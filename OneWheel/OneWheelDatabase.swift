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
    private let dbQueue : DatabaseQueue
    
    init(_ path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        
        try migrator.migrate(dbQueue)
    }
    
    func insertState(state : OneWheelState) throws {
        try dbQueue.inDatabase { (db) in
            try state.insert(db)
        }
    }
    
    func getStateRecordsController() throws -> FetchedRecordsController<OneWheelState> {
        let controller = try FetchedRecordsController(
            dbQueue,
            request: OneWheelState.order(Column("time")))
        return controller
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
        self.safetyHeadroom = 0
        self.batteryLevel = 0
    
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
        batteryLevel: UInt8) {
        
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
            description += "Headroom to \(self.safetyHeadroom). "
        }
        if prev.batteryLevel != self.batteryLevel {
            description += "Battery \(self.batteryLevel). "
        }
        return description
    }
    
    func mph() -> Double {
        return 60.0 * (35.0 * Double(rpm)) / 63360.0;
    }
    
}
