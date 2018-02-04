//
//  OneWheelDatabase.swift
//  OneWheel
//
//  Created by David Brodsky on 12/30/17.
//  Copyright © 2017 David Brodsky. All rights reserved.
//

import Foundation
import GRDB

let tableState = "state"

class OneWheelDatabase {
    var updateListener: UpdateListener? = nil
    
    private let dbPool : DatabasePool
    private let dateFormatter = DateFormatter()
    
    init(_ path: String) throws {
        dbPool = try DatabasePool(path: path)
        try migrator.migrate(dbPool)
        
        //                          2018-01-13 07:11:57.448"
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
    }
    
    func insertState(state : OneWheelState) throws {
        try dbPool.write { (db) in
            try state.insert(db)
        }
        updateListener?.onChange()
    }
    
    func insertStates(states: [OneWheelState]) throws {
        try dbPool.writeInTransaction{ (db) -> Database.TransactionCompletion in
            for state in states {
                try state.insert(db)
            }
            return .commit
        }
        updateListener?.onChange()
    }
    
    func getStateRecordsController() throws -> FetchedRecordsController<OneWheelState> {
        let controller = try FetchedRecordsController(
            dbPool,
            request: OneWheelState.order(Column("time")))
        return controller
    }
    
    func getRecentStateRecordsController(completion: @escaping((FetchedRecordsController<OneWheelState>) -> ())) throws {
        let lastDate: Date = try dbPool.read { (db) in
            if let state = try? OneWheelState.order(sql: "time DESC").fetchOne(db) {
                return state?.time ?? Date()
            } else {
                return Date()
            }
        }
        let startDate = Calendar.current.date(
            byAdding: .minute,
            value: -1,
            to: lastDate)!
        let sinceDateStr = dateFormatter.string(from: startDate)
        NSLog("Fetching state since \(sinceDateStr)")
        let controller = try FetchedRecordsController(
            dbPool,
            request: OneWheelState.filter(sql: "time > ?", arguments: [sinceDateStr]))
        DispatchQueue.main.async {
            completion(controller)
        }
    }
    
    func clear() throws {
        let _ = try dbPool.write { (db) in
            try OneWheelState.deleteAll(db)
        }
        try dbPool.checkpoint()
    }
    
    func checkpoint() throws {
        try dbPool.checkpoint()
    }
}

var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    
    migrator.registerMigration("createState") { db in
        try db.create(table: tableState) { t in
            t.column("id", .integer).primaryKey()
            t.column("time", .datetime).notNull()
            t.column("riderPresent", .boolean).notNull()
            t.column("footPad1", .boolean).notNull()
            t.column("footPad2", .boolean).notNull()
            t.column("icsuFault", .boolean).notNull()
            t.column("icsvFault", .boolean).notNull()
            t.column("charging", .boolean).notNull()
            t.column("bmsCtrlComms", .boolean).notNull()
            t.column("brokenCapacitor", .boolean).notNull()
            t.column("rpm", .integer).notNull()
            t.column("safetyHeadroom", .integer).notNull()
            t.column("batteryLevel", .integer).notNull()
        }
    }
    
    migrator.registerMigration("addMotorControllerTempAndLastError") { db in
        try db.alter(table: tableState) { t in
            t.add(column: "motorTemp", .integer).notNull().defaults(to: 0)
            t.add(column: "controllerTemp", .integer).notNull().defaults(to: 0)
            t.add(column: "lastErrorCode", .integer).notNull().defaults(to: 0)
            t.add(column: "lastErrorCodeVal", .integer).notNull().defaults(to: 0)
        }
    }

    return migrator
}

class OneWheelState : Record, CustomStringConvertible {
    
    override class var databaseTableName : String {
        return tableState
    }
    
    let time: Date
    let riderPresent: Bool
    let footPad1: Bool
    let footPad2: Bool
    let icsuFault: Bool
    let icsvFault: Bool
    let charging: Bool
    let bmsCtrlComms: Bool
    let brokenCapacitor: Bool
    let rpm: Int16
    let safetyHeadroom: UInt8
    let batteryLevel : UInt8
    let motorTemp : UInt8
    let controllerTemp : UInt8
    let lastErrorCode : UInt8
    let lastErrorCodeVal : UInt8

    
    override init() {
        self.time = Date()
        self.riderPresent = false
        self.footPad1 = false
        self.footPad2 = false
        self.icsuFault = false
        self.icsvFault = false
        self.charging = false
        self.bmsCtrlComms = false
        self.brokenCapacitor = false
        self.rpm = 0
        self.safetyHeadroom = 100
        self.batteryLevel = 0
        self.motorTemp = 0
        self.controllerTemp = 0
        self.lastErrorCode = 0
        self.lastErrorCodeVal = 0
        
        super.init()
    }
    
    init(
        time: Date,
        riderPresent: Bool,
        footPad1: Bool,
        footPad2: Bool,
        icsuFault: Bool,
        icsvFault: Bool,
        charging: Bool,
        bmsCtrlComms: Bool,
        brokenCapacitor: Bool,
        rpm: Int16,
        safetyHeadroom: UInt8,
        batteryLevel: UInt8,
        motorTemp: UInt8,
        controllerTemp: UInt8,
        lastErrorCode: UInt8,
        lastErrorCodeVal: UInt8) {
        
        self.time = time
        self.riderPresent = riderPresent
        self.footPad1 = footPad1
        self.footPad2 = footPad2
        self.icsuFault = icsuFault
        self.icsvFault = icsvFault
        self.charging = charging
        self.bmsCtrlComms = bmsCtrlComms
        self.brokenCapacitor = brokenCapacitor
        self.rpm = rpm
        self.safetyHeadroom = safetyHeadroom
        self.batteryLevel = batteryLevel
        self.motorTemp = motorTemp
        self.controllerTemp = controllerTemp
        self.lastErrorCode = lastErrorCode
        self.lastErrorCodeVal = lastErrorCodeVal
        
        super.init()
    }
    
    required init(row: Row) {
        time = row["time"]
        riderPresent = row["riderPresent"]
        footPad1 = row["footPad1"]
        footPad2 = row["footPad2"]
        icsuFault = row["icsuFault"]
        icsvFault = row["icsvFault"]
        charging = row["charging"]
        bmsCtrlComms = row["bmsCtrlComms"]
        brokenCapacitor = row["brokenCapacitor"]
        rpm = row["rpm"]
        safetyHeadroom = row["safetyHeadroom"]
        batteryLevel = row["batteryLevel"]
        motorTemp = row["motorTemp"]
        controllerTemp = row["controllerTemp"]
        lastErrorCode = row["lastErrorCode"]
        lastErrorCodeVal = row["lastErrorCodeVal"]
        
        super.init()
    }
    
    override func encode(to container: inout PersistenceContainer) {
        container["time"] = time
        container["riderPresent"] = riderPresent
        container["footPad1"] = footPad1
        container["footPad2"] = footPad2
        container["icsuFault"] = icsuFault
        container["icsvFault"] = icsvFault
        container["charging"] = charging
        container["bmsCtrlComms"] = bmsCtrlComms
        container["brokenCapacitor"] = brokenCapacitor
        container["rpm"] = rpm
        container["safetyHeadroom"] = safetyHeadroom
        container["batteryLevel"] = batteryLevel
        container["motorTemp"] = motorTemp
        container["controllerTemp"] = controllerTemp
        container["lastErrorCode"] = lastErrorCode
        container["lastErrorCodeVal"] = lastErrorCodeVal
    }
    
    var description: String {
        // Delta from default values)
        return self.describeDelta(prev: OneWheelState())
    }
    
    func describeDelta(prev: OneWheelState) -> String {
        var description = ""
        if prev.riderPresent != self.riderPresent {
            description += "Rider \(self.riderPresent ? "On" : "Off"). "
        }
        if prev.footPad1 != self.footPad1 {
            description += "Toe \(self.footPad1 ? "On" : "Off"). "
        }
        if prev.footPad2 != self.footPad2 {
            description += "Heel \(self.footPad2 ? "On" : "Off"). "
        }
        if prev.icsuFault != self.icsuFault {
            description += "U Fault \(self.icsuFault ? "On" : "Off"). "
        }
        if prev.icsvFault != self.icsvFault {
            description += "V Fault \(self.icsvFault ? "On" : "Off"). "
        }
        if prev.charging != self.charging {
            description += "Charging \(self.charging ? "On" : "Off"). "
        }
        if prev.bmsCtrlComms != self.bmsCtrlComms {
            description += "Ctl Comms \(self.bmsCtrlComms ? "On" : "Off"). "
        }
        if prev.brokenCapacitor != self.brokenCapacitor {
            description += "Broken Capacitor \(self.brokenCapacitor ? "On" : "Off"). "
        }
        if prev.rpm != self.rpm {
            let mph = String(format: "%.1f", self.mph())
            description += "Speed \(mph). "
        }
        if prev.safetyHeadroom != self.safetyHeadroom {
            description += "Headroom \(self.safetyHeadroom). "
        }
        if prev.batteryLevel != self.batteryLevel {
            description += "Battery \(self.batteryLevel). "
        }
        if prev.motorTemp != self.motorTemp {
            description += "Motor Temp \(self.motorTemp). "
        }
        if prev.controllerTemp != self.controllerTemp {
            description += "Controller Temp \(self.controllerTemp). "
        }
        if prev.lastErrorCode != self.lastErrorCode {
            description += "Last Error \(self.lastErrorDescription()). "
        }
        return description
    }
    
    func mph() -> Double {
        return 60.0 * (35.0 * Double(rpm)) / 63360.0;
    }
    
    func lastErrorDescription() -> String {
        return "\(errorCodeMap[self.lastErrorCode] ?? "Unknown") \(self.lastErrorCodeVal)"
    }
    
    func feetOffDuringMotion() -> Bool {
        // If we're moving and rider is present but neither footpad sensor is triggered
        // In this case we seem to have about 500 ms before shutoff (riderPresent going false)
        return (rpm > 0) && (!footPad1 && !footPad2 && riderPresent)
    }
}

protocol UpdateListener {
    func onChange()
}

let errorCodeMap: [UInt8: String] = [
    0: "None",
    1: "BmsLowBattery",
    2: "VoltageLow",
    3: "VoltageHigh",
    4: "FallDetected",
    5: "PickupDetected",
    6: "OverCurrentDetected",
    7: "OverTemperature",
    8: "BadGyro",
    9: "BadAccelerometer",
    10: "BadCurrentSensor",
    11: "BadHallSensors",
    12: "BadMotor",
    13: "Overcurrent13",
    14: "Overcurrent14",
    15: "BadRiderDetectZone"
]
