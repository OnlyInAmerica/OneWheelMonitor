//
//  ViewController.swift
//  OneWheel
//
//  Created by David Brodsky on 12/30/17.
//  Copyright © 2017 David Brodsky. All rights reserved.
//

import UIKit
import GRDB

class StateViewController: UIViewController {
    
    @IBOutlet weak var onewheelLabel: UILabel!
    @IBOutlet weak var connStatusLabel: UIButton!
    @IBOutlet var graphView: OneWheelGraphView!
    
    var owManager : OneWheelManager!

    private var controller: FetchedRecordsController<OneWheelState>!
    
    private let dateFormatter = DateFormatter()
    private let data = OneWheelLocalData()
    
    private var graphNeedsDisplay = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        self.graphView.dataSource = self
        self.graphView.addSeries(newSeries: OneWheelGraphView.SpeedSeries(name: "Speed", color: UIColor(red: 0.29, green: 0.29, blue: 0.29, alpha: 1.0)
            .cgColor))
        self.graphView.addSeries(newSeries: OneWheelGraphView.BatterySeries(name: "Battery", color: UIColor(red: 0.37, green: 0.47, blue: 0.66, alpha: 1.0)
.cgColor))
        self.graphView.addSeries(newSeries: OneWheelGraphView.ErrorSeries(name: "Error", color: UIColor(red: 0.89, green: 0.13, blue: 0.13, alpha: 0.1)
            .cgColor))
        self.graphView.contentMode = .redraw // redraw on bounds change
        
        self.owManager.connListener = self
        updateUi(isConnected: false, onewheel: nil)
        connStatusLabel.addTarget(self, action: #selector(disconnectClick(_:)), for: .touchUpInside)
        
        self.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        self.controller = try! owManager.db?.getStateRecordsController()
            
        if let controller = self.controller {
            controller.trackChanges(
                didChange: { [unowned self] _ in
                    let state = UIApplication.shared.applicationState
                    if state == .active {
                        self.graphView.setNeedsDisplay()
                    } else {
                        self.graphNeedsDisplay = true
                    }
            })
            try! controller.performFetch()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if graphNeedsDisplay {
            self.graphView.setNeedsDisplay()
            graphNeedsDisplay = false
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @objc func disconnectClick(_ sender: UIButton) {
        let owConnectionDesired = !owManager.startRequested
        if owConnectionDesired {
            owManager?.start()
        } else {
            owManager?.stop()
        }
        // On button click we're about to disconnect or about to start searching
        updateUi(isConnected: false, onewheel: nil)
    }
    
    func updateUi(isConnected: Bool, onewheel: OneWheel?) {
        if isConnected {
            self.onewheelLabel.text = onewheel?.name ?? "OneWheel"
            self.connStatusLabel.setTitle("Disconnect", for: UIControlState.normal)
        } else if owManager.startRequested {
            self.onewheelLabel.text = "Searching for OneWheel..."
            self.connStatusLabel.setTitle("Stop", for: UIControlState.normal)
        } else {
            self.onewheelLabel.text = ""
            self.connStatusLabel.setTitle("Connect", for: UIControlState.normal)
        }
    }
}

// MARK: ConnectionListener
extension StateViewController: ConnectionListener {
    func onConnected(oneWheel: OneWheel) {
        updateUi(isConnected: true, onewheel: oneWheel)
    }
    
    func onDisconnected(oneWheel: OneWheel) {
        updateUi(isConnected: false, onewheel: oneWheel)
    }
}

// MARK: GraphDataSource
extension StateViewController: GraphDataSource {
    func getCount() -> Int {
        let numItems = controller.sections[0].numberOfRecords
        NSLog("\(numItems) graph items")
        return numItems
    }
    
    func getStateForIndex(index: Int) -> OneWheelState {
        let state = controller.record(at: IndexPath(row: index, section: 0))
        return state
    }
}
