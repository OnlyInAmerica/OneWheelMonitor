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
    
    private var isAlerting = false
    private var lastAlert: Alert?
    
    func queueAlert(_ alert: Alert) {
        serialQueue.async {
            // First remove any other alerts with same key
            if let key = alert.key {
                self.alerts = self.alerts.filter({ (existingAlert) -> Bool in
                    existingAlert.key != key
                })
            }
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
                self.isAlerting = true  // Will be set false if alertNext -> isEmpty
                NSLog("Playing next on queueAlert")
                self.alertNext()
            }
        }
    }
    
    private func alertNext() {
        serialQueue.async {
            
            let onQueueEmpty = {
                NSLog("Alert queue empty")
                self.isAlerting = false
            }
            
            if self.alerts.isEmpty {
                onQueueEmpty()
            } else {
                // Skip duplicates of last alert
                let lastHash = (self.lastAlert?.hashValue() ?? -1)
                var nextAlert: Alert = self.alerts.removeFirst()
                while nextAlert.hashValue() == lastHash {
                    if !self.alerts.isEmpty {
                        nextAlert = self.alerts.removeFirst()
                    } else {
                        onQueueEmpty()
                        return
                    }
                }
                self.lastAlert = nextAlert
                self.play(nextAlert)
            }
        }
    }
    
    // Call from serialQueue
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
    // If the previous alert was of same key, this will be used. Default implementation returns message
    var shortMessage: String {get}
    // Only one alert per key should be present in the queue at once
    var key: String? {get}
    
    // Block until alert trigger complete
    func trigger(completion: (@escaping () -> ()))
}

extension Alert {
    func hashValue() -> Int {
        return self.priority.hashValue ^ (self.key?.hashValue ?? "?".hashValue) ^ self.message.hashValue &* 16777619
    }
}

extension Alert {
    var shortMessage: String {
        get {
            return message
        }
    }
}
