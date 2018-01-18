//
//  SpeechAlertManager.swift
//  OneWheel
//
//  Created by David Brodsky on 1/13/18.
//  Copyright © 2018 David Brodsky. All rights reserved.
//

import Foundation
import AVFoundation

class SpeechAlertManager {
    
    // Speech
    private let speechSynth = AVSpeechSynthesizer()
    private let speechVoice = AVSpeechSynthesisVoice(language: "en-US")
    
    func createSpeechAlert(priority: Priority, message: String, key: String? = nil, shortMessage: String? = nil) -> Alert {
        return SpeechAlert(speechManager: self, priority: priority, message: message, key: key, shortMessage: shortMessage)
    }
    
    class SpeechAlert: NSObject, Alert, AVSpeechSynthesizerDelegate {
        let speechAlertManager: SpeechAlertManager
        var priority: Priority
        var message: String
        var shortMessage: String
        var key: String?
        
        var completion: (() -> Void)?
        
        init(speechManager: SpeechAlertManager, priority: Priority, message: String, key: String? = nil, shortMessage: String? = nil) {
            self.speechAlertManager = speechManager
            self.priority = priority
            self.message = message
            self.key = key
            self.shortMessage = (shortMessage != nil) ? shortMessage! : message
            
            try? AVAudioSession.sharedInstance().setCategory(
                AVAudioSessionCategoryPlayback,
                with:.mixWithOthers)
        }
        
        func trigger(useShortMessage: Bool, completion: @escaping () -> Void) {
            try? AVAudioSession.sharedInstance().setActive(true)
            let toSpeak = (useShortMessage) ? shortMessage : message
            if speechAlertManager.speechSynth.isSpeaking {
                NSLog("Warning: Speech synthesizer was speaking when alert '\(toSpeak)' triggered")
            }
            NSLog("Speaking '\(toSpeak)'. key \(key ?? "None") Priority \(priority)")
            speechAlertManager.speechSynth.stopSpeaking(at: .word)
            self.completion = completion
            speechAlertManager.speechSynth.delegate = self
            let utterance = AVSpeechUtterance(string: toSpeak)
            utterance.rate = 0.55
            utterance.voice = speechAlertManager.speechVoice
            speechAlertManager.speechSynth.speak(utterance)
        }
        
        // MARK: AVSpeechSynthesizerDelegate
        
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            try? AVAudioSession.sharedInstance().setActive(false)
            if let completion = self.completion {
                completion()
            } else {
                NSLog("Warning: No completion callback on speech complete")
            }
        }
    }
}
