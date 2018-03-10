//
//  OneWheelGraphView.swift
//  OneWheel
//
//  Created by David Brodsky on 1/5/18.
//  Copyright © 2018 David Brodsky. All rights reserved.
//

import UIKit
import GRDB

class OneWheelGraphView: UIView {
    
    private let rideData = RideLocalData()
    
    let zoomHintColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0).cgColor
    
    var dataSource: GraphDataSource?
    var dataRange = CGPoint(x: 0.0, y: 1.0) //x - min, y - max
    var series = [String: Series]()
    var bgColor: UIColor = UIColor(white: 0.0, alpha: 1.0) {
        didSet {
            self.backgroundColor = bgColor
        }
    }
    var bgTransparentColor: CGColor {
        get {
            return bgColor.cgColor.copy(alpha: 0.0)!
        }
    }
    
    var portraitMode: Bool = false {
        didSet {
            NSLog("Set portrait mode \(portraitMode)")
            if portraitMode {
                resetDataRange()
            }
        }
    }
    
    // Data cahce
    var rowCache = [Row]()
    
    // Display rects
    var seriesRect = CGRect()
    var seriesAxisRect = CGRect()
    var timeLabelsRect = CGRect()
    
    // Layers managed by view
    var zoomLayer = CALayer()
    var axisLabelLayer = CALayer()
    var timeAxisLabels : [CATextLayer]? = nil  // sublayers of axisLabelLayer
    var zoomHintLayer: CAShapeLayer? = nil
    
    // Gestures
    var lastScale: CGFloat = 1.0
    var lastScalePoint: CGPoint? = nil
    var isGesturing = false
    
    // For time axis labels
    private var startTime: Date? = nil
    private var endTime: Date? = nil
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        calculateRects()
        
        zoomLayer.frame = seriesAxisRect
        zoomLayer.masksToBounds = true
        self.layer.addSublayer(zoomLayer)
        
        axisLabelLayer.frame = seriesAxisRect
        self.layer.addSublayer(axisLabelLayer)
    }
    
    private func calculateRects() {
        NSLog("Calculate rects with bounds \(self.bounds)")
        let seriesAxisRect = self.bounds.insetBy(dx: 0.0, dy: 11.0).applying(CGAffineTransform(translationX: 0.0, y: -11.0))
        let timeLabelsRect = portraitMode ? self.bounds.insetBy(dx: 20.0, dy: 0.0) : self.bounds.insetBy(dx: 40.0, dy: 0.0).applying(CGAffineTransform(translationX: 7.0, y: 0.0)) // last affineT is a janky compensation for the MPH / Battery label width differences :/
        let seriesRect = portraitMode ? seriesAxisRect.insetBy(dx: 20.0, dy: 0.0).applying(CGAffineTransform(translationX: -20.0, y: 0.0)) : seriesAxisRect.insetBy(dx: 45.0, dy: 0.0).applying(CGAffineTransform(translationX: 7.0, y: 0.0))
    
        self.seriesRect = seriesRect
        self.seriesAxisRect = seriesAxisRect
        self.timeLabelsRect = timeLabelsRect
    }
    
    public override func layoutSublayers(of layer: CALayer) {

        if (!isGesturing) {
            NSLog("CALayer - layoutSublayers with bounds \(self.bounds) frame \(self.frame)")
            refreshGraph()
        }
        super.layoutSublayers(of: layer)
    }
    
    private func resizeLayers() {
        calculateRects()
        
        // Resize layers, but do not reset transform
        self.zoomLayer.bounds = seriesRect
        self.zoomLayer.position = CGPoint(x: seriesRect.midX, y: seriesRect.midY)
        
        self.axisLabelLayer.bounds = seriesAxisRect
        self.axisLabelLayer.position = CGPoint(x: seriesAxisRect.midX, y: seriesAxisRect.midY)
        
        for (_, series) in self.series {
            series.resizeLayers(frame: seriesRect, graphView: self)
        }
    }
    
    // Whether to fully draw every intermediate zoom step (true) or transform view until pan complete (false)
    // TODO : smoothPinch not yet finished
    var smoothPinch = false

    func onPinch(_ sender: UIPinchGestureRecognizer) {
        if portraitMode {
            return
        }
        
        if sender.state == .began {
            isGesturing = true
        }
        
        if sender.state == .changed {
            
            if !smoothPinch {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                // Only scale x axis
                let scale = sender.scale
                sender.scale = 1.0
                lastScale = scale
                
                var point = sender.location(in: self)
                point = self.layer.convert(point, to: zoomLayer)
                point.x -= zoomLayer.bounds.midX  // zoomLayer anchorPoint is at center
                var transform = CATransform3DTranslate(zoomLayer.transform, point.x, 0.0, 0.0)
                transform = CATransform3DScale(transform, scale, 1.0, 1.0)
                transform = CATransform3DTranslate(transform, -point.x, 0.0, 0.0)
                zoomLayer.transform = transform
                //let xTrans = zoomLayer.value(forKeyPath: "transform.translation.x")
                //let xScale = zoomLayer.value(forKeyPath: "transform.scale.x") as! CGFloat
                let dataScale = dataRange.y - dataRange.x
                let xScale = 1 / dataScale
                
                let seriesRectFromZoomLayer = self.layer.convert(self.seriesRect, from: self.zoomLayer)
                let zlVisibleFrac = (self.seriesRect.width / seriesRectFromZoomLayer.width)
                let zlStartFrac = (self.seriesRect.origin.x - seriesRectFromZoomLayer.origin.x) / seriesRectFromZoomLayer.width
                
                let newDataRange = CGPoint(x: max(0.0, dataRange.x + (zlStartFrac / xScale)), y: min(1.0, dataRange.x + ((zlStartFrac + zlVisibleFrac) / xScale)))
                drawZoomHint(rect: seriesRect, root: axisLabelLayer, dataRange: newDataRange)
                CATransaction.commit()
            } else {
                let dataScale = dataRange.y - dataRange.x
                let xScale = 1 / dataScale
                
                let seriesRectFromZoomLayer = self.layer.convert(self.seriesRect, from: self.zoomLayer)
                let zlVisibleFrac = (self.seriesRect.width / seriesRectFromZoomLayer.width)
                let zlStartFrac = (self.seriesRect.origin.x - seriesRectFromZoomLayer.origin.x) / seriesRectFromZoomLayer.width
                
                let newDataRange = CGPoint(x: max(0.0, dataRange.x + (zlStartFrac / xScale)), y: min(1.0, dataRange.x + ((zlStartFrac + zlVisibleFrac) / xScale)))
                
                //NSLog("Pinch to [\(newDataRange.x):\(newDataRange.y)]")
                if newDataRange != self.dataRange && (newDataRange.y - newDataRange.x < 1.0) {
                    // Zoomed in
                    NSLog("Pinch to [\(newDataRange.x):\(newDataRange.y)]")
                    self.dataRange = newDataRange
                    refreshGraph()
                } else if newDataRange != self.dataRange {
                    // Zoomed all the way out
                    resetDataRange()
                    refreshGraph()
                } else {
                    // no-op
                }
            }
            
        } else if (sender.state == .ended) {
            
            isGesturing = false
            
            let dataScale = dataRange.y - dataRange.x
            let xScale = 1 / dataScale
            
            let seriesRectFromZoomLayer = self.layer.convert(self.seriesRect, from: self.zoomLayer)
            let zlVisibleFrac = (self.seriesRect.width / seriesRectFromZoomLayer.width)
            let zlStartFrac = (self.seriesRect.origin.x - seriesRectFromZoomLayer.origin.x) / seriesRectFromZoomLayer.width
            
            let newDataRange = CGPoint(x: max(0.0, dataRange.x + (zlStartFrac / xScale)), y: min(1.0, dataRange.x + ((zlStartFrac + zlVisibleFrac) / xScale)))
            
            //NSLog("Pinch to [\(newDataRange.x):\(newDataRange.y)]")
            if newDataRange != self.dataRange && (newDataRange.y - newDataRange.x < 1.0) {
                // Zoomed in
                NSLog("Pinch to [\(newDataRange.x):\(newDataRange.y)]")
                self.dataRange = newDataRange
                refreshGraph()
            } else if newDataRange != self.dataRange {
                // Zoomed all the way out
                resetDataRange()
                refreshGraph()
            } else {
                // Animate transform back to identity. No meaningful zoom happened (e.g: Just zoomed out 1x scale)
                zoomLayer.transform = CATransform3DIdentity
            }
        }
    }
    
    // Whether to fully draw every intermediate pan step (true) or transform view until pan complete (false)
    var smoothPan = true
    
    func onPan(_ sender: UIPanGestureRecognizer) {
        if portraitMode {
            return
        }
        
        if sender.state == .began {
            isGesturing = true
        }
        
        let dataScale = dataRange.y - dataRange.x
        let xScale = 1 / dataScale
        let translation = sender.translation(in: self)
        let xTransNormalized = translation.x / xScale
        
        // Rect-based xTrans measurements only work with smoothPan false e.g: When we're translating layer
        let seriesRectFromZoomLayer = self.layer.convert(self.seriesRect, from: self.zoomLayer)
        let xTransRaw = self.seriesRect.origin.x - seriesRectFromZoomLayer.origin.x
        let xTrans = (xTransRaw / self.seriesRect.width) / xScale
        let dataRangeLeeway = (xTrans > 0) ? /* left */ 1.0 - dataRange.y : /* right */ dataRange.x
        let xTransNormal = min(dataRangeLeeway, xTrans)
        sender.setTranslation(CGPoint.zero, in: self)
        
        let xTransInDataRange = (translation.x / self.seriesRect.width) / xScale
        NSLog("xT \(xTransInDataRange), xTnormal \(xTransNormal)")

        if sender.state == .changed {
            
            // Limit pan

            if (!smoothPan) {
                
                // TODO: Xcode complaining about complexity of expression. Something's wrong here...
//                if xScale <= 1.0 ||                                                             // Not zoomed in
//                    (xTransNormalized > 0.0 && self.dataRange.x + xTransNormal <= 0.0) ||       // Panning beyond left bounds
//                    (xTransNormalized < 0.0 && self.dataRange.x + xTransNormal >= 1.0) {        // Panning beyond right bounds
//                    return
//                }

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                zoomLayer.transform = CATransform3DTranslate(zoomLayer.transform, xTransNormalized, 0.0, 0.0)
                CATransaction.commit()
            } else {
                
                if xScale <= 1.0 ||                                        // Not zoomed in
                    (self.dataRange.x - xTransInDataRange <= 0.0) ||       // Panning beyond left bounds
                    (self.dataRange.y - xTransInDataRange >= 1.0) {        // Panning beyond right bounds
                    return
                }
                
                let newDataRange = CGPoint(x: max(0, self.dataRange.x - xTransInDataRange), y: min(1.0, self.dataRange.y - xTransInDataRange))
                if newDataRange != self.dataRange {
                    self.dataRange = newDataRange
                    refreshGraph()
                }
            }
            
        } else if (sender.state == .ended) {
            
            isGesturing = false

            let newDataRange = CGPoint(x: max(0, self.dataRange.x + xTransNormal), y: min(1.0, self.dataRange.y + xTransNormal))
            
            NSLog("Pan [\(dataRange) -> \(newDataRange)")

            if newDataRange != self.dataRange {
                self.dataRange = newDataRange
                refreshGraph()
            }
        }
    }
    
    func refreshGraph() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        zoomLayer.transform = CATransform3DIdentity
        
        resizeLayers()
        
        if let dataSource = self.dataSource {
            
            let dataSourceCount = dataSource.getCount()
            
            for (_, series) in self.series {

                if series is SpeedSeries {
                    series.max = max((series as! SpeedSeries).defaultMax, 1.10 * rpmToMph(Double(rideData.getMaxRpm())))
                }

                series.startNewPath(rect: seriesRect, numItems: dataSourceCount, graphView: self)
            }
            
            let rect = seriesRect
            let dataCount = Int(CGFloat(dataSourceCount) * (dataRange.y - dataRange.x))
            let widthPtsPerData: CGFloat = 2
            let maxPoints = Int(rect.width / widthPtsPerData)
            let numPoints = min(dataCount, maxPoints)
            let deltaX = rect.width / (CGFloat(numPoints - 1))
            var x: CGFloat = rect.origin.x
            
            if dataSourceCount != rowCache.count {
                // Cache rows and append to series paths
                
                let dataIdxstart = Int(CGFloat(dataSourceCount) * dataRange.x)
                let dataIdxend = Int(CGFloat(dataSourceCount) * dataRange.y)
                // Using floor below potentially gives us more points than we need, using ceil gives us potentially less
                let stride = (numPoints > 0) ? Int(ceil(Double((dataIdxend - dataIdxstart)) / Double(numPoints))) : 1
                let numPointsFinal = (dataIdxend - dataIdxstart) / stride
                let deltaXFinal = rect.width / (CGFloat(numPointsFinal - 1))

                NSLog("Query [\(dataIdxstart):\(dataIdxend)] [\(CGFloat(dataIdxstart)/CGFloat(dataSourceCount)):\(CGFloat(dataIdxend) / CGFloat(dataSourceCount))] mod \(stride) numPoints \(numPointsFinal)")
                if let cursor = dataSource.getCursor(start: dataIdxstart, end: dataIdxend, stride: stride) {

                    rowCache.removeAll()
                    
                    var dataIdx = 0
                    
                    var startIdx: Int = 0, endIdx: Int = 0
                    
                    try? cursor.forEach({ (row) in
                        //NSLog("dataIdx \(dataIdx) id \(row[colIdxId])")
                        if dataIdx == 0 {
                            startIdx = row[colIdxId]
                            startTime = row[colIdxTime]
                        }
                        if dataIdx == numPointsFinal - 1 {
                            endIdx = row[colIdxId]
                            endTime = row[colIdxTime]
                        }
                        
                        if isGesturing {
                            // If we're gesturing, don't bother caching because we're going to do many draws with varying data range
                            appendRowToPath(x: x, row: row)
                        } else {
                            let rowCopy = row.copy()
                            appendRowToPath(x: x, row: rowCopy)
                            rowCache.append(rowCopy)
                        }
                        
                        dataIdx += 1
                        x += deltaXFinal
                    })
                    
                    let startFrac = CGFloat(startIdx) / CGFloat(dataSourceCount)
                    let endFrac = CGFloat(endIdx) / CGFloat(dataSourceCount)

                    NSLog("Query result to [\(startIdx):\(endIdx)] [\(startFrac):\(endFrac)]")
                } else {
                    NSLog("Fuckup alert, no cursor")
                    return
                }
            } else if rowCache.count > 0 {
                NSLog("Re-using rowCache")

                // We just need to append cached rows to series paths
                self.startTime = rowCache[0][colIdxTime]
                self.endTime = rowCache[rowCache.count - 1][colIdxTime]
                for row in rowCache {
                    appendRowToPath(x: x, row: row)
                    x += deltaX
                }
            } else {
                // No data
                self.startTime = Date()
                self.endTime = Date()
            }
            
            // Complete paths
            for (_, series) in self.series {
                series.completePath()
            }
            drawLayers()
            CATransaction.commit()
        }
    }
    
    private func appendRowToPath(x: CGFloat, row: Row) {
        for (_, series) in self.series {
            series.appendToPath(x: x, row: row)
        }
    }
    
    func drawLayers() {
        NSLog("Draw layers")
        drawLabels()
        //axisLabelLayer.display()
        zoomLayer.display()
        zoomLayer.sublayers?.forEach {
            $0.display()
            //NSLog("Draw zoomLayer sublayer \($0.name)")
        }
    } // willRotate, layoutSublayers,
    
    private func drawLabels() {
        //NSLog("Draw axisLabelLayer in")
        
        var seriesAxisLabelRect = seriesAxisRect
        for (_, series) in series {
            if series is SpeedSeries && series.drawMaxValLineWithAxisLabels {
                let maxValFrac = (series as! ValueSeries).getMaximumValueInfo().1
                if maxValFrac > 0 {
                    series.drawSeriesMaxVal(rect: seriesRect, root: layer, bgColor: bgColor.cgColor, maxVal: CGFloat(maxValFrac), portraitMode: portraitMode)
                }
            }
            series.drawAxisLabels(rect: seriesAxisLabelRect, root: axisLabelLayer, numLabels: 5, bgColor: bgColor.cgColor)
            
            if series.labelType == .Right { // TODO : Assumes duplicate labels only on right
                // Keep insetting axis label rect to allow stacking labels instead of having them overlap
                seriesAxisLabelRect = seriesAxisLabelRect.insetBy(dx: 20.0, dy: 0.0).applying(CGAffineTransform(translationX: -20.0, y: 0.0))
            }
        }
        
        if let _ = dataSource {
            drawTimeLabels(rect: timeLabelsRect, root: axisLabelLayer) //, numLabels: 3)
        }
        drawZoomHint(rect: seriesRect, root: axisLabelLayer, dataRange: self.dataRange)
    }
    
    private func resetDataRange() {
        self.dataRange = CGPoint(x: 0.0, y: 1.0)
    }
    
    func drawTimeLabels(rect: CGRect, root: CALayer) { //}, numLabels: Int) {
        let numLabels = 3 // For now, just draw start (left), center with mileage, and end (right)
        NSLog("drawTimeLabels")
        
        if timeAxisLabels == nil {
            timeAxisLabels = [CATextLayer]()
        }
        
        while (timeAxisLabels!.count < numLabels) {
            let newLayer = CATextLayer()
            timeAxisLabels?.append(newLayer)
            root.addSublayer(newLayer)
        }

        let dataCount = dataSource!.getCount()
        
        if dataCount == 0 {
            return
        }
        
        let labelFont = UIFont.systemFont(ofSize: 14.0)
        
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        
        let labelSideMargin: CGFloat = 5
        for axisLabelIdx in 0..<numLabels {
            
            let axisLabelFrac: CGFloat = CGFloat(axisLabelIdx) / CGFloat(numLabels-1)
            let date: Date = axisLabelIdx == 0 ? startTime! : endTime!
            
            let x: CGFloat = (rect.width * axisLabelFrac) + rect.origin.x
            var axisLabel = formatter.string(from: date)
            
            // If there's a middle label, use that for general info: distance, battery %
            if axisLabelIdx % 2 == 1 && axisLabelIdx == (numLabels / 2) {
                let batt = rideData.getLastBattery()
                let odometer = rideData.getOdometerSum()
                // If both are 0 we probably haven't initialized. Should use a no value constant to differentiate from 0
                if !(batt == 0 && odometer == 0) {
                    let miles = revolutionstoMiles(Double(rideData.getOdometerSum()))
                    let milesStr = String(format: "%.1f", miles)
                    axisLabel = "\(milesStr) Miles | \(batt)%"
                }
            }
            var labelRect = axisLabel.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [NSAttributedStringKey.font: labelFont], context: nil)
            var rectX = x - (labelRect.width / 2)
            let rectY = rect.height - labelSideMargin - labelRect.height
            
            let labelLayer = timeAxisLabels![axisLabelIdx]
            labelLayer.isHidden = false
            labelLayer.font = labelFont
            labelLayer.fontSize = labelFont.pointSize
            labelLayer.foregroundColor = UIColor.white.cgColor
            labelLayer.backgroundColor = bgColor.cgColor
            labelLayer.contentsScale = UIScreen.main.scale
            
            if axisLabelIdx == 0 {
                rectX = labelSideMargin + x
                labelLayer.alignmentMode = "left"
            } else if axisLabelIdx == numLabels - 1 {
                rectX = x - labelSideMargin - labelRect.width
                labelLayer.alignmentMode = "right"
            } else {
                labelLayer.alignmentMode = "center"
            }
            
            labelLayer.string = axisLabel
            
            labelRect = CGRect(x: rectX, y: rectY, width: labelRect.width, height: labelRect.height)
            labelLayer.frame = labelRect
            labelLayer.display()
            
            //NSLog("Drawing time axis label \(axisLabel)")
        }
        
        for i in numLabels..<timeAxisLabels!.count {
            timeAxisLabels![i].isHidden = true
            NSLog("Hiding time axis label \(timeAxisLabels![i].string)")
        }
    }
    
    func drawZoomHint(rect: CGRect, root: CALayer, dataRange: CGPoint) {
        //NSLog("drawZoomHint")
        if dataRange.y - dataRange.x == 1.0 {
            // Don't draw zoom hint when zoomed all the way out
            zoomHintLayer?.isHidden = true
            return
        }
        
        if zoomHintLayer == nil {
            zoomHintLayer = CAShapeLayer()
            root.addSublayer(zoomHintLayer!)
        }
        
        let yPad: CGFloat = 3.0
        let yHeight: CGFloat = 3.0
        
        let zoomStart = rect.origin.x + (dataRange.x * rect.width)
        let zoomEnd = zoomStart + ((dataRange.y - dataRange.x) * rect.width)
        
        let rt = CGRect(x: zoomStart, y: yPad, width: zoomEnd - zoomStart, height: yHeight)
        zoomHintLayer!.cornerRadius = 2.0
        zoomHintLayer!.isHidden = false
        zoomHintLayer!.frame = rt
        zoomHintLayer!.backgroundColor = zoomHintColor
    }

    func addSeries(newSeries: Series) {
        if self.dataSource != nil {
            series[newSeries.name] = newSeries
            //addSeriesSubLayer(series: newSeries) BAD_ACCESS
            newSeries.requestLayerSetup(root: self.zoomLayer, frame: seriesRect, graphView: self)
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
            let midPt = CGPoint(x: frame.midX, y: frame.midY)
            
            layer?.bounds = frame
            layer?.position = midPt
            
//            if let path = self.path, !path.boundingBox.isEmpty, let layer = self.layer {
//
//                let newPath = createPath(rect: frame, graphView: graphView)
//                animateShapeLayerPath(shapeLayer: layer, newPath: newPath)
//            }
        }
        
//        override func bindData(rect: CGRect, graphView: OneWheelGraphView) {
//            layer?.setNeedsDisplay()
//
//            if let layer = self.layer {
//                let path = createPath(rect: rect, graphView: graphView)
//                layer.path = path
//            }
//        }
//
//        private func createPath(rect: CGRect, graphView: OneWheelGraphView) -> CGPath {
//            let path = CGMutablePath()
//            forEachData(rect: rect, graphView: graphView) { (x, state) -> CGFloat in
//                let normVal = CGFloat(getNormalizedVal(state: state))
//                if normVal == 1.0 {
//                    let errorRect = CGRect(x: lastX, y: rect.origin.y, width: (x-lastX), height: rect.height)
//                    path.addRect(errorRect)
//                }
//                return rect.origin.y
//            }
//            return path
//        }
    }
    
    class ValueSeries : Series {
        
        private var shapeLayer: CAShapeLayer? = nil
        private var bgLayer: CAGradientLayer? = nil
        private var bgMaskLayer: CAShapeLayer? = nil
        
        private var path: CGMutablePath? = nil
        private var pathRect: CGRect? = nil
        var didInitPath = false
        
        override func setupLayers(root: CALayer, frame: CGRect, graphView: OneWheelGraphView) {
            let scale = UIScreen.main.scale
            
            if gradientUnderPath {
                let bgM = CAShapeLayer()
                bgM.contentsScale = scale
                bgM.frame = frame
                bgM.fillColor = color
                self.bgMaskLayer = bgM
                
                let bg = CAGradientLayer()
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
            sl.miterLimit = 0
            sl.contentsScale = scale
            sl.frame = frame
            sl.fillColor = UIColor.clear.cgColor
            sl.lineWidth = 3.0
            sl.strokeColor = color
            root.addSublayer(sl)
            self.shapeLayer = sl
        }
        
        override func resizeLayers(frame: CGRect, graphView: OneWheelGraphView) {
            let midPt = CGPoint(x: frame.midX, y: frame.midY)
            
            shapeLayer?.bounds = frame
            shapeLayer?.position = midPt
            
            bgMaskLayer?.bounds = frame
            bgMaskLayer?.position = midPt
            
            bgLayer?.bounds = frame
            bgLayer?.position = midPt
            
            // TODO : We could use rowCache to re-create paths for animating
//            if let shapeLayer = self.shapeLayer {
//
//                let newPath = createPath(rect: frame, graphView: graphView)
//                animateShapeLayerPath(shapeLayer: shapeLayer, newPath: newPath)
//
//                if gradientUnderPath, let bgMaskLayer = self.bgMaskLayer {
//                    let newMaskPath = closePath(path: newPath, rect: frame)
//                    animateShapeLayerPath(shapeLayer: bgMaskLayer, newPath: newMaskPath)
//                    bgLayer?.mask = bgMaskLayer
//                }
//            }
        }
        
        override func startNewPath(rect: CGRect, numItems: Int, graphView: OneWheelGraphView) {
            NSLog("NewPath")
            self.pathRect = rect
            self.path = CGMutablePath()
            didInitPath = false
        }
        
        override func appendToPath(x: CGFloat, row: Row) {
            let normVal = CGFloat(getNormalizedVal(row: row))
            let y = ((1.0 - normVal) * pathRect!.height) + pathRect!.origin.y
            if !didInitPath {
                didInitPath = true
                path!.move(to: CGPoint(x: x, y: y))
                //NSLog("AppendPath move to \(CGPoint(x: x, y: y))")

            } else {
                path!.addLine(to: CGPoint(x: x, y: y))
                //NSLog("AppendPath line to \(CGPoint(x: x, y: y))")
            }
        }
        
        override func completePath() {
            shapeLayer?.path = path
            if gradientUnderPath {
                bgMaskLayer?.path = closePath(path: path!, rect: pathRect!)
                bgLayer?.mask = bgMaskLayer
            }
        }
        
        // Subclass overrides
        public func getMaximumValueInfo() -> (Date, Float) {
            return (Date.distantFuture, 0.0)
        }
        
        private func closePath(path: CGPath, rect: CGRect) -> CGPath {
            let maskPath = path.mutableCopy()!
            maskPath.addLine(to: CGPoint(x: rect.maxX, y: rect.height))
            maskPath.addLine(to: CGPoint(x: rect.origin.x, y: rect.height))
            maskPath.closeSubpath()
            return maskPath
        }
        
//        private func createPath(rect: CGRect, graphView: OneWheelGraphView) -> CGMutablePath {
//            NSLog("CALayer - ValueSeries createPath \(self.name) in \(rect)")
//
//            // TODO : Guard graphView, series etc.
//            let path = CGMutablePath()
//            var didInitPath = false
//
//            forEachData(rect: rect, graphView: graphView) { (x, state) -> CGFloat in
//                let normVal = CGFloat(getNormalizedVal(state: state))
//                let y = ((1.0 - normVal) * rect.height) + rect.origin.y
//
//                if !didInitPath {
//                    didInitPath = true
//                    path.move(to: CGPoint(x: x, y: y))
//                } else {
//                    path.addLine(to: CGPoint(x: x, y: y))
//                }
//
//                return y
//            }
//            NSLog("CALayer - createdPath \(self.name) in \(path.boundingBox)")
//
//            return path
//        }
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
        
        var drawMaxValLineWithAxisLabels = false
        
        var min = 0.0
        var max = 0.0
        
        var lastX: CGFloat = 0.0
        var lastY: CGFloat = 0.0
        
        private let shapeAnimateDurationS = 0.100
        
        // Drawing
        internal var didSetupLayers = false // private set
        internal var axisLabelLayers: [CATextLayer]? = nil
        internal var maxValLayer: CAShapeLayer? = nil
        internal var maxValLabel: CATextLayer? = nil
        
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
        
        func startNewPath(rect: CGRect, numItems: Int, graphView: OneWheelGraphView) {
            // Subclass override
            // e.g: Begin new path
        }
        
        func appendToPath(x: CGFloat, row: Row) {
            // Subclass override
            // e.g: Add point from row to path
        }
        
        func completePath() {
            // Subclass override
            // e.g: Set path to shape layer
        }
        
        // Return the normalized value at the given index.
        // returns a value between [0, 1]
        func getNormalizedVal(row: Row) -> Double {
            let val = evaluator.getValForRow(row: row)
            return (val / (max - min))
        }
        
//        internal func forEachData(rect: CGRect, graphView: OneWheelGraphView, onData: (CGFloat, OneWheelState) -> CGFloat) {
//            lastX = 0
//            lastY = rect.height
//
//            for cacheIdx in 0..<graphView.stateCache.count {
//                let state = graphView.stateCache[cacheIdx]
//                let x = graphView.stateXPosCache[cacheIdx]
//
//                let y = onData(x, state)
//
//                lastX = x
//                lastY = y
//            }
//        }
        
        internal func animateShapeLayerPath(shapeLayer: CAShapeLayer, newPath: CGPath) {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = shapeLayer.path
            animation.toValue = newPath
            animation.duration = shapeAnimateDurationS
            animation.timingFunction =  CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
            shapeLayer.add(animation, forKey: "path")
            shapeLayer.path = newPath
        }
        
        internal func animateLayerPosition(layer: CALayer, newPos: CGPoint) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = layer.position
            animation.toValue = newPos
            animation.duration = shapeAnimateDurationS
            animation.timingFunction =  CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
            layer.add(animation, forKey: "position")
            layer.position = newPos
            CATransaction.commit()
        }
        
        func drawAxisLabels(rect: CGRect, root: CALayer, numLabels: Int, bgColor: CGColor) {
            if labelType == AxisLabelType.None {
                for layer in axisLabelLayers ?? [] {
                    layer.isHidden = true
                }
                return
            }
            
            if axisLabelLayers == nil {
                axisLabelLayers = [CATextLayer]()
            }
            
            while (axisLabelLayers!.count < numLabels) {
                let newLayer = CATextLayer()
                axisLabelLayers?.append(newLayer)
                root.addSublayer(newLayer)
            }
            
            let labelFont = UIFont.systemFont(ofSize: 14.0)
            
            var labelIdx = 0
            let labelSideMargin: CGFloat = 5
            let x: CGFloat = (labelType == AxisLabelType.Left) ? CGFloat(labelSideMargin) : rect.width - labelSideMargin
            for axisLabelVal in stride(from: min, through: max, by: (max - min) / Double(numLabels)) {
                // TODO : Re-evaluate, but for now don't draw 0-val label
                if axisLabelVal == min {
                    continue
                }
                
                let y = CGFloat(1.0 - ((axisLabelVal - min) / (max - min))) * rect.height
                let axisLabel = printAxisVal(val: axisLabelVal)
                
                let labelLayer = axisLabelLayers![labelIdx]
                labelLayer.isHidden = false
                labelLayer.font = labelFont
                labelLayer.fontSize = labelFont.pointSize
                labelLayer.alignmentMode = (labelType == AxisLabelType.Left) ? "left" : "right"
                labelLayer.foregroundColor = color
                labelLayer.backgroundColor = bgColor
                labelLayer.string = axisLabel
                labelLayer.contentsScale = UIScreen.main.scale
                
                var labelRect = axisLabel.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [NSAttributedStringKey.font: labelFont], context: nil)
                let rectX = (labelType == AxisLabelType.Right) ? x - labelRect.width : x
                labelRect = CGRect(x: rectX, y: y, width: labelRect.width, height: labelRect.height)
                labelLayer.frame = labelRect
                labelLayer.display()
                //NSLog("Axis label \(axisLabel) at \(labelLayer.position)")
                labelIdx += 1

                // Assumes RTL language : When positioning left-flowing text on the right side, need to move our start point left by the text width
            }
            
            for i in labelIdx..<axisLabelLayers!.count {
                axisLabelLayers![i].isHidden = true
            }
        }
        
        func drawSeriesMaxVal(rect: CGRect, root: CALayer, bgColor: CGColor, maxVal: CGFloat, portraitMode: Bool) {
            NSLog("drawSeriesMaxVal")
            
            if (maxValLayer == nil) {
                maxValLayer = CAShapeLayer()
                root.addSublayer(maxValLayer!)
            }
            if (maxValLabel == nil) {
                maxValLabel = CATextLayer()
                root.addSublayer(maxValLabel!)
            }
            
            maxValLayer!.frame = rect
            maxValLabel!.frame = rect
            
            let labelSideMargin: CGFloat = portraitMode ? 60 : 10  // In portrait mode we let the seriesRect extend behind axis labels
            let maxYPos: CGFloat = ((1.0 - maxVal) * rect.height) + rect.origin.y
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: maxYPos))
            path.addLine(to: CGPoint(x: rect.width, y: maxYPos))
            // TODO : Line properties
            maxValLayer!.path = path
            maxValLayer!.strokeColor = color.copy(alpha: 0.7)
            maxValLayer!.lineWidth = 1.0
            
            let maxLabel = String(format: "%.1f", (Double(maxVal) * max))
            
            let labelFont = UIFont.systemFont(ofSize: 12.0)
            
            var labelRect = maxLabel.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [NSAttributedStringKey.font: labelFont], context: nil)
            labelRect = CGRect(x: rect.minX + labelSideMargin, y: maxYPos - (labelRect.height / 2), width: labelRect.width, height: labelRect.height)

            maxValLabel!.frame = labelRect
            maxValLabel!.isHidden = false
            maxValLabel!.font = labelFont
            maxValLabel!.fontSize = labelFont.pointSize
            maxValLabel!.alignmentMode = "left"
            maxValLabel!.foregroundColor = color
            maxValLabel!.backgroundColor = bgColor
            maxValLabel!.string = maxLabel
            maxValLabel!.contentsScale = UIScreen.main.scale
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
        
        func getValForRow(row: Row) -> Double {
            return (row[colIdxControllerTemp] as Double)
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
        
        func getValForRow(row: Row) -> Double {
            return (row[colIdxMotorTemp] as Double)
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))°F"
        }
    }
    
    class SpeedSeries : ValueSeries, SeriesEvaluator {
        
        public let defaultMax = 20.0  // Current world record is ~ 27 MPH
        
        let rideLocalData: RideLocalData

        init(name: String, color: CGColor, rideData: RideLocalData) {
            self.rideLocalData = rideData
            
            super.init(name: name, color: color, labelType: AxisLabelType.Left, gradientUnderPath: true, evaluator: self)
            max = defaultMax
            
            // Draw max speed line
            self.drawMaxValLineWithAxisLabels = true
        }
        
        public override func getMaximumValueInfo() -> (Date, Float) {
            return (rideLocalData.getMaxRpmDate() ?? Date.distantFuture, Float(rpmToMph(Double(rideLocalData.getMaxRpm())) / max))
        }
        
        func getValForRow(row: Row) -> Double {
            return rpmToMph(row[colIdxRpm])
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
        
        func getValForRow(row: Row) -> Double {
            return (row[colIdxBatt] as Double)
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))%"
        }
    }
    
    class BatteryVoltageSeries : ValueSeries, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, labelType: AxisLabelType.Right, gradientUnderPath: false, evaluator: self)
            max = 59.0
        }
        
        func getValForRow(row: Row) -> Double {
            return (row[colIdxBattVoltage] as Double) / 10.0
        }
        
        override func printAxisVal(val: Double) -> String {
            return String(format: "%.1fV", arguments: [val])
        }
    }
    
    class ErrorSeries : BooleanSeries, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, labelType: AxisLabelType.None, gradientUnderPath: false, evaluator: self)
            max = 1.0
        }
        
        func getValForRow(row: Row) -> Double {
            let foot1: Bool = row[colIdxFoot1]
            let foot2: Bool = row[colIdxFoot2]
            let rider: Bool = row[colIdxRider]
            let mph: Double = rpmToMph(row[colIdxRpm] as Double)
            return (mph > 1.0) && ((!foot1 && !foot2) || (!rider)) ? 1.0 : 0.0
        }
    }
}

protocol GraphDataSource {
    func getCount() -> Int
    func getCursor(start: Int, end: Int, stride: Int) -> RowCursor?
}

protocol SeriesEvaluator {
    func getValForRow(row: Row) -> Double
}
