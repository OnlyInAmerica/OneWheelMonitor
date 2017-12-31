//
//  ViewController.swift
//  OneWheel
//
//  Created by David Brodsky on 12/30/17.
//  Copyright © 2017 David Brodsky. All rights reserved.
//

import UIKit
import GRDB

class StateViewController: UITableViewController {
    
    var db : OneWheelDatabase?
    
    private var controller: FetchedRecordsController<OneWheelState>!
    
    private let dateFormatter = DateFormatter()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        self.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        self.tableView.register(UINib(nibName: "StateTableViewCell", bundle: nil), forCellReuseIdentifier: "State")
        
        self.controller = try! db?.getStateRecordsController()
            
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
            })
            try! controller.performFetch()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
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
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return controller.sections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return controller.sections[section].numberOfRecords
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "State", for: indexPath)
        configure(cell as! StateTableViewCell, at: indexPath)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        // Delete the state
//        let state = controller.record(at: indexPath)
//        try! dbQueue.inDatabase { db in
//            _ = try state.delete(db)
//        }
    }
}
