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
    var seriesPaths = [String: CGMutablePath]()
    var bgColor: CGColor = UIColor(white: 0.0, alpha: 1.0).cgColor
    var bgTransparentColor: CGColor {
        get {
            return bgColor.copy(alpha: 0.0)!
        }
    }
    
    var portraitMode  = false
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()!

        if let dataSource = self.dataSource {
            
            context.setFillColor(bgColor)
            context.fill(rect)
            
            let seriesAxisRect = rect.insetBy(dx: 0.0, dy: 11.0).applying(CGAffineTransform(translationX: 0.0, y: -11.0))
            let timeLabelsRect = portraitMode ? rect.insetBy(dx: 20.0, dy: 0.0) : rect.insetBy(dx: 40.0, dy: 0.0).applying(CGAffineTransform(translationX: 7.0, y: 0.0)) // last affineT is a janky compensation for the MPH / Battery label width differences :/
            let seriesRect = portraitMode ? seriesAxisRect.insetBy(dx: 20.0, dy: 0.0).applying(CGAffineTransform(translationX: -20.0, y: 0.0)) : seriesAxisRect.insetBy(dx: 40.0, dy: 0.0).applying(CGAffineTransform(translationX: 7.0, y: 0.0))

            context.addRect(seriesRect)
            context.clip()
            drawSeries(dataSource: dataSource, rect: seriesRect, context: context)
            context.resetClip()

            if portraitMode {
                context.saveGState()
                
                let gradientColors = [bgColor, bgTransparentColor]
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let colorLocations: [CGFloat] = [0.1, 1.0]
                let gradient = CGGradient(colorsSpace: colorSpace,
                                          colors: gradientColors as CFArray,
                                          locations: colorLocations)!
                let startPoint = CGPoint(x: 0, y: rect.midY)
                let endPoint = CGPoint(x: 50, y: rect.midY)
                let gradientWidth = 100
//                let leftGradientPath = UIBezierPath(rect: CGRect(x: 0, y: 0, width: gradientWidth, height: Int(rect.height)))
//                leftGradientPath.addClip()
                
                let gradientRect = CGRect(x: 0, y: 0, width: gradientWidth, height: Int(rect.height))
                context.addRect(gradientRect)
                context.clip()
                context.drawLinearGradient(gradient,
                                           start: startPoint,
                                           end: endPoint,
                                           options: [])
                context.restoreGState()
            }
            
            // clear Series last-values and draw axis labels
            for curSeries in series.values {
                curSeries.lastX = 0.0
                curSeries.lastY = 0.0

                let numLabels = (curSeries is MotorTempSeries) ? 4 : 5
                curSeries.drawAxisLabels(rect: seriesAxisRect, numLabels: numLabels, bgColor: bgColor)
            }
            drawTimeLabels(rect: timeLabelsRect, context: context, numLabels: portraitMode ? 2 : 3)
            
            seriesPaths.removeAll()
        }
        NSLog("Drawing graph finished")
    }
    
    func drawSeries(dataSource: GraphDataSource, rect: CGRect, context: CGContext) {
        // Start drawing at Lower left
        context.move(to: CGPoint(x: rect.origin.x, y: rect.height))
        let dataCount = dataSource.getCount()
        let widthPtsPerData: CGFloat = 2
        let strideCount: Int = CGFloat(dataCount) > (rect.width / widthPtsPerData) ? dataCount / Int(rect.width / widthPtsPerData) : 1
        let deltaX = rect.width / (CGFloat(dataCount / strideCount))
        var x: CGFloat = rect.origin.x + deltaX
        NSLog("Drawing graph with deltaX \(deltaX), stride \(strideCount)")
        for valIdx in stride(from: 0, to: dataCount, by: strideCount)  { // 0..<dataCount {
            
            let state = dataSource.getStateForIndex(index: valIdx)
            
            for curSeries in series.values {
                
                let normVal = CGFloat(curSeries.getNormalizedVal(state: state))
                let y = ((1.0 - normVal) * rect.height) + rect.origin.y
                
                if curSeries.type == SeriesType.Value {
                    var path = seriesPaths[curSeries.name]
                    if path == nil {
                        path = CGMutablePath()
                        path?.move(to: CGPoint(x: x, y: y))
                    }
                    path!.addLine(to: CGPoint(x: x, y: y))
                    //                        NSLog("Draw line from \(curSeries.lastX), \(curSeries.lastY) to \(x), \(y)")
                    
                    seriesPaths[curSeries.name] = path
                    
                } else if curSeries.type == SeriesType.Boolean {
                    
                    if normVal == 1.0 {
                        let errorRect = CGRect(x: curSeries.lastX, y: y, width: (x-curSeries.lastX), height: rect.height)
                        context.setFillColor(curSeries.color)
                        context.fill(errorRect)
                    }
                }
                
                curSeries.lastX = x
                curSeries.lastY = y
                
            } // end for series
            x += deltaX
        } // end for x-val
        
        // draw value series paths
        for (seriesName, seriesPath) in seriesPaths {
            let curSeries = series[seriesName]!
            let seriesColor = curSeries.color
            context.addPath(seriesPath)
            context.setLineWidth(3.0)
            context.setStrokeColor(seriesColor)
            context.strokePath()
            
            if curSeries.gradientUnderPath {
                let clippingPath = UIBezierPath(cgPath: seriesPath.copy() as! CGMutablePath)
                clippingPath.addLine(to: CGPoint(x: curSeries.lastX, y: rect.height))
                clippingPath.addLine(to: CGPoint(x: rect.origin.x, y: rect.height))
                clippingPath.close()
                clippingPath.addClip()
                
                // create and add the gradient
                let colors = [seriesColor.copy(alpha: 0.9), seriesColor.copy(alpha: 0.0)]
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let colorLocations:[CGFloat] = [0.0, 1.0]
                let gradient = CGGradient(colorsSpace: colorSpace,
                                          colors: colors as CFArray,
                                          locations: colorLocations)!
                
                let startPoint = rect.origin
                let endPoint = CGPoint(x: rect.origin.x, y: rect.maxY)
                
                context.drawLinearGradient(gradient,
                                           start: startPoint,
                                           end: endPoint,
                                           options: [])
            }
        }
    }
    
    func drawTimeLabels(rect: CGRect, context: CGContext, numLabels: Int) {
        
        let dataCount = dataSource!.getCount()
        
        if dataCount == 0 {
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes = [NSAttributedStringKey.paragraphStyle  : paragraphStyle,
                          NSAttributedStringKey.font            : UIFont.systemFont(ofSize: 14.0),
                          NSAttributedStringKey.foregroundColor : UIColor(cgColor: UIColor.white.cgColor)
        ]
        
        let labelSideMargin: CGFloat = 5
        for axisLabelIdx in 0..<numLabels {
            if axisLabelIdx == 0 {
                paragraphStyle.alignment = .left
            } else if axisLabelIdx == numLabels - 1 {
                paragraphStyle.alignment = .right
            } else {
                paragraphStyle.alignment = .center
            }
            
            let axisLabelFrac: CGFloat = CGFloat(axisLabelIdx) / CGFloat(numLabels-1)
            let state = dataSource!.getStateForIndex(index: Int(CGFloat(dataCount-1) * axisLabelFrac))

            let x: CGFloat = (rect.width * axisLabelFrac) + rect.origin.x
            let axisLabel = formatter.string(from: state.time)
            let attrString = NSAttributedString(string: axisLabel,
                                                attributes: attributes)
            let labelSize = attrString.size()
            var rectX = x - (labelSize.width / 2)
            if paragraphStyle.alignment == .left {
                rectX = labelSideMargin + x
            } else if paragraphStyle.alignment == .right {
                rectX = x - labelSideMargin - labelSize.width
            }
            
            let rectY = rect.height - labelSideMargin - labelSize.height
            
            let rt =  CGRect(x: rectX, y: rectY, width: labelSize.width, height: labelSize.height)
            
            context.setFillColor(bgColor)
            context.fill(rt)
            
//            NSLog("Drawing time axis label \(axisLabel)")

            attrString.draw(in: rt)
        }
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
        
        enum AxisLabelType {
            case None
            case Left
            case Right
        }
        
        let name: String
        let color: CGColor
        let evaluator: SeriesEvaluator
        let type: SeriesType
        let labelType: AxisLabelType
        let gradientUnderPath: Bool

        var min = 0.0
        var max = 0.0
        
        var lastX: CGFloat = 0.0
        var lastY: CGFloat = 0.0
        
        init(name: String, color: CGColor, type: SeriesType, labelType: AxisLabelType, gradientUnderPath: Bool, evaluator: SeriesEvaluator) {
            self.name = name
            self.color = color
            self.type = type
            self.labelType = labelType
            self.gradientUnderPath = gradientUnderPath
            self.evaluator = evaluator
        }
        
        // Return the normalized value at the given index.
        // returns a value between [0, 1]
        func getNormalizedVal(state: OneWheelState) -> Double {
            let val = evaluator.getValForState(state: state)
            return (val / (max - min))
        }
        
        func drawAxisLabels(rect: CGRect, numLabels: Int, bgColor: CGColor) {
            if labelType == AxisLabelType.None {
                return
            }
            
            let context = UIGraphicsGetCurrentContext()!
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = (labelType == AxisLabelType.Left) ? .left : .right
            
            let attributes = [NSAttributedStringKey.paragraphStyle  : paragraphStyle,
                              NSAttributedStringKey.font            : UIFont.systemFont(ofSize: 14.0),
                              NSAttributedStringKey.foregroundColor : UIColor(cgColor: self.color)
                              ]
            
            let labelSideMargin: CGFloat = 5
            let x: CGFloat = (labelType == AxisLabelType.Left) ? CGFloat(labelSideMargin) : rect.width - labelSideMargin
            for axisLabelVal in stride(from: min, through: max, by: (max - min) / Double(numLabels)) {
                // TODO : Re-evaluate, but for now don't draw 0-val label
                if axisLabelVal == min {
                    continue
                }
                let y = CGFloat(1.0 - ((axisLabelVal - min) / (max - min))) * rect.height
                let axisLabel = printAxisVal(val: axisLabelVal)
                let attrString = NSAttributedString(string: axisLabel,
                                                    attributes: attributes)
                let labelSize = attrString.size()
                // Assumes RTL language : When positioning left-flowing text on the right side, need to move our start point left by the text width
                let rectX = (labelType == AxisLabelType.Right) ? x - labelSize.width : x
                
                let rt =  CGRect(x: rectX, y: y, width: labelSize.width, height: labelSize.height)
                
                context.setFillColor(bgColor)
                context.fill(rt)
                
                attrString.draw(in: rt)
            }
        }
        
        func printAxisVal(val: Double) -> String {
            return "\(val)"
        }
    }
    
    class ControllerTempSeries : Series, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, type: SeriesType.Value, labelType: AxisLabelType.None, gradientUnderPath: false, evaluator: self)
            max = 120 // TODO: Figure out reasonable max temperatures
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return Double(state.controllerTemp)
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))°F"
        }
    }
    
    class MotorTempSeries : Series, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, type: SeriesType.Value, labelType: AxisLabelType.Right, gradientUnderPath: false, evaluator: self)
            max = 120 // TODO: Figure out reasonable max temperatures
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return Double(state.motorTemp)
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))°F"
        }
    }
    
    class SpeedSeries : Series, SeriesEvaluator {

        init(name: String, color: CGColor) {
            super.init(name: name, color: color, type: SeriesType.Value, labelType: AxisLabelType.Left, gradientUnderPath: true, evaluator: self)
            max = 20.0 // Current world record is ~ 27 MPH
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return state.mph()
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))MPH"
        }
    }
    
    class BatterySeries : Series, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, type: SeriesType.Value, labelType: AxisLabelType.Right, gradientUnderPath: false, evaluator: self)
            max = 100.0
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return Double(state.batteryLevel)
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))%"
        }
    }
    
    class ErrorSeries : Series, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, type: SeriesType.Boolean, labelType: AxisLabelType.None, gradientUnderPath: false, evaluator: self)
            max = 1.0
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return (state.mph() > 1.0) && ((!state.footPad1 && !state.footPad2) || (!state.riderPresent)) ? 1.0 : 0.0
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
