//
//  AlertQueue.swift
//  OneWheel
//
//  Created by David Brodsky on 1/12/18.
//  Copyright © 2018 David Brodsky. All rights reserved.
//

import Foundation
import AVFoundation

class AlertQueue : NSObject, AVSpeechSynthesizerDelegate {
    
    private let serialQueue = DispatchQueue(label: "alertQueue")
    
    private var alerts = [Alert]()
    
    // Speech
    private var isSpeaking = false
    private let speechSynth = AVSpeechSynthesizer()
    private let speechVoice = AVSpeechSynthesisVoice(language: "en-US")
    
    override init() {
        super.init()
        self.speechSynth.delegate = self
    }
    
    func queueAlert(_ alert: Alert) {
        serialQueue.async {
            switch alert.priority {
            case .HIGH:
                let firstNonHighIdx = self.alerts.index(where: { (alert) -> Bool in
                    alert.priority != Alert.Priority.HIGH
                }) ?? self.alerts.endIndex
                NSLog("Inserting high alert at idx \(firstNonHighIdx)")
                self.alerts.insert(alert, at: firstNonHighIdx)
            case .LOW:
                self.alerts.append(alert)
                NSLog("Inserting low alert at idx \(self.alerts.endIndex)")
            }
            
            if !self.isSpeaking {
                NSLog("Playing next on queueAlert")
                self.playNext()
            }
        }
    }
    
    private func playNext() {
        serialQueue.async {
            if self.alerts.isEmpty {
                NSLog("Alert queue empty")
                self.isSpeaking = false
                try? AVAudioSession.sharedInstance().setActive(false)
            } else {
                let nextAlert = self.alerts.removeFirst()
                self.play(nextAlert)
            }
        }
    }
    
    private func play(_ alert: Alert) {
        try? AVAudioSession.sharedInstance().setActive(true)
        speechSynth.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: alert.message)
        utterance.voice = speechVoice
        speechSynth.speak(utterance)
    }
    
    // MARK: AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        NSLog("Playing next on speech complete: '\(utterance.speechString)'")
        playNext()
    }
    
    struct Alert {
        enum Priority {
            // Play after other high alerts
            case HIGH
            // Play after other high and low alerts
            case LOW
        }
        
        var priority: Priority
        var message: String
    }
}
