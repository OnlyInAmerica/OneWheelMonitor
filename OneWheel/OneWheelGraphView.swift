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
    var bgColor: CGColor = UIColor(white: 0.0, alpha: 1.0).cgColor
    var bgTransparentColor: CGColor {
        get {
            return bgColor.copy(alpha: 0.0)!
        }
    }
    
    var portraitMode  = false
    
    // Parallel cache arrays of state and x placement
    var stateCacheDataCount: Int = 0
    var stateCache = [OneWheelState]()
    var stateXPosCache = [CGFloat]()
    
    // Display rects
    var seriesRect: CGRect? = nil
    var seriesAxisRect: CGRect? = nil
    var timeLabelsRect: CGRect? = nil
    
    public override func layoutSublayers(of layer: CALayer) {
        NSLog("CALayer - layoutSublayers with bounds \(self.bounds) frame \(self.frame)")
        
        let seriesAxisRect = self.bounds.insetBy(dx: 0.0, dy: 11.0).applying(CGAffineTransform(translationX: 0.0, y: -11.0))
        let timeLabelsRect = portraitMode ? self.bounds.insetBy(dx: 20.0, dy: 0.0) : self.bounds.insetBy(dx: 40.0, dy: 0.0).applying(CGAffineTransform(translationX: 7.0, y: 0.0)) // last affineT is a janky compensation for the MPH / Battery label width differences :/
        let seriesRect = portraitMode ? seriesAxisRect.insetBy(dx: 20.0, dy: 0.0).applying(CGAffineTransform(translationX: -20.0, y: 0.0)) : seriesAxisRect.insetBy(dx: 40.0, dy: 0.0).applying(CGAffineTransform(translationX: 7.0, y: 0.0))

        for (_, series) in self.series {
            if !series.didSetupLayers {
                series.requestLayerSetup(root: self.layer, frame: seriesRect, graphView: self)
            } else {
                series.resizeLayers(frame: seriesRect, graphView: self)
            }
        }
        self.seriesRect = seriesRect
        self.seriesAxisRect = seriesAxisRect
        self.timeLabelsRect = timeLabelsRect
        super.layoutSublayers(of: layer)
    }
    
    override func draw(_ rect: CGRect) {
        NSLog("CALayer - draw with bounds \(self.bounds) frame \(self.frame)")

        if let dataSource = self.dataSource, let seriesRect = self.seriesRect, let seriesAxisRect = self.seriesAxisRect, let timeLabelsRect = self.timeLabelsRect, let cgContext = UIGraphicsGetCurrentContext() {
            let dataCount = dataSource.getCount()
            if stateCacheDataCount != dataCount {
                NSLog("CALayer - Caching data. \(dataCount) items, \(stateCache.count) in cache")
                // Assume that we're working with timeseries data so only need to update cache if size changes
                self.cacheState(dataSource: dataSource, rect: seriesRect)

                for (_, series) in self.series {
                    series.bindData(rect: seriesRect, graphView: self)
                }
            }
            for (_, series) in self.series {
                series.drawAxisLabels(rect: seriesAxisRect, numLabels: 5, bgColor: bgColor, context: cgContext)
            }
            
            drawTimeLabels(rect: timeLabelsRect, context: cgContext, numLabels: portraitMode ? 2: 3)
            // Forget background color for now
//            cgContext.setFillColor(bgColor)
//            cgContext.fill(rect)
            super.draw(rect)
        }
    }
    
    private func cacheState(dataSource: GraphDataSource, rect: CGRect) {
        let dataCount = dataSource.getCount()
        let widthPtsPerData: CGFloat = 2
        let maxPoints = Int(rect.width / widthPtsPerData)
        let numPoints = min(dataCount, maxPoints)
        stateCache = [OneWheelState](repeating: OneWheelState(), count: numPoints)
        stateXPosCache = [CGFloat](repeating: 0.0, count: numPoints)
        let deltaDataIdx = dataCount / numPoints
        let deltaX = rect.width / (CGFloat(numPoints))
        var x: CGFloat = rect.origin.x + deltaX
        NSLog("CALayer - Caching graph data")
        var cacheIdx = 0
        var dataIdx = 0
        for valIdx in 0..<numPoints  {
            
            let state = dataSource.getStateForIndex(index: dataIdx)
            
            stateCache[cacheIdx] = state
            stateXPosCache[cacheIdx] = x
            
            x += deltaX
            dataIdx += deltaDataIdx
            cacheIdx += 1
        }
        stateCacheDataCount = dataCount
        NSLog("CALayer - Cached \(stateCache.count) graph data ")
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
            //addSeriesSubLayer(series: newSeries) BAD_ACCESS
        } else {
            NSLog("Cannot add series before a datasource is set")
        }
    }
 
    class BooleanSeries : Series, CALayerDelegate {
        
        private var path: CGPath? = nil
        private var layer: CAShapeLayer? = nil
        
        override func setupLayers(root: CALayer, frame: CGRect, graphView: OneWheelGraphView) {
            let scale = UIScreen.main.scale
            
            let l = CAShapeLayer()
            l.fillColor = color
            l.contentsScale = scale
            l.frame = frame
            root.addSublayer(l)
            self.layer = l
        }
        
        override func resizeLayers(frame: CGRect, graphView: OneWheelGraphView) {
            let position = CGPoint(x: frame.midX, y: frame.midY)
            
            layer?.bounds = frame
            layer?.position = position
            
            if let path = self.path, !path.boundingBox.isEmpty, let layer = self.layer {
                
                let newPath = createPath(rect: frame, graphView: graphView)
                animateShapeLayerPath(shapeLayer: layer, newPath: newPath)
            }
        }
        
        override func bindData(rect: CGRect, graphView: OneWheelGraphView) {
            layer?.setNeedsDisplay()
            
            if let layer = self.layer {
                let path = createPath(rect: rect, graphView: graphView)
                layer.path = path
            }
        }
        
        private func createPath(rect: CGRect, graphView: OneWheelGraphView) -> CGPath {
            let path = CGMutablePath()
            forEachData(rect: rect, graphView: graphView) { (x, state) -> CGFloat in
                let normVal = CGFloat(getNormalizedVal(state: state))
                if normVal == 1.0 {
                    let errorRect = CGRect(x: lastX, y: rect.origin.y, width: (x-lastX), height: rect.height)
                    path.addRect(errorRect)
                }
                return rect.origin.y
            }
            return path
        }
    }
    
    class ValueSeries : Series {
        
        private var shapeLayer: CAShapeLayer? = nil
        private var bgLayer: CAGradientLayer? = nil
        private var bgMaskLayer: CAShapeLayer? = nil
        
        override func setupLayers(root: CALayer, frame: CGRect, graphView: OneWheelGraphView) {
            let scale = UIScreen.main.scale
            
            if gradientUnderPath {
                let bgM = CAShapeLayer()
                bgM.needsDisplayOnBoundsChange = true
                bgM.contentsScale = scale
                bgM.frame = frame
                bgM.fillColor = color
                self.bgMaskLayer = bgM
                
                let bg = CAGradientLayer()
                bg.needsDisplayOnBoundsChange = true
                bg.contentsScale = scale
                bg.frame = frame
                bg.colors = [color.copy(alpha: 0.9)!, color.copy(alpha: 0.0)!]
                bg.startPoint = CGPoint(x: 0.0, y: 0.0)
                bg.endPoint = CGPoint(x: 0.0, y: 1.0)
                bg.locations = [0.0, 1.0]
                bg.mask = bgM
                
                root.addSublayer(bg)
                self.bgLayer = bg
            }
            
            let sl = CAShapeLayer()
            sl.needsDisplayOnBoundsChange = true
            sl.contentsScale = scale
            sl.frame = frame
            sl.fillColor = UIColor.clear.cgColor
            sl.lineWidth = 3.0
            sl.strokeColor = color
            root.addSublayer(sl)
            self.shapeLayer = sl
        }
        
        override func resizeLayers(frame: CGRect, graphView: OneWheelGraphView) {
            let position = CGPoint(x: frame.midX, y: frame.midY)
            
            shapeLayer?.bounds = frame
            shapeLayer?.position = position

            bgMaskLayer?.bounds = frame
            bgMaskLayer?.position = position
            
            bgLayer?.bounds = frame
            bgLayer?.position = position
            
            if let shapeLayer = self.shapeLayer{

                let newPath = createPath(rect: frame, graphView: graphView)
                animateShapeLayerPath(shapeLayer: shapeLayer, newPath: newPath)
             
                if gradientUnderPath, let bgMaskLayer = self.bgMaskLayer {
                    let newMaskPath = closePath(path: newPath, rect: frame)
                    animateShapeLayerPath(shapeLayer: bgMaskLayer, newPath: newMaskPath)
                }
            }
        }
        
        override func bindData(rect: CGRect, graphView: OneWheelGraphView) {
            if let shapeLayer = self.shapeLayer {
                let path = createPath(rect: rect, graphView: graphView)
                shapeLayer.path = path
                
                
                if gradientUnderPath {
                    bgMaskLayer?.path = closePath(path: path, rect: rect)
                    bgLayer?.mask = bgMaskLayer
                }
            }
        }
        
        private func closePath(path: CGPath, rect: CGRect) -> CGPath {
            let maskPath = path.mutableCopy()!
            maskPath.addLine(to: CGPoint(x: lastX, y: rect.height))
            maskPath.addLine(to: CGPoint(x: rect.origin.x, y: rect.height))
            maskPath.closeSubpath()
            return maskPath
        }
        
        private func createPath(rect: CGRect, graphView: OneWheelGraphView) -> CGMutablePath {
            NSLog("CALayer - createPath \(self.name)")
            
            // TODO : Guard graphView, series etc.
            let path = CGMutablePath()
            var didInitPath = false
            
            forEachData(rect: rect, graphView: graphView) { (x, state) -> CGFloat in
                let normVal = CGFloat(getNormalizedVal(state: state))
                let y = ((1.0 - normVal) * rect.height) + rect.origin.y
                
                if !didInitPath {
                    didInitPath = true
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                return y
            }
            
            return path
        }
    }
    
    class Series : NSObject {
        
        enum AxisLabelType {
            case None
            case Left
            case Right
        }
        
        let name: String
        let color: CGColor
        let evaluator: SeriesEvaluator
        let labelType: AxisLabelType
        let gradientUnderPath: Bool
        
        var min = 0.0
        var max = 0.0
        
        var lastX: CGFloat = 0.0
        var lastY: CGFloat = 0.0
        
        // Drawing
        internal var didSetupLayers = false // private set
        
        init(name: String, color: CGColor, labelType: AxisLabelType, gradientUnderPath: Bool, evaluator: SeriesEvaluator) {
            self.name = name
            self.color = color
            self.labelType = labelType
            self.gradientUnderPath = gradientUnderPath
            self.evaluator = evaluator
        }
        
        func requestLayerSetup(root: CALayer, frame: CGRect, graphView: OneWheelGraphView) {
            if didSetupLayers {
                return
            }
            didSetupLayers = true
            
            setupLayers(root: root, frame: frame, graphView: graphView)
        }
        
        internal func setupLayers(root: CALayer, frame: CGRect, graphView: OneWheelGraphView) {
            // Subclass override
        }
        
        internal func resizeLayers(frame: CGRect, graphView: OneWheelGraphView) {
            // Subclass override
        }
        
        func bindData(rect: CGRect, graphView: OneWheelGraphView) {
            // Subclass override
        }
        
        // Return the normalized value at the given index.
        // returns a value between [0, 1]
        func getNormalizedVal(state: OneWheelState) -> Double {
            let val = evaluator.getValForState(state: state)
            return (val / (max - min))
        }
        
        internal func forEachData(rect: CGRect, graphView: OneWheelGraphView, onData: (CGFloat, OneWheelState) -> CGFloat) {
            lastX = 0
            lastY = rect.height
            
            for cacheIdx in 0..<graphView.stateCache.count {
                let state = graphView.stateCache[cacheIdx]
                let x = graphView.stateXPosCache[cacheIdx]
                
                let y = onData(x, state)

                lastX = x
                lastY = y
            }
        }
        
        internal func animateShapeLayerPath(shapeLayer: CAShapeLayer, newPath: CGPath) {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = shapeLayer.path
            animation.toValue = newPath
            
            shapeLayer.add(animation, forKey: "path")
            shapeLayer.path = newPath
        }
        
        func drawAxisLabels(rect: CGRect, numLabels: Int, bgColor: CGColor, context: CGContext) {
            if labelType == AxisLabelType.None {
                return
            }
            
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
    
    class ControllerTempSeries : ValueSeries, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, labelType: AxisLabelType.None, gradientUnderPath: false, evaluator: self)
            max = 120 // TODO: Figure out reasonable max temperatures
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return Double(state.controllerTemp)
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))°F"
        }
    }
    
    class MotorTempSeries : ValueSeries, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, labelType: AxisLabelType.Right, gradientUnderPath: false, evaluator: self)
            max = 120 // TODO: Figure out reasonable max temperatures
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return Double(state.motorTemp)
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))°F"
        }
    }
    
    class SpeedSeries : ValueSeries, SeriesEvaluator {

        init(name: String, color: CGColor) {
            super.init(name: name, color: color, labelType: AxisLabelType.Left, gradientUnderPath: true, evaluator: self)
            max = 20.0 // Current world record is ~ 27 MPH
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return state.mph()
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))MPH"
        }
    }
    
    class BatterySeries : ValueSeries, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, labelType: AxisLabelType.Right, gradientUnderPath: false, evaluator: self)
            max = 100.0
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return Double(state.batteryLevel)
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))%"
        }
    }
    
    class ErrorSeries : BooleanSeries, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, labelType: AxisLabelType.None, gradientUnderPath: false, evaluator: self)
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
