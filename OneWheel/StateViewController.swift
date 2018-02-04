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
    
    @IBOutlet var graphView: OneWheelGraphView!
    @IBOutlet var connActionButton: UIBarButtonItem!
    @IBOutlet var newRideButton: UIBarButtonItem!
    @IBOutlet var muteAudioButton: UIBarButtonItem!
    @IBOutlet var unpairButton: UIBarButtonItem!
    
    var owManager : OneWheelManager!
    private var connectedOneWheel: OneWheel? = nil
    private var isConnected: Bool {
        get {
            return connectedOneWheel != nil
        }
    }

    private var controller: FetchedRecordsController<OneWheelState>?
    private var graphRefreshTimer: Timer?
    private let graphRefreshTimeInterval: TimeInterval = 1.0
    private var dbChanged = true

    private let dateFormatter = DateFormatter()
    private let userPrefs = OneWheelLocalData()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.graphView.dataSource = self
        //self.graphView.bgColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0).cgColor
        self.graphView.addSeries(newSeries: OneWheelGraphView.ErrorSeries(name: "Error", color: UIColor(red:0.99, green:0.07, blue:0.55, alpha:0.6).cgColor))
        self.graphView.addSeries(newSeries: OneWheelGraphView.SpeedSeries(name: "Speed", color: UIColor(red:0.89, green:0.89, blue:0.89, alpha:1.0).cgColor))
        self.graphView.addSeries(newSeries: OneWheelGraphView.BatterySeries(name: "Battery", color: UIColor(red:0.00, green:0.68, blue:0.94, alpha:1.0).cgColor))
//        self.graphView.addSeries(newSeries: OneWheelGraphView.MotorTempSeries(name: "MotorTemp", color: UIColor(red:1.00, green:0.52, blue:0.00, alpha:1.0).cgColor))
//        self.graphView.addSeries(newSeries: OneWheelGraphView.ControllerTempSeries(name: "ControllerTemp", color: UIColor(red:0.82, green:0.72, blue:0.47, alpha:1.0).cgColor))

        self.graphView.contentMode = .redraw // redraw on bounds change
        
        self.owManager.connListener = self
        self.owManager.db?.updateListener = self
        updateUi(isConnected: false, onewheel: nil)
        
        connActionButton.target = self
        connActionButton.action = #selector(connActionClick(_:))
        
        newRideButton.target = self
        newRideButton.action = #selector(newRideClick(_:))

        muteAudioButton.target = self
        muteAudioButton.action = #selector(muteAudioClick(_:))
        
        unpairButton.target = self
        unpairButton.action = #selector(unpairClick(_:))
        
        self.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        navigationController?.hidesBarsOnTap = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        subscribeToState(doSubscribe: true)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        subscribeToState(doSubscribe: false)
    }
    
    func subscribeToState(doSubscribe: Bool) {
        graphRefreshTimer?.invalidate()
        if doSubscribe {
            let isLandscape = self.view.bounds.width > self.view.bounds.height
            self.graphView.portraitMode = !isLandscape
            setupController(isLandscape: isLandscape)
            graphRefreshTimer = Timer.scheduledTimer(withTimeInterval: graphRefreshTimeInterval, repeats: true, block: { (timer) in
                let state = UIApplication.shared.applicationState
                if self.isConnected && state == .active && self.dbChanged {
                    self.refreshGraph()
                    self.dbChanged = false
                }
            })
        } else {
            self.controller = nil
            NSLog("Dereference controller")
        }
    }
    
    private func refreshGraph() {
        NSLog("Refresh graph")
        try! self.controller?.performFetch()
        self.graphView.setNeedsDisplay()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func setupController(isLandscape: Bool) {
        
        let completion: (FetchedRecordsController<OneWheelState>) -> () = { (controller) in
            self.controller = controller
            NSLog("Setup controller")
            self.refreshGraph()
        }
        
        if isLandscape {
            let newController = try! owManager.db!.getStateRecordsController()
            completion(newController)
        } else {
            try! owManager.db!.getRecentStateRecordsController(completion: completion)
        }
    }
    
    override func willRotate(to toInterfaceOrientation: UIInterfaceOrientation, duration: TimeInterval) {
        NSLog("willRotate to \(toInterfaceOrientation)")
        self.graphView.portraitMode = toInterfaceOrientation.isPortrait
        setupController(isLandscape: toInterfaceOrientation.isLandscape)
    }

    @objc func connActionClick(_ sender: UIButton) {
        let owConnectionDesired = !owManager.startRequested
        if owConnectionDesired {
            owManager?.start()
        } else {
            owManager?.stop()
        }
        // On button click we're about to disconnect or about to start searching
        updateUi(isConnected: false, onewheel: nil)
    }
    
    @objc func newRideClick(_ sender: UIButton) {
        let alert = UIAlertController(title: "Delete Previous Ride?", message: "Starting a new ride will delete data from the previous ride", preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { action in
            if action.style == .default {
                try? self.owManager.db?.clear()
                self.refreshGraph()
            }
            }))
        self.present(alert, animated: true, completion: nil)
    }
    
    @objc func muteAudioClick(_ sender: UIButton) {
        let audioEnabled = !userPrefs.getAudioAlertsEnabled()
        userPrefs.setAudioAlertsEnabled(audioEnabled)
        
        updateUi(isConnected: isConnected, onewheel: connectedOneWheel)
    }
    
    @objc func unpairClick(_ sender: UIButton) {
        let alert = UIAlertController(title: "Unpair OneWheel?", message: "The next time you click 'Connect', the first OneWheel found will become the paired device", preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { action in
            if action.style == .default {
                // Clear primary device selection and disconnect
                self.userPrefs.clearPrimaryDeviceUUID()
                self.owManager?.stop()
                self.updateUi(isConnected: false, onewheel: nil)
            }
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    func updateUi(isConnected: Bool, onewheel: OneWheel?) {
        if isConnected {
            self.navigationItem.title = "Connected to \(onewheel?.name ?? "OneWheel")"
            self.connActionButton.title = "Disconnect"
        } else if owManager.startRequested {
            self.navigationItem.title = "Searching for OneWheel..."
            self.connActionButton.title = "Stop"
        } else {
            self.navigationItem.title = ""
            self.connActionButton.title = "Connect"
        }
        
        let audioEnabled = userPrefs.getAudioAlertsEnabled()
        if audioEnabled {
            muteAudioButton.title = "Mute Audio"
        } else {
            muteAudioButton.title = "Unmute Audio"
        }
    }
}

// MARK: ConnectionListener
extension StateViewController: ConnectionListener {
    func onConnected(oneWheel: OneWheel) {
        connectedOneWheel = oneWheel
        updateUi(isConnected: true, onewheel: oneWheel)
    }
    
    func onDisconnected(oneWheel: OneWheel) {
        connectedOneWheel = nil
        updateUi(isConnected: false, onewheel: oneWheel)
    }
}

// MARK: GraphDataSource
extension StateViewController: GraphDataSource {
    func getCount() -> Int {
        let numItems = controller?.sections[0].numberOfRecords ?? 0
        NSLog("\(numItems) graph items")
        return numItems
    }
    
    func getStateForIndex(index: Int) -> OneWheelState {
        let state = controller!.record(at: IndexPath(row: index, section: 0))
        return state
    }
}

// MARK: Database UpdateListener
extension StateViewController: UpdateListener {
    func onChange() {
        dbChanged = true
    }
}

