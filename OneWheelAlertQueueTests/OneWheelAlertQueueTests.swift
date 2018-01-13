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
        
        init(priority: Priority, message: String) {
            self.priority = priority
            self.message = message
        }
        
        func trigger(completion: @escaping () -> Void) {
            NSLog("Triggered Test Alert priority \(priority) message \(message)")
            completion()
        }
    }
    
    func testAlertQueue() {
        let queue = AlertQueue()
        queue.queueAlert(TestAlert(priority: .LOW, message: "Low Alert 1"))
        queue.queueAlert(TestAlert(priority: .LOW, message: "Low Alert 2"))
        queue.queueAlert(TestAlert(priority: .LOW, message: "Low Alert 3"))
        queue.queueAlert(TestAlert(priority: .HIGH, message: "High Alert 1"))
        queue.queueAlert(TestAlert(priority: .LOW, message: "Low Alert 4"))
        
        sleep(4)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
