//
//  ViewController.swift
//  OneWheel
//
//  Created by David Brodsky on 12/30/17.
//  Copyright © 2017 David Brodsky. All rights reserved.
//

import UIKit
import GRDB

class StateViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, ConnectionListener {
    
    @IBOutlet weak var onewheelLabel: UILabel!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet var tableView: UITableView!
    
    var owConnectionDesired = true
    var owManager : OneWheelManager?

    private var controller: FetchedRecordsController<OneWheelState>!
    
    private let dateFormatter = DateFormatter()
    private let data = OneWheelLocalData()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        self.owManager?.connListener = self
        updateUi(isConnected: false, onewheel: nil)
        disconnectButton.addTarget(self, action: #selector(disconnectClick(_:)), for: .touchUpInside)

        self.tableView.delegate = self
        self.tableView.dataSource = self
        
        self.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        self.tableView.register(UINib(nibName: "StateTableViewCell", bundle: nil), forCellReuseIdentifier: "State")
        
        self.controller = try! owManager?.db?.getStateRecordsController()
            
        if let controller = self.controller {
            controller.trackChanges(
                willChange: { [unowned self] _ in
                    self.tableView.beginUpdates()
                },
                onChange: { [unowned self] (controller, record, change) in
                    switch change {
                    case .insertion(let indexPath):
                        self.tableView.insertRows(at: [indexPath], with: .fade)
                        
                    case .deletion(let indexPath):
                        self.tableView.deleteRows(at: [indexPath], with: .fade)
                        
                    case .update(let indexPath, _):
                        if let cell = self.tableView.cellForRow(at: indexPath) {
                            self.configure(cell as! StateTableViewCell, at: indexPath)
                        }
                        
                    case .move(let indexPath, let newIndexPath, _):
                        // Actually move cells around for more demo effect :-)
                        let cell = self.tableView.cellForRow(at: indexPath)
                        self.tableView.moveRow(at: indexPath, to: newIndexPath)
                        if let cell = cell {
                            self.configure(cell as! StateTableViewCell, at: newIndexPath)
                        }
                        
                        // A quieter animation:
                        // self.tableView.deleteRows(at: [indexPath], with: .fade)
                        // self.tableView.insertRows(at: [newIndexPath], with: .fade)
                    }
                },
                didChange: { [unowned self] _ in
                    self.tableView.endUpdates()
                    self.tableView.scrollToNearestSelectedRow(at: UITableViewScrollPosition.bottom, animated: true)
            })
            try! controller.performFetch()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @objc func disconnectClick(_ sender: UIButton) {
        NSLog("Click")
        owConnectionDesired = !owConnectionDesired
        if owConnectionDesired {
            self.disconnectButton.setTitle("Disconnect", for: UIControlState.normal)
            owManager?.start()
        } else {
            self.disconnectButton.setTitle("Connect", for: UIControlState.normal)
            owManager?.stop()
        }
    }
}

// MARK: - UITableViewDataSource
extension StateViewController {
    func configure(_ cell: StateTableViewCell, at indexPath: IndexPath) {
        let state = controller.record(at: indexPath)
        let prev = IndexPath(row: indexPath.row - 1, section: indexPath.section)
        if prev.row >= 0 {
            // Calculate delta
            let prevState = controller.record(at: prev)
            cell.titleLabel.text = state.describeDelta(prev: prevState)
            
        } else {
            cell.titleLabel.text = state.description
        }
        let stateTime = dateFormatter.string(from: state.time)
        cell.timeLabel.text = stateTime
    }
    
    // MARK UITableViewDelegate
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return controller.sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return controller.sections[section].numberOfRecords
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "State", for: indexPath)
        configure(cell as! StateTableViewCell, at: indexPath)
        return cell
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        // Delete the state
//        let state = controller.record(at: indexPath)
//        try! dbQueue.inDatabase { db in
//            _ = try state.delete(db)
//        }
    }
    
    func updateUi(isConnected: Bool, onewheel: OneWheel?) {
        if isConnected {
            self.onewheelLabel.text = onewheel?.name ?? "OneWheel"
        } else {
            self.onewheelLabel.text = "Searching for OneWheel..."
        }
    }
    
    // MARK: ConnectionListener
    func onConnected(oneWheel: OneWheel) {
        updateUi(isConnected: true, onewheel: oneWheel)
    }
    
    func onDisconnected(oneWheel: OneWheel) {
        updateUi(isConnected: false, onewheel: oneWheel)
    }
}
