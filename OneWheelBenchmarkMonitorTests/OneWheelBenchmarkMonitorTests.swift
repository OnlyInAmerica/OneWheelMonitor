//
//  OneWheelBenchmarkMonitorTests.swift
//  OneWheelBenchmarkMonitorTests
//
//  Created by David Brodsky on 1/13/18.
//  Copyright © 2018 David Brodsky. All rights reserved.
//

import XCTest
@testable import OneWheel

class OneWheelBenchmarkMonitorTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testSpeedMonitor() {
        let benchmarks = [3.0, 2.0, 1.0]
        let hysteresis = 0.5
        let m = BenchmarkMonitor(benchmarks: benchmarks, hysteresis: hysteresis)
        
        assert(m.passedBenchmark(0.0) == false)
        assert(m.lastBenchmarkIdx == benchmarks.count)
        assert(m.lastLastBenchmarkIdx == benchmarks.count)
        
        assert(m.passedBenchmark(0.9) == false)
        assert(m.lastBenchmarkIdx == benchmarks.count)
        assert(m.lastLastBenchmarkIdx == benchmarks.count)
        
        assert(m.passedBenchmark(1.0) == true)
        assert(m.lastBenchmarkIdx == 2)
        assert(m.lastLastBenchmarkIdx == benchmarks.count)
        
        assert(m.passedBenchmark(0.9) == false) // .1 past 1.0 benchmark less than hysteresis
        assert(m.lastBenchmarkIdx == 2)
        assert(m.lastLastBenchmarkIdx == benchmarks.count)
        
        assert(m.passedBenchmark(0.4) == true) // .6 past 1.0 benchmark greater than hysteresis
        assert(m.lastBenchmarkIdx == benchmarks.count)
        assert(m.lastLastBenchmarkIdx == 2)
        
        assert(m.passedBenchmark(1.1) == false) // 1.1 past 1.0 benchmark less than hysteresis
        assert(m.lastBenchmarkIdx == benchmarks.count)
        assert(m.lastLastBenchmarkIdx == 2)
        
        assert(m.passedBenchmark(1.5) == true)  // .5 past 1.0 benchmark greater than hysteresis
        assert(m.lastBenchmarkIdx == 2)
        assert(m.lastLastBenchmarkIdx == benchmarks.count)
    }
}
