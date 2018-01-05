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
    
    var startRequested = false
    
    // Listener
    var connListener: ConnectionListener?
    
    // Audio feedback
    public var audioFeedback = false {
        didSet {
            if audioFeedback {
                speechSynth = AVSpeechSynthesizer()
                speechSynth?.delegate = self
                speechVoice = AVSpeechSynthesisVoice(language: "en-US")
                
                try? AVAudioSession.sharedInstance().setCategory(
                    AVAudioSessionCategoryPlayback,
                    with:.mixWithOthers)
            }
        }
    }
    
    private var speechSynth : AVSpeechSynthesizer?
    private var speechVoice : AVSpeechSynthesisVoice?
    
    // Used to throttle speed audio alerts
    private let speedMonitor: BenchmarkMonitor = SpeedMonitor()
    private let batteryMonitor: BenchmarkMonitor = BatteryMonitor()

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
    
    // MARK: AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false)
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
                    speak("Reconnecting")
                } else {
                    speak("Disconnected")
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
            peripheral.discoverCharacteristics([characteristicRpmUuid, characteristicErrorUuid, characteristicSafetyHeadroomUuid, characteristicBatteryUuid], for: service)
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
                if (characteristic.uuid == characteristicBatteryUuid || characteristic.uuid == characteristicSafetyHeadroomUuid) {
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
        default:
            NSLog("Peripheral unknown charactersitic (\(characteristic.uuid)) changed")
        }
    }
    
    private func handleConnectedDevice(_ device: CBPeripheral) {
        connectingDevice = nil
        connectedDevice = device
        device.delegate = self
        
        connListener?.onConnected(oneWheel: OneWheel(device))
        device.discoverServices([serviceUuid])
        // Delegate awaits service discovery
        
        if audioFeedback {
            speak("Connected")
        }
    }
    
    private func handleUpdatedStatus(_ s: OneWheelStatus) {
        let newState = OneWheelState(time: Date.init(), riderPresent: s.riderDetected, footPad1: s.riderDetectPad1, footPad2: s.riderDetectPad2, icsuFault: s.icsuFault, icsvFault: s.icsvFault, charging: s.charging, bmsCtrlComms: s.bmsCtrlComms, brokenCapacitor: s.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: lastState.safetyHeadroom, batteryLevel: lastState.batteryLevel)
        try? db?.insertState(state: newState)
        if audioFeedback {
            speak(newState.describeDelta(prev: lastState))
        }
        lastState = newState
    }
    
    private func handleUpdatedRpm(_ rpm: Int16) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: rpm, safetyHeadroom: lastState.safetyHeadroom, batteryLevel: lastState.batteryLevel)
        // Lets not create new events for every speed update. Eventually let's create another table or in-memory structure for speed
        try? db?.insertState(state: newState)
        let mph = newState.mph()
        if audioFeedback && speedMonitor.passedBenchmark(mph){
            let mphRound = Int(mph)
            speak("Speed \(mphRound)")
        }
        lastState = newState
    }
    
    private func handleUpdatedSafetyHeadroom(_ sh: UInt8) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: sh, batteryLevel: lastState.batteryLevel)
        try? db?.insertState(state: newState)
        if audioFeedback {
            speak(newState.describeDelta(prev: lastState))
        }
        lastState = newState
    }
    
    private func handleUpdatedBattery(_ batteryLevel: UInt8) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: lastState.safetyHeadroom, batteryLevel: batteryLevel)
        try? db?.insertState(state: newState)
        if audioFeedback && batteryMonitor.passedBenchmark(Double(batteryLevel)){
            speak(newState.describeDelta(prev: lastState))
        }
        lastState = newState
    }
    
    private func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setActive(true)
        speechSynth?.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = speechVoice
        speechSynth?.speak(utterance)
        // AVSpeechSynthesizerDelegate will set AVAudioSession inactive on didFinish
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
            return 0 // TODO : assumes DESC sort
        }
        return benchmarks[index]
    }
}

class SpeedMonitor: BenchmarkMonitor {
    
    init() {
        let benchmarks = [10.0, 12.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0, 27.0, 28.0]
        let hysteresis = 1.0
        super.init(benchmarks: benchmarks, hysteresis: hysteresis)
    }
}

class BatteryMonitor: BenchmarkMonitor {
    
    init() {
        // 1% increments from [0-10]%, then 10% increments
        let benchmarks = Array(stride(from: 0.0, to: 10.0, by: 1.0)) + Array(stride(from: 10.0, to: 100.0, by: 10.0))
        let hysteresis = 1.0
        super.init(benchmarks: benchmarks, hysteresis: hysteresis)
    }
}

protocol ConnectionListener {
    func onConnected(oneWheel: OneWheel)
    func onDisconnected(oneWheel: OneWheel)
}
