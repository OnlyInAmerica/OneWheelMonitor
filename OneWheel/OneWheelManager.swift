//
//  OneWheelManager.swift
//  OneWheel
//
//  Created by David Brodsky on 12/30/17.
//  Copyright © 2017 David Brodsky. All rights reserved.
//

import Foundation
import CoreBluetooth
import AVFoundation
import UIKit

class OneWheelManager : NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, AVSpeechSynthesizerDelegate {
    
    private(set) var startRequested = false
    
    // Listener
    var connListener: ConnectionListener?
    
    // Audio feedback
    private var headphonesPresent = checkHeadphonesPresent()
    private var shouldSoundAlerts: Bool {
        get {
            return userPrefs.getAudioAlertsEnabled() && headphonesPresent
        }
    }
    
    private let speechManager = SpeechAlertManager()
    private let alertQueue = AlertQueue()
    
    // Used to throttle alert generation
    private let speedMonitor: BenchmarkMonitor = SpeedMonitor()
    private let batteryMonitor: BenchmarkMonitor = BatteryMonitor()
    private let headroomMonitor: BenchmarkMonitor = HeadroomMonitor()
    private let alertThrottler = CancelableAlertThrottler()

    // Persistence
    public var db : OneWheelDatabase?
    private var lastState = OneWheelState()
    private let userPrefs = OneWheelLocalData()
    
    private let bgQueue = DispatchQueue(label: "bgQueue")
    private let bgDbTransactionLength = 20 // When in background, group inserts to conserve CPU
    private var bgStateQueue = [OneWheelState]()

    // Bluetooth
    private var cm : CBCentralManager?
    
    private var connectingDevice : CBPeripheral?
    private var connectedDevice : CBPeripheral?
    
    // Bluetooth - UUIDs
    let serviceUuid = CBUUID.init(string: "e659f300-ea98-11e3-ac10-0800200c9a66")
    
    let characteristicErrorUuid = CBUUID.init(string: "e659f30f-ea98-11e3-ac10-0800200c9a66")
    let characteristicSafetyHeadroomUuid = CBUUID.init(string: "e659f317-ea98-11e3-ac10-0800200c9a66")
    let characteristicRpmUuid = CBUUID.init(string: "e659f30b-ea98-11e3-ac10-0800200c9a66")
    let characteristicBatteryUuid = CBUUID.init(string: "e659f303-ea98-11e3-ac10-0800200c9a66")
    let characteristicTempUuid = CBUUID.init(string: "e659f310-ea98-11e3-ac10-0800200c9a66")
    let characteristicLastErrorUuid = CBUUID.init(string: "e659f31c-ea98-11e3-ac10-0800200c9a66")
    let characteristicLightsUuid = CBUUID.init(string: "e659f30c-ea98-11e3-ac10-0800200c9a66")
    
    private var characteristicForUUID = [CBUUID: CBCharacteristic]()
    
    private let tempPollingInterval: TimeInterval = 10.0
    private var lastTempPollDate: Date?
    
    // MARK : Public API
    
    func start() {
        startRequested = true
        cm = CBCentralManager.init(delegate: self, queue: nil, options: nil)
        // delegate awaits poweredOn state
        
        headphonesPresent = checkHeadphonesPresent()
        setHeadphoneNotificationsEnabled(true)
    }
    
    func discoveredDevices() -> [OneWheel] {
        return [] // TODO
    }
    
    func stop() {
        startRequested = false
        cm?.stopScan()
        if let device = connectedDevice {
            cm?.cancelPeripheralConnection(device)
        }
        setHeadphoneNotificationsEnabled(false)
    }
    
    func toggleLights(onewheel: OneWheel, on: Bool) {
        toggleLights(peripheral: onewheel.peripheral, on: on)
    }
    
    // MARK : Private APIs
    
    private func setHeadphoneNotificationsEnabled(_ enabled: Bool) {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVAudioSessionRouteChange, object: nil)
        if enabled {
            NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange(_:)), name: NSNotification.Name.AVAudioSessionRouteChange, object: nil)
        }
    }
    
    private func toggleLights(peripheral: CBPeripheral, on: Bool) {
        if let lightChar = self.characteristicForUUID[characteristicLightsUuid] {
            let lightsOn = UInt16(on ? 1 : 0)
            var value = CFSwapInt16HostToBig(lightsOn)
            let data = withUnsafePointer(to: &value) {
                Data(bytes: UnsafePointer($0), count: MemoryLayout.size(ofValue: lightsOn))
            }
            NSLog("Writing lights \(on ? "on" : "off")")
            peripheral.writeValue(data, for: lightChar, type: CBCharacteristicWriteType.withResponse)
        } else {
            NSLog("Cannot toggle lights, lighting characteristic not yet discovered")
        }
    }
    
    private func findDevice() {
        let cm = self.cm!
        if let primaryDeviceUuid = userPrefs.getPrimaryDeviceUUID() {
            // Connect known device
            let knownDevices = cm.retrievePeripherals(withIdentifiers: [primaryDeviceUuid])
            if knownDevices.count == 0 {
                let connectedDevices = cm.retrieveConnectedPeripherals(withServices: [serviceUuid])
                if connectedDevices.count == 1 {
                    // Locally connect to pre-connected peripheral
                    let targetDevice = knownDevices[0]
                    NSLog("Connecting locally to pre-connected device \(targetDevice.identifier)")
                    connectDevice(targetDevice)
                } else {
                    NSLog("Unexpected number (\(knownDevices.count) of connected CBPeripherals matching uuid \(primaryDeviceUuid)")
                    return
                }
            } else if knownDevices.count > 1 {
                NSLog("Multiple (\(knownDevices.count) known CBPeripherals matching uuid \(primaryDeviceUuid)")
                return
            } else {
                let targetDevice = knownDevices[0]
                NSLog("Connecting to known device \(targetDevice.identifier)")
                connectDevice(targetDevice)
            }
        } else {
            // Discover devices
            NSLog("Beginning CBPeripheral scan for service \(serviceUuid.uuidString)")
            cm.scanForPeripherals(withServices: [serviceUuid], options: nil)
            // Delegate awaits discovery events
        }
    }
    
    private func connectDevice(_ device: CBPeripheral) {
        if let cm = self.cm {
            userPrefs.setPrimaryDeviceUUID(device.identifier)
            connectingDevice = device
            cm.connect(device, options: nil)
            // Delegate awaits connetion update
        }
    }
    
    // MARK: CBManagerDelegate
    
    // Peripheral discovered
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        NSLog("Peripheral discovered: \(peripheral.identifier) - \(peripheral.name ?? "No Name")")
        connectDevice(peripheral)
    }
    
    // Peripheral connected
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        NSLog("Peripheral connected: \(peripheral.identifier) - \(peripheral.name ?? "No Name")")
        handleConnectedDevice(peripheral)
    }
    
    // Peripheral disconnected
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // TODO : Allow user to control if auto re-connection is desired
        NSLog("Peripheral disconnected: \(peripheral.identifier) - \(peripheral.name ?? "No Name")")
        if peripheral.identifier == connectedDevice?.identifier {
            NSLog("Reconnecting disconnected peripheral")
            if shouldSoundAlerts {
                if startRequested {
                    queueHighAlert("Reconnecting")
                } else {
                    queueHighAlert("Disconnected")
                }
            }
            connListener?.onDisconnected(oneWheel: OneWheel(peripheral))
            if startRequested {
                connectDevice(peripheral)
            }
        }
    }
    
    // CentralManager state changed
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        NSLog("CentralManager state changed to \(central.state)")
        if central.state == CBManagerState.poweredOn {
            findDevice()
        }
    }
    
    // MARK: CBPeripheralDelegate
    
    // Services discovered
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        NSLog("Peripheral services discovered with error \(error)")
        if let service = peripheral.services?.filter({ (service) -> Bool in
            return service.uuid == serviceUuid
        }).first {
            NSLog("Peripheral target service discovered. Discovering characteristics")
            peripheral.discoverCharacteristics([characteristicRpmUuid, characteristicErrorUuid, characteristicSafetyHeadroomUuid, characteristicBatteryUuid, characteristicTempUuid, characteristicLightsUuid /* Don't seem to be properly interpreting these values yet: characteristicLastErrorUuid*/], for: service)
        }
    }
    
    // Service characteristics discovered
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        NSLog("Peripheral service characteristics discovered with error \(error)")
        let now = Date()
        
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                NSLog("Peripheral enabling notification for characteristic \(characteristic)")
                // To minimize bg wakeups, let speed be the only rapidly changing subscription
                // Upon speed notifications, we can conditionally poll temperature e.g
                let uuid = characteristic.uuid
                characteristicForUUID[uuid] = characteristic
                if (uuid != characteristicTempUuid && uuid != characteristicLightsUuid) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                if (uuid == characteristicBatteryUuid || uuid == characteristicTempUuid /* Don't seem to be peroperly interpreting these values yet:|| characteristic.uuid == characteristicLastErrorUuid*/) {
                    peripheral.readValue(for: characteristic)
                    if uuid == characteristicTempUuid {
                        lastTempPollDate = now
                    }
                    //peripheral.discoverDescriptors(for: characteristic)
                } else if (uuid == characteristicLightsUuid) {
                    let hour = Calendar.current.component(.hour, from: now)
                    let isProbablyDark = (hour > 17 || hour < 8)
                    NSLog("Current hour is \(hour). Is probably dark: \(isProbablyDark)")
                    toggleLights(peripheral: peripheral, on: isProbablyDark)
                }
            }
        }
    }
    
    // Characteristic descriptor discovered
    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        NSLog("Got descriptor for \(characteristic.uuid) : \(characteristic.descriptors)")
    }
    
    // Characterisitc notification register result
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        NSLog("Peripheral notification registered for \(characteristic.uuid) with error \(error)")
    }
    
    // Characterisitic updated
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        switch characteristic.uuid {
        case characteristicErrorUuid:
            if let value = characteristic.value {
                let intValue: UInt8 = value.withUnsafeBytes { $0.pointee }
                let status = OneWheelStatus(intValue)
                NSLog("Peripheral error characteristic changed with status \(value) -> \(status)")
                handleUpdatedStatus(status)
            } else {
                NSLog("Peripheral error charactersitic changed with no value")
            }

        case characteristicSafetyHeadroomUuid:
            if let value = characteristic.value {
                let intValue = Int16(bigEndian: value.withUnsafeBytes { $0.pointee })
                NSLog("Peripheral headroom characteristic changed with value \(value.base64EncodedString()) -> \(intValue)")
                if intValue <= UInt8.max && intValue >= UInt8.min { // TODO : Is this actually a Int16?
                    handleUpdatedSafetyHeadroom(UInt8(intValue))
                }
            } else {
                NSLog("Peripheral headroom charactersitic changed with no value")
            }
            
        case characteristicRpmUuid:
            if let value = characteristic.value {
                let intValue = Int16(bigEndian: value.withUnsafeBytes { $0.pointee })
                handleUpdatedRpm(intValue)
            } else {
                NSLog("Peripheral rpm charactersitic changed with no value")
            }
            
        case characteristicBatteryUuid:
            if let value = characteristic.value {
                let intValue = Int16(bigEndian: value.withUnsafeBytes { $0.pointee })
                NSLog("Peripheral battery characteristic changed \(value.base64EncodedString()) -> \(intValue)")
                if intValue <= UInt8.max && intValue >= UInt8.min { // TODO : Is this actually a Int16?
                    handleUpdatedBattery(UInt8(intValue))
                }
            } else {
                NSLog("Peripheral battery level charactersitic changed with no value")
            }
            
        case characteristicTempUuid:
            if let value = characteristic.value {
                let controllerTemp: UInt8 = value.withUnsafeBytes { $0.pointee }
                let motorTemp: UInt8 = value.withUnsafeBytes { $0.pointee + 1 }

                NSLog("Peripheral temperature characteristic changed motor: \(motorTemp) controller: \(controllerTemp)")
                handleUpdatedTemperature(motorTempC: motorTemp, controllerTempC: controllerTemp)
            } else {
                NSLog("Peripheral temperature charactersitic changed with no value")
            }
            
        case characteristicLastErrorUuid:
            if let value = characteristic.value {
                let errorCode1: UInt8 = value.withUnsafeBytes { $0.pointee }
                let errorCode2: UInt8 = value.withUnsafeBytes { $0.pointee + 1 }
                
                NSLog("Peripheral last error characteristic changed \(errorCode1) - \(errorCodeMap[errorCode1]) - \(errorCode2)")
                handleUpdatedLastErrorCode(errorCode1: errorCode1, errorCode2: errorCode2)
            } else {
                NSLog("Peripheral last error charactersitic changed with no value")
            }
            
        default:
            NSLog("Peripheral unknown charactersitic (\(characteristic.uuid)) changed")
        }
    }
    
    // MARK: Handle property update
    
    private func handleConnectedDevice(_ device: CBPeripheral) {
        connectingDevice = nil
        connectedDevice = device
        device.delegate = self
        
        connListener?.onConnected(oneWheel: OneWheel(device))
        device.discoverServices([serviceUuid])
        // Delegate awaits service discovery
        
        if shouldSoundAlerts {
            queueHighAlert("Connected")
        }
    }
    
    private func handleUpdatedStatus(_ s: OneWheelStatus) {
        let newState = OneWheelState(time: Date.init(), riderPresent: s.riderDetected, footPad1: s.riderDetectPad1, footPad2: s.riderDetectPad2, icsuFault: s.icsuFault, icsvFault: s.icsvFault, charging: s.charging, bmsCtrlComms: s.bmsCtrlComms, brokenCapacitor: s.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: lastState.safetyHeadroom, batteryLevel: lastState.batteryLevel, motorTemp: lastState.motorTemp, controllerTemp: lastState.controllerTemp, lastErrorCode: lastState.lastErrorCode, lastErrorCodeVal: lastState.lastErrorCodeVal)
        writeState(newState)
        
        if shouldSoundAlerts {
            
            let feetOffInMotion = newState.feetOffDuringMotion() && !lastState.feetOffDuringMotion()
            
            var delta = newState.describeDelta(prev: lastState)
            
            // If feet off in motion, we'll send a special high priority alert as the last item (to supercede any other announcements). The
            // feet off announcement can also replace the Heel/Toe Off announcement.
            if feetOffInMotion {
                delta = delta.replacingOccurrences(of: "Heel Off. ", with: "").replacingOccurrences(of: "Toe Off.", with: "")
            }
            
            // This is a jank way of adding a time threshold to Toe/Heel off alerts. By checking describeState like this we can
            // easily tell if the *only* delta in the new state is a toe or heel change. Since these changes are especially spurious, they're generally
            // more nuisance than help if not throttled
            switch delta {
            case "Heel Off. ":
                if newState.riderPresent {
                    alertThrottler.scheduleAlert(key: "heel-off", alertQueue: alertQueue, alert: speechManager.createSpeechAlert(priority: .HIGH, message: delta, key:"Heel"))
                }
            case "Heel On. ":
                if newState.riderPresent {
                    alertThrottler.cancelAlert(key: "heel-off", alertQueue: alertQueue, ifNoOutstandingAlert: speechManager.createSpeechAlert(priority: .HIGH, message: delta, key:"Heel"))
                }
            case "Toe Off. ":
                if newState.riderPresent {
                    alertThrottler.scheduleAlert(key: "toe-off", alertQueue: alertQueue, alert: speechManager.createSpeechAlert(priority: .HIGH, message: delta, key:"Toe"))
                }
            case "Toe On. ":
                if newState.riderPresent {
                    alertThrottler.cancelAlert(key: "toe-off", alertQueue: alertQueue, ifNoOutstandingAlert: speechManager.createSpeechAlert(priority: .HIGH, message: delta, key:"Toe"))
                }
            case "Rider Off. ":
                alertThrottler.cancelAlert(key: "toe-off", alertQueue: alertQueue, ifNoOutstandingAlert: nil)
                alertThrottler.cancelAlert(key: "heel-off", alertQueue: alertQueue, ifNoOutstandingAlert: nil)
                queueHighAlert(delta, key: "Rider")
                
            default:
                
                // All OneWheelStatus changes are high priority, with the possible exception of charging
                queueHighAlert(delta)
            }
            
            // Queue this last so it's at the head of the queue (High priority alerts skip to front)
            if feetOffInMotion {
                queueHighAlert("Feet off", key: "Feet")
            }
        }
        lastState = newState
    }
    
    private func handleUpdatedRpm(_ rpm: Int16) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: rpm, safetyHeadroom: lastState.safetyHeadroom, batteryLevel: lastState.batteryLevel, motorTemp: lastState.motorTemp, controllerTemp: lastState.controllerTemp, lastErrorCode: lastState.lastErrorCode, lastErrorCodeVal: lastState.lastErrorCodeVal)
        writeState(newState)
        let mph = newState.mph()
        let lastSpeedBenchmark = speedMonitor.lastBenchmarkIdx
        if shouldSoundAlerts && speedMonitor.passedBenchmark(mph) && /* Only announce speed increases */ lastSpeedBenchmark > speedMonitor.lastBenchmarkIdx {
            NSLog("Announcing speed change from \(lastSpeedBenchmark) to \(speedMonitor.lastBenchmarkIdx)")
            let mphRound = Int(mph)
            queueHighAlert("Speed \(mphRound)", key: "Speed", shortMessage: "\(mphRound)")
        }
        
        let now = Date()
        if lastTempPollDate != nil && lastTempPollDate!.addingTimeInterval(tempPollingInterval) < now {
            if let tempCharacteristic = characteristicForUUID[characteristicTempUuid] {
                connectedDevice?.readValue(for: tempCharacteristic)
                lastTempPollDate = Date()
            }
        }
        lastState = newState
    }
    
    private func handleUpdatedSafetyHeadroom(_ sh: UInt8) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: sh, batteryLevel: lastState.batteryLevel, motorTemp: lastState.motorTemp, controllerTemp: lastState.controllerTemp, lastErrorCode: lastState.lastErrorCode, lastErrorCodeVal: lastState.lastErrorCodeVal)
        writeState(newState)
        if shouldSoundAlerts && headroomMonitor.passedBenchmark(Double(sh)) {
            queueHighAlert("Headroom \(sh)", key: "Headroom")
        }
        lastState = newState
    }
    
    private func handleUpdatedBattery(_ batteryLevelInt: UInt8) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: lastState.safetyHeadroom, batteryLevel: batteryLevelInt, motorTemp: lastState.motorTemp, controllerTemp: lastState.controllerTemp, lastErrorCode: lastState.lastErrorCode, lastErrorCodeVal: lastState.lastErrorCodeVal)
        // If we're moving, let rpm be the driver of db updates
        if newState.rpm == 0 {
            try? db?.insertState(state: newState)
        }
        let batteryLevel = Double(batteryLevelInt)
        if shouldSoundAlerts && batteryMonitor.passedBenchmark(batteryLevel){
            // Only speak the benchmark battery val. e.g: 70%, not 69%
            let currentBattBenchmark = batteryMonitor.getBenchmarkVal(batteryMonitor.lastBenchmarkIdx) // "last"BenchmarkIdx relative to last call to #passedBenchmark
            let lastBattBenchmark = batteryMonitor.getBenchmarkVal(batteryMonitor.lastLastBenchmarkIdx)

            let currentBattDiff = abs(currentBattBenchmark - batteryLevel)
            let lastBattDiff = abs(lastBattBenchmark - batteryLevel)
            if (currentBattDiff < lastBattDiff) {
                queueLowAlert("Battery \(Int(currentBattBenchmark))", key: "Batt")
            } else {
                queueLowAlert("Battery \(Int(lastBattBenchmark))", key: "Batt")
            }
        }
        lastState = newState
    }
    
    private func handleUpdatedTemperature(motorTempC: UInt8, controllerTempC: UInt8) {
        let motorTempF = celsiusToFahrenheit(celsius: Double(motorTempC))
        let controllerTempF = celsiusToFahrenheit(celsius: Double(controllerTempC))
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: lastState.safetyHeadroom, batteryLevel: lastState.batteryLevel, motorTemp: UInt8(motorTempF), controllerTemp: UInt8(controllerTempF), lastErrorCode: lastState.lastErrorCode, lastErrorCodeVal: lastState.lastErrorCodeVal)
        //try? db?.insertState(state: newState) //  Rpm can catch these updates to avoid db bloat?
        // TODO : Alert when temperatures hit danger zones
        lastState = newState
    }
    
    private func handleUpdatedLastErrorCode(errorCode1: UInt8, errorCode2: UInt8) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: lastState.safetyHeadroom, batteryLevel: lastState.batteryLevel, motorTemp: lastState.motorTemp, controllerTemp: lastState.controllerTemp, lastErrorCode: errorCode1, lastErrorCodeVal: errorCode2)
        writeState(newState)
        if shouldSoundAlerts {
            queueHighAlert("Last Error \(newState.lastErrorDescription())")
        }
        lastState = newState
    }
    
    private func queueLowAlert(_ message: String, key: String? = nil, shortMessage: String? = nil) {
        self.alertQueue.queueAlert(speechManager.createSpeechAlert(priority: .LOW, message: message, key: key, shortMessage: shortMessage))
    }
    
    private func queueHighAlert(_ message: String, key: String? = nil, shortMessage: String? = nil) {
        self.alertQueue.queueAlert(speechManager.createSpeechAlert(priority: .HIGH, message: message, key: key, shortMessage: shortMessage))
    }
    
    private func celsiusToFahrenheit(celsius: Double) -> Double {
        return ((9.0 / 5.0) * celsius) + 32
    }
    
    private func writeState(_ state: OneWheelState) {
        bgQueue.sync {
            let uiState = UIApplication.shared.applicationState
            if uiState == .active {
                if bgStateQueue.count > 0 {
                    flushBgStateQueueInternal()
                }
                try? db?.insertState(state: state)
            } else {
                bgStateQueue.append(state)
                if bgStateQueue.count >= bgDbTransactionLength {
                    flushBgStateQueueInternal()
                }
            }
        }
    }
    
    func flushBgStateQueue() {
        bgQueue.sync {
            flushBgStateQueueInternal()
        }
    }
    
    // Should be called from bgQueue
    private func flushBgStateQueueInternal() {
        if bgStateQueue.count > 0 {
            NSLog("Flush bg state queue")
            try? db?.insertStates(states: bgStateQueue)
            bgStateQueue.removeAll()
        }
    }
    
    // MARK : Audio route handling
    @objc func handleAudioRouteChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let reasonRaw = userInfo[AVAudioSessionRouteChangeReasonKey] as? NSNumber,
            let reason = AVAudioSessionRouteChangeReason(rawValue: reasonRaw.uintValue)
        else {
            NSLog("handleAudioRouteChange Error: Failed to get routeChange")
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            fallthrough
        case .newDeviceAvailable:
            self.headphonesPresent = checkHeadphonesPresent()
        default:
            NSLog("handleAudioRouteChange Error: Unknown reason: \(reason)")
        }
    }
}

private func checkHeadphonesPresent() -> Bool {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    for output in outputs {
        switch output.portType {
        case AVAudioSessionPortBluetoothA2DP:
            fallthrough
        case AVAudioSessionPortHeadphones:
            NSLog("checkHeadphonesPresent -> true")
            return true
        default:
            continue
        }
    }
    NSLog("checkHeadphonesPresent -> false")
    return false
}

extension UInt8 {
    func getBit(_ num: UInt8) -> Bool {
        let mask : UInt8 = 0x01 << num
        return (self & mask) == mask
    }
}

// Struct sent as characteristicErrorUuid value
class OneWheelStatus : CustomStringConvertible {

    let riderDetected: Bool
    let riderDetectPad1: Bool
    let riderDetectPad2: Bool
    let icsuFault: Bool
    let icsvFault: Bool
    let charging: Bool
    let bmsCtrlComms: Bool
    let brokenCapacitor: Bool
    
    var description: String {
        return "OneWheelStatus: riderDetected \(riderDetected) pad1 \(riderDetectPad1) pad2 \(riderDetectPad2) iscuFault \(icsuFault) icsvFault \(icsvFault) charging \(charging) bmsCtrlComms \(bmsCtrlComms) brokenCapacitor \(brokenCapacitor)"
    }
    
    init(_ data : UInt8) {
        riderDetected = data.getBit(0)
        riderDetectPad1 = data.getBit(1)
        riderDetectPad2 = data.getBit(2)
        icsuFault = data.getBit(3)
        icsvFault = data.getBit(4)
        charging = data.getBit(5)
        bmsCtrlComms = data.getBit(6)
        brokenCapacitor = data.getBit(7)
    }
}

class OneWheel {
    
    var name: String? {
        get {
            return self.peripheral.name
        }
    }
    
    let peripheral: CBPeripheral
    
    init(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }
}

class OneWheelLocalData {
    private let keyUuid = "ow_uuid"
    private let keyAudioAlerts = "ow_audio_alerts"

    private let data = UserDefaults.standard
    
    init() {
        data.register(defaults: [keyAudioAlerts : true])
    }
    
    func clearPrimaryDeviceUUID() {
        data.removeObject(forKey: keyUuid)
    }
    
    func setPrimaryDeviceUUID(_ uuid: UUID) {
        data.setValue(uuid.uuidString, forKeyPath: keyUuid)
    }
    
    func getPrimaryDeviceUUID() -> UUID? {
        if let stringUuid = data.string(forKey: keyUuid) {
            return UUID.init(uuidString: stringUuid)
        } else {
            return nil
        }
    }
    
    func setAudioAlertsEnabled(_ enabled: Bool) {
        data.setValue(enabled, forKeyPath: keyAudioAlerts)
    }
    
    func getAudioAlertsEnabled() -> Bool {
        return data.bool(forKey: keyAudioAlerts)
    }
}

// Allows scheduling alerts for a short delay to allow short-lived events to be cancelled
class CancelableAlertThrottler {
    private var scheduledAlerts = [String:Timer]()
    var thresholdS = 1.450
    
    func scheduleAlert(key: String, alertQueue: AlertQueue, alert: Alert) {
        if let existingTimer = scheduledAlerts[key] {
            existingTimer.invalidate()
            scheduledAlerts.removeValue(forKey: key)
        }
        
        let timer = Timer.scheduledTimer(withTimeInterval: thresholdS, repeats: false, block: { (timer) in
            NSLog("Queueing \(key) alert after \(self.thresholdS)s")
            alertQueue.queueAlert(alert)
            self.scheduledAlerts.removeValue(forKey: key)
        })
        scheduledAlerts[key] = timer
    }
    
    func cancelAlert(key: String, alertQueue: AlertQueue, ifNoOutstandingAlert: Alert?) {
        if let timer = scheduledAlerts[key] {
            NSLog("Cancelling \(key) alert")
            timer.invalidate()
        } else if let newAlert = ifNoOutstandingAlert {
            alertQueue.queueAlert(newAlert)
        }
    }
}

// Processes a changing Double value into discrete benchmark passing events
class BenchmarkMonitor {
    let benchmarks: [Double]
    let hysteresis: Double
    
    // A benchmark index of benchmarks.count indicates we passed no benchmarks, otherwise value indicates that indexed benchmark passed.
    var lastBenchmarkIdx = 0
    var lastLastBenchmarkIdx = 0
    
    init(benchmarks: [Double], hysteresis: Double) {
        self.benchmarks = benchmarks.sorted().reversed()
        self.hysteresis = hysteresis
        self.lastBenchmarkIdx = benchmarks.count
        self.lastLastBenchmarkIdx = benchmarks.count
    }
    
    func passedBenchmark(_ val: Double) -> Bool {
        let newBenchmarkIdx = (benchmarks.index(where: { (benchmarkVal) -> Bool in
            val >= benchmarkVal
        }) ?? benchmarks.count)
        NSLog("idx \(lastBenchmarkIdx) -> \(newBenchmarkIdx)")
        // Apply Hysteresis when downgrading speed benchmark
        if newBenchmarkIdx == lastLastBenchmarkIdx && abs(getBenchmarkVal(lastBenchmarkIdx) - val) < hysteresis {
            return false
        }
        
        let isNew = newBenchmarkIdx != lastBenchmarkIdx
        lastLastBenchmarkIdx = lastBenchmarkIdx
        lastBenchmarkIdx = newBenchmarkIdx
        return isNew
    }
    
    func getBenchmarkVal(_ index: Int) -> Double {
        if index >= benchmarks.count {
            return benchmarks.last! // TODO : assumes DESC sort
        }
        return benchmarks[index]
    }
}

class SpeedMonitor: BenchmarkMonitor {
    
    init() {
        let benchmarks = [5.0, 10.0, 12.0, 14.0] + Array(stride(from: 15.0, through: 30.0, by: 1.0))
        let hysteresis = 1.5
        super.init(benchmarks: benchmarks, hysteresis: hysteresis)
    }
}

class BatteryMonitor: BenchmarkMonitor {
    
    init() {
        // 1% increments from [0-10]%, then 5% increments
        let benchmarks = Array(stride(from: 0.0, to: 10.0, by: 1.0)) + Array(stride(from: 10.0, to: 100.0, by: 5.0))
        let hysteresis = 1.0
        super.init(benchmarks: benchmarks, hysteresis: hysteresis)
    }
}

class HeadroomMonitor: BenchmarkMonitor {
    
    init() {
        // 10% increments, including 100%. So 99% should be first trigger
        let benchmarks = Array(stride(from: 0.0, to: 110.0, by: 10.0))
        let hysteresis = 1.0
        super.init(benchmarks: benchmarks, hysteresis: hysteresis)
    }
}

protocol ConnectionListener {
    func onConnected(oneWheel: OneWheel)
    func onDisconnected(oneWheel: OneWheel)
}
