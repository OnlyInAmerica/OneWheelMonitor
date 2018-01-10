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

    private var controller: FetchedRecordsController<OneWheelState>?
    
    private let dateFormatter = DateFormatter()
    private let data = OneWheelLocalData()
    
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
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(sender:)))
        graphView.addGestureRecognizer(tapGesture)
    }
    
    func subscribeToState(doSubscribe: Bool) {
        if doSubscribe {
            setupController()
        } else {
            self.controller = nil
            NSLog("Dereference controller")
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func setupController() {
        self.controller = try! owManager.db?.getStateRecordsController()
        
        if let controller = self.controller {
            controller.trackChanges(
                didChange: { [unowned self] _ in
                    NSLog("Controller didChange")
                    let state = UIApplication.shared.applicationState
                    if state == .active {
                        self.graphView.setNeedsDisplay()
                    }
            })
            try! controller.performFetch()
            NSLog("Setup controller")
        }
    }
    
    @objc func handleTap(sender: UITapGestureRecognizer) {
        if let hidden = navigationController?.isNavigationBarHidden {
            navigationController?.setNavigationBarHidden(!hidden, animated: true)
            navigationController?.setToolbarHidden(!hidden, animated: true)
        }
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
            }
            }))
        self.present(alert, animated: true, completion: nil)
    }
    
    @objc func muteAudioClick(_ sender: UIButton) {
        let audioFeedbackDesired = !owManager.audioFeedback
        if audioFeedbackDesired {
            owManager.audioFeedback = true
            muteAudioButton.title = "Mute Audio"
        } else {
            owManager.audioFeedback = false
            muteAudioButton.title = "Unmute Audio"
        }
    }
    
    @objc func unpairClick(_ sender: UIButton) {
        let alert = UIAlertController(title: "Unpair OneWheel?", message: "The next time you click 'Connect', the first OneWheel found will become the paired device", preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { action in
            if action.style == .default {
                // Clear primary device selection and disconnect
                self.data.clearPrimaryDeviceUUID()
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
        let numItems = controller?.sections[0].numberOfRecords ?? 0
        NSLog("\(numItems) graph items")
        return numItems
    }
    
    func getStateForIndex(index: Int) -> OneWheelState {
        let state = controller!.record(at: IndexPath(row: index, section: 0))
        return state
    }
}
