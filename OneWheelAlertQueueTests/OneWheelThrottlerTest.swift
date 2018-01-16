//
//  OneWheelThrottlerTest.swift
//  OneWheelAlertQueueTests
//
//  Created by David Brodsky on 1/15/18.
//  Copyright © 2018 David Brodsky. All rights reserved.
//

import XCTest
@testable import OneWheel

class OneWheelThrottlerTest: XCTestCase {
    
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
    
    func testThrottlerCancel() {
        let throttler = CancelableAlertThrottler()
        throttler.thresholdS = 0.100
        let alertQueue = AlertQueue()
        throttler.scheduleAlert(key: "a", alertQueue: alertQueue, alert: TestAlert(priority: .HIGH, message: "a") {
            // Should be cancelled before being triggered by next call to cancelAlert
            assertionFailure()
        })
        throttler.cancelAlert(key: "a", alertQueue: alertQueue, ifNoOutstandingAlert: TestAlert(priority: .HIGH, message: "a") {
            // Previous alert should be outstanding
            assertionFailure()
        })
        sleep(1)
    }
    
    func testThrottlerNoCancel() {
        let throttler = CancelableAlertThrottler()
        throttler.thresholdS = 0.100
        let alertQueue = AlertQueue()
        var firstAlertTriggered = false
        var secondaryAlertTriggered = false
        throttler.scheduleAlert(key: "a", alertQueue: alertQueue, alert: TestAlert(priority: .HIGH, message: "a") {
            // Should be cancelled before being triggered by next call to cancelAlert
            firstAlertTriggered = true
        })
        sleep(1)//UInt32(throttler.thresholdS * 2.0))
        assert(firstAlertTriggered)
        throttler.cancelAlert(key: "a", alertQueue: alertQueue, ifNoOutstandingAlert: TestAlert(priority: .HIGH, message: "b") {
            // Previous alert should be outstanding
            secondaryAlertTriggered = true
        })
        sleep(1)
        assert(secondaryAlertTriggered)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
