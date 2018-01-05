//
//  OneWheelGraphView.swift
//  OneWheel
//
//  Created by David Brodsky on 1/5/18.
//  Copyright © 2018 David Brodsky. All rights reserved.
//

import UIKit

class OneWheelGraphView: UIView {
    
    var dataSource: GraphDataSource?
    var series = [String: Series]()

    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()!

        if let dataSource = self.dataSource {
            
            // Start drawing at Lower left
            context.move(to: CGPoint(x: 0.0, y: rect.height))
            let dataCount = dataSource.getCount()
            let strideCount: Int = CGFloat(dataCount) > rect.width ? dataCount / Int(rect.width) : 1
            let deltaX = rect.width / (CGFloat(dataCount / strideCount))
            var x: CGFloat = deltaX
            NSLog("Drawing graph with deltaX \(deltaX), stride \(strideCount)")
            for valIdx in stride(from: 0, to: dataCount, by: strideCount)  { // 0..<dataCount {

                let state = dataSource.getStateForIndex(index: valIdx)

                for curSeries in series.values {
                    
                    let normVal = CGFloat(curSeries.getNormalizedVal(state: state))
                    let y = (1.0 - normVal) * rect.height
                    
                    context.setStrokeColor(curSeries.color)

                    if curSeries.type == SeriesType.Value {
                        context.move(to: CGPoint(x: curSeries.lastX, y: curSeries.lastY))
                        context.setLineWidth(2.0)
                        context.addLine(to: CGPoint(x: x, y: y))
//                        NSLog("Draw line from \(curSeries.lastX), \(curSeries.lastY) to \(x), \(y)")
                        
                        context.strokePath()
                        
                    } else if curSeries.type == SeriesType.Boolean {
                        
                        if normVal == 1.0 {
                            context.move(to: CGPoint(x: curSeries.lastX, y: y))
                            context.setLineWidth(8.0)
                            context.addLine(to: CGPoint(x: x, y: y))
                            context.strokePath()
//                            NSLog("Draw error line from \(curSeries.lastX), \(curSeries.lastY) to \(x), \(y)")
                        }
                    }
                    
                    curSeries.lastX = x
                    curSeries.lastY = y
                } // end for series
                x += deltaX
            } // end for x-val
            
            // clear Series last-values
            for curSeries in series.values {
                curSeries.lastX = 0.0
                curSeries.lastY = 0.0
            }
        }
        NSLog("Drawing graph finished")
    }
    
    func addSeries(newSeries: Series) {
        if self.dataSource != nil {
            series[newSeries.name] = newSeries
        } else {
            NSLog("Cannot add series before a datasource is set")
        }
    }
    
    enum SeriesType {
        case Value
        case Boolean
    }
    
    class Series {
        let name: String
        let color: CGColor
        let evaluator: SeriesEvaluator
        let type: SeriesType

        var min = 0.0
        var max = 0.0
        
        var lastX: CGFloat = 0.0
        var lastY: CGFloat = 0.0
        
        init(name: String, color: CGColor, type: SeriesType, evaluator: SeriesEvaluator) {
            self.name = name
            self.color = color
            self.evaluator = evaluator
            self.type = type
        }
        
        // Return the normalized value at the given index.
        // returns a value between [0, 1]
        func getNormalizedVal(state: OneWheelState) -> Double {
            let val = evaluator.getValForState(state: state)
            return (val / (max - min))
        }
    }
    
    class SpeedSeries : Series, SeriesEvaluator {

        init(name: String, color: CGColor) {
            super.init(name: name, color: color, type: SeriesType.Value, evaluator: self)
            max = 28.0 // Current world record is ~ 27 MPH
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return state.mph()
        }
    }
    
    class BatterySeries : Series, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, type: SeriesType.Value, evaluator: self)
            max = 100.0
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return Double(state.batteryLevel)
        }
    }
    
    class ErrorSeries : Series, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, type: SeriesType.Boolean, evaluator: self)
            max = 1.0
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return (!state.footPad1 || !state.footPad2 || !state.riderPresent) ? 1.0 : 0.0
        }
    }
}

protocol GraphDataSource {
    func getCount() -> Int
    func getStateForIndex(index: Int) -> OneWheelState
}

protocol SeriesEvaluator {
    func getValForState(state: OneWheelState) -> Double
}
