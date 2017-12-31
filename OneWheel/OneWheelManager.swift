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
    private let speedMonitor = SpeedMonitor()
    
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

    func start() {
        cm = CBCentralManager.init(delegate: self, queue: nil, options: nil)
        // delegate awaits poweredOn state
    }
    
    func discoveredDevices() -> [OneWheel] {
        return []
    }
    
    func stop() {
        cm?.stopScan()
        if let device = connectedDevice {
            cm?.cancelPeripheralConnection(device)
        }
    }
    
    private func findDevice() {
        let cm = self.cm!
        if let primaryDeviceUuid = data.getPrimaryeviceUUID() {
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
            peripheral.discoverCharacteristics([characteristicRpmUuid, characteristicErrorUuid, characteristicSafetyHeadroomUuid], for: service)
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
            }
        }
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
                NSLog("Peripheral error characteristic changed with status \(status)")
                handleUpdatedStatus(status)
            } else {
                NSLog("Peripheral error charactersitic changed with no value")
            }

        case characteristicSafetyHeadroomUuid:
            if let value = characteristic.value {
                let intValue: UInt8 = value.withUnsafeBytes { $0.pointee }
                NSLog("Peripheral headroom characteristic changed with value \(intValue)")
                handleUpdatedSafetyHeadroom(intValue)
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
        default:
            NSLog("Peripheral unknown charactersitic (\(characteristic.uuid)) changed")
        }
    }
    
    private func handleConnectedDevice(_ device: CBPeripheral) {
        connectingDevice = nil
        connectedDevice = device
        device.delegate = self
        
        device.discoverServices([serviceUuid])
        // Delegate awaits service discovery
    }
    
    private func handleUpdatedStatus(_ s: OneWheelStatus) {
        let newState = OneWheelState(time: Date.init(), riderPresent: s.riderDetected, footPad1: s.riderDetectPad1, footPad2: s.riderDetectPad2, icsuFault: s.icsuFault, icsvFault: s.icsvFault, charging: s.charging, bmsCtrlComms: s.bmsCtrlComms, brokenCapacitor: s.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: lastState.safetyHeadroom)
        try? db?.insertState(state: newState)
        if audioFeedback {
            speak(newState.describeDelta(prev: lastState))
        }
        lastState = newState
    }
    
    private func handleUpdatedRpm(_ rpm: Int16) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: rpm, safetyHeadroom: lastState.safetyHeadroom)
        // Lets not create new events for every speed update. Eventually let's create another table or in-memory structure for speed
        //try? db?.insertState(state: newState)
        let mph = newState.mph()
        if audioFeedback && speedMonitor.passedBenchmark(mph){
            speak(newState.describeDelta(prev: lastState))
        }
        lastState = newState
    }
    
    private func handleUpdatedSafetyHeadroom(_ sh: UInt8) {
        let newState = OneWheelState(time: Date.init(), riderPresent: lastState.riderPresent, footPad1: lastState.footPad1, footPad2: lastState.footPad2, icsuFault: lastState.icsuFault, icsvFault: lastState.icsvFault, charging: lastState.charging, bmsCtrlComms: lastState.bmsCtrlComms, brokenCapacitor: lastState.brokenCapacitor, rpm: lastState.rpm, safetyHeadroom: sh)
        try? db?.insertState(state: newState)
        if audioFeedback {
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
    
}

class OneWheelLocalData {
    private let keyUuid = "ow_uuid"
    private let data = UserDefaults.standard
    
    func setPrimaryDeviceUUID(_ uuid: UUID) {
        data.setValue(uuid.uuidString, forKeyPath: keyUuid)
    }
    
    func getPrimaryeviceUUID() -> UUID? {
        if let stringUuid = data.string(forKey: keyUuid) {
            return UUID.init(uuidString: stringUuid)
        } else {
            return nil
        }
    }
}

class SpeedMonitor {
    // Trigger when passing through any of these benchmark speeds (MPH)
    let speedBenchmarksMph = [10.0, 12.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0, 27.0, 28.0]
    let hysteresisMph = 1.0
    
    // A speed index of 0 indicates we passed no benchmarks, 1 indicates we passed the 0-indexed benchmark etc.
    var lastSpeedIdx = 0
    
    func passedBenchmark(_ newSpeedMph: Double) -> Bool {
        
        let newSpeedIdx = (speedBenchmarksMph.index { (benchmarkMph) -> Bool in
            newSpeedMph >= benchmarkMph
        } ?? -1) + 1
        
        // Apply Hysteresis when downgrading speed benchmark
        if newSpeedIdx - lastSpeedIdx == -1 && speedBenchmarksMph[lastSpeedIdx] - newSpeedMph < hysteresisMph {
            return false
        }

        let isNew = newSpeedIdx != lastSpeedIdx
        lastSpeedIdx = newSpeedIdx
        return isNew
    }
}
