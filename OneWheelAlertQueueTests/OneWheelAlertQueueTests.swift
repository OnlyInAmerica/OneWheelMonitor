//
//  OneWheelAlertQueueTests.swift
//  OneWheelAlertQueueTests
//
//  Created by David Brodsky on 1/13/18.
//  Copyright © 2018 David Brodsky. All rights reserved.
//

import XCTest
@testable import OneWheel

class OneWheelAlertQueueTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    class TestAlert : Alert {
        var priority: Priority
        var message: String
        var key: String?
        var triggerCallback: (() -> Void)
        
        init(priority: Priority, message: String, key: String, callback: @escaping(() -> Void)) {
            self.priority = priority
            self.message = message
            self.key = key
            self.triggerCallback = callback
        }
        
        init(priority: Priority, message: String, callback: @escaping(() -> Void)) {
            self.priority = priority
            self.message = message
            self.triggerCallback = callback
        }
        
        func trigger(completion: @escaping () -> Void) {
            NSLog("Triggered Test Alert priority \(priority) message \(message)")
            triggerCallback()
            completion()
        }
    }
    
    func testAlertQueuePriority() {
        let expectedCallbackOrder = ["H1", "L1", "L2", "L3", "L4"]
        var callbackOrder = [String]()
        let queue = AlertQueue()
        queue.queueAlert(TestAlert(priority: .LOW, message: "Low Alert 1") {
            callbackOrder.append("L1")
        })
        queue.queueAlert(TestAlert(priority: .LOW, message: "Low Alert 2") {
            callbackOrder.append("L2")
        })
        queue.queueAlert(TestAlert(priority: .LOW, message: "Low Alert 3") {
            callbackOrder.append("L3")
        })
        queue.queueAlert(TestAlert(priority: .HIGH, message: "High Alert 1") {
            callbackOrder.append("H1")
        })
        queue.queueAlert(TestAlert(priority: .LOW, message: "Low Alert 4") {
            callbackOrder.append("L4")
        })
        
        sleep(1)
        assert(expectedCallbackOrder == callbackOrder)
    }
    
    func testAlertQueueTag() {
        let expectedCallbackOrder = ["K1-3", "K2-1", "K3-1"]
        var callbackOrder = [String]()
        let queue = AlertQueue()
        queue.queueAlert(TestAlert(priority: .LOW, message: "Key Alert 1", key: "1") {
            callbackOrder.append("K1-1")
        })
        queue.queueAlert(TestAlert(priority: .LOW, message: "Key Alert 2", key: "1") {
            callbackOrder.append("K1-2")
        })
        queue.queueAlert(TestAlert(priority: .LOW, message: "Key Alert 3", key: "1") {
            callbackOrder.append("K1-3")
        })
        queue.queueAlert(TestAlert(priority: .LOW, message: "Key Alert 2", key: "2") {
            callbackOrder.append("K2-1")
        })
        queue.queueAlert(TestAlert(priority: .LOW, message: "Key Alert 3", key: "3") {
            callbackOrder.append("K3-1")
        })
        sleep(1)
        assert(expectedCallbackOrder == callbackOrder)
    }

    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
