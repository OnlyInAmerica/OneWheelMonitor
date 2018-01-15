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

class OneWheelManager : NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, AVSpeechSynthesizerDelegate {
    
    private(set) var startRequested = false
    
    // Listener
    var connListener: ConnectionListener?
    
    // Audio feedback
    public var audioFeedback = false
    
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
    private let data = OneWheelLocalData()

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

    func start() {
        startRequested = true
        cm = CBCentralManager.init(delegate: self, queue: nil, options: nil)
        // delegate awaits poweredOn state
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
    }
    
    private func findDevice() {
        let cm = self.cm!
        if let primaryDeviceUuid = data.getPrimaryDeviceUUID() {
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
            data.setPrimaryDeviceUUID(device.identifier)
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
            if audioFeedback {
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
            peripheral.discoverCharacteristics([characteristicRpmUuid, characteristicErrorUuid, characteristicSafetyHeadroomUuid, characteristicBatteryUuid, characteristicTempUuid, /* Don't seem to be peroperly interpreting these values yet: characteristicLastErrorUuid*/], for: service)
        }
    }
    
    // Service characteristics discovered
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        NSLog("Peripheral service characteristics discovered with error \(error)")

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                NSLog("Peripheral enabling notification for characteristic \(characteristic)")
                peripheral.setNotifyValue(true, for: characteristic)
                if (characteristic.uuid == characteristicBatteryUuid || characteristic.uuid == characteristicSafetyHeadroomUuid || characteristic.uuid == characteristicTempUuid || characteristic.uuid == characteristicLastErrorUuid) {
                    peripheral.readValue(for: characteristic)
                    //peripheral.discoverDescriptors(for: characteristic)
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
        
        if audioFeedback {
            queueHighAlert("Connected")
        }
    }
    
    private func handleUpdatedStatus(_ s: OneWheelStatus) {
        let newState = OneWheelState(time: Date.init(), riderPresent: s.riderDetected, footPad1: s.riderDetectPad1, footPad2: s.riderDetectPad2, icsuFault: s.icsuFault, icsvFault: s.icsvFault, charging: s.charging, bmsCtrlComms: s.bmsCtrlComms, brokenCapacitor: s.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: lastState.safetyHeadroom, batteryLevel: lastState.batteryLevel, motorTemp: lastState.motorTemp, controllerTemp: lastState.controllerTemp, lastErrorCode: lastState.lastErrorCode, lastErrorCodeVal: lastState.lastErrorCodeVal)
        try? db?.insertState(state: newState)
        if audioFeedback {
            let delta = newState.describeDelta(prev: lastState)
            switch delta {
            case "Heel Off. ":
                alertThrottler.scheduleAlert(key: "heel-off", alertQueue: alertQueue, alert: speechManager.createSpeechAlert(priority: .HIGH, message: delta))
            case "Heel On. ":
                alertThrottler.cancelAlert(key: "heel-off", alertQueue: alertQueue, ifNoOutstandingAlert: speechManager.createSpeechAlert(priority: .HIGH, message: delta))
            case "Toe Off. ":
                alertThrottler.scheduleAlert(key: "toe-off", alertQueue: alertQueue, alert: speechManager.createSpeechAlert(priority: .HIGH, message: delta))
            case "Toe On. ":
                alertThrottler.cancelAlert(key: "toe-off", alertQueue: alertQueue, ifNoOutstandingAlert: speechManager.createSpeechAlert(priority: .HIGH, message: delta))
            default:
                // All OneWheelStatus changes are high priority, with the possible exception of charging
                queueHighAlert(delta)
            }
        }
        lastState = newState
    }
    
    private func handleUpdatedRpm(_ rpm: Int16) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: rpm, safetyHeadroom: lastState.safetyHeadroom, batteryLevel: lastState.batteryLevel, motorTemp: lastState.motorTemp, controllerTemp: lastState.controllerTemp, lastErrorCode: lastState.lastErrorCode, lastErrorCodeVal: lastState.lastErrorCodeVal)
        // Lets not create new events for every speed update. Eventually let's create another table or in-memory structure for speed
        try? db?.insertState(state: newState)
        let mph = newState.mph()
        if audioFeedback && speedMonitor.passedBenchmark(mph){
            let mphRound = Int(mph)
            queueHighAlert("Speed \(mphRound)")
        }
        lastState = newState
    }
    
    private func handleUpdatedSafetyHeadroom(_ sh: UInt8) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: sh, batteryLevel: lastState.batteryLevel, motorTemp: lastState.motorTemp, controllerTemp: lastState.controllerTemp, lastErrorCode: lastState.lastErrorCode, lastErrorCodeVal: lastState.lastErrorCodeVal)
        try? db?.insertState(state: newState)
        if audioFeedback && headroomMonitor.passedBenchmark(Double(sh)) {
            queueHighAlert("Headroom \(sh)")
        }
        lastState = newState
    }
    
    private func handleUpdatedBattery(_ batteryLevelInt: UInt8) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: lastState.safetyHeadroom, batteryLevel: batteryLevelInt, motorTemp: lastState.motorTemp, controllerTemp: lastState.controllerTemp, lastErrorCode: lastState.lastErrorCode, lastErrorCodeVal: lastState.lastErrorCodeVal)
        //try? db?.insertState(state: newState) Rpm can catch these updates to avoid db bloat?
        let batteryLevel = Double(batteryLevelInt)
        if audioFeedback && batteryMonitor.passedBenchmark(batteryLevel){
            // Only speak the benchmark battery val. e.g: 70%, not 69%
            let currentBattBenchmark = batteryMonitor.getBenchmarkVal(batteryMonitor.lastBenchmarkIdx) // "last"BenchmarkIdx relative to last call to #passedBenchmark
            let lastBattBenchmark = batteryMonitor.getBenchmarkVal(batteryMonitor.lastLastBenchmarkIdx)

            let currentBattDiff = abs(currentBattBenchmark - batteryLevel)
            let lastBattDiff = abs(lastBattBenchmark - batteryLevel)
            if (currentBattDiff < lastBattDiff) {
                queueLowAlert("Battery \(Int(currentBattBenchmark))")
            } else {
                queueLowAlert("Battery \(Int(lastBattBenchmark))")
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
        try? db?.insertState(state: newState)
        if audioFeedback {
            queueHighAlert("Last Error \(newState.lastErrorDescription())")
        }
        lastState = newState
    }
    
    private func queueLowAlert(_ message: String) {
        self.alertQueue.queueAlert(speechManager.createSpeechAlert(priority: .LOW, message: message))
    }
    
    private func queueHighAlert(_ message: String) {
        self.alertQueue.queueAlert(speechManager.createSpeechAlert(priority: .HIGH, message: message))
    }
    
    private func celsiusToFahrenheit(celsius: Double) -> Double {
        return ((9.0 / 5.0) * celsius) + 32
    }
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
    
    private let peripheral: CBPeripheral
    
    init(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }
}

class OneWheelLocalData {
    private let keyUuid = "ow_uuid"

    private let data = UserDefaults.standard
    
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
}

// Allows scheduling alerts for a short delay to allow short-lived events to be cancelled
class CancelableAlertThrottler {
    var scheduledAlerts = [String:Timer]()
    let thresholdS = 0.200
    
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
    
    func cancelAlert(key: String, alertQueue: AlertQueue, ifNoOutstandingAlert: Alert) {
        if let timer = scheduledAlerts[key] {
            NSLog("Cancelling \(key) alert")
            timer.invalidate()
        } else {
            alertQueue.queueAlert(ifNoOutstandingAlert)
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
        let benchmarks = [10.0, 12.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0, 27.0, 28.0]
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
