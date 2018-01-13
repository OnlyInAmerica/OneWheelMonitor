//
//  AlertQueue.swift
//  OneWheel
//
//  Created by David Brodsky on 1/12/18.
//  Copyright © 2018 David Brodsky. All rights reserved.
//

import Foundation
import AVFoundation

class AlertQueue {
    
    private let serialQueue = DispatchQueue(label: "alertQueue")
    
    private var alerts = [Alert]()
    
    // Speech
    private var isAlerting = false
    
    func queueAlert(_ alert: Alert) {
        serialQueue.async {
            switch alert.priority {
            case .HIGH:
                let firstNonHighIdx = self.alerts.index(where: { (alert) -> Bool in
                    alert.priority != Priority.HIGH
                }) ?? self.alerts.endIndex
                NSLog("Inserting high alert at idx \(firstNonHighIdx)")
                self.alerts.insert(alert, at: firstNonHighIdx)
            case .LOW:
                self.alerts.append(alert)
                NSLog("Inserting low alert at idx \(self.alerts.endIndex)")
            }
            
            if !self.isAlerting {
                NSLog("Playing next on queueAlert")
                self.alertNext()
            }
        }
    }
    
    private func alertNext() {
        serialQueue.async {
            if self.alerts.isEmpty {
                NSLog("Alert queue empty")
                self.isAlerting = false
            } else {
                let nextAlert = self.alerts.removeFirst()
                self.play(nextAlert)
            }
        }
    }
    
    private func play(_ alert: Alert) {
        alert.trigger {
            self.alertNext()
        }
    }
}

enum Priority {
    // Play after other high alerts
    case HIGH
    // Play after other high and low alerts
    case LOW
}

protocol Alert {
    var priority: Priority {get}
    var message: String {get}
    
    // Block until alert trigger complete
    func trigger(completion: (@escaping () -> ()))
}
