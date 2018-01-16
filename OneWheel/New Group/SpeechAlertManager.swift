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
    
    func createSpeechAlert(priority: Priority, message: String, key: String? = nil) -> Alert {
        return SpeechAlert(speechManager: self, priority: priority, message: message)
    }
    
    class SpeechAlert: NSObject, Alert, AVSpeechSynthesizerDelegate {
        
        let speechAlertManager: SpeechAlertManager
        var priority: Priority
        var message: String
        var key: String?
        
        var completion: (() -> Void)?
        
        init(speechManager: SpeechAlertManager, priority: Priority, message: String) {
            self.speechAlertManager = speechManager
            self.priority = priority
            self.message = message
            
            try? AVAudioSession.sharedInstance().setCategory(
                AVAudioSessionCategoryPlayback,
                with:.mixWithOthers)
        }
        
        func trigger(completion: @escaping () -> Void) {
            try? AVAudioSession.sharedInstance().setActive(true)
            if speechAlertManager.speechSynth.isSpeaking {
                NSLog("Warning: Speech synthesizer was speaking when alert '\(message)' triggered")
            }
            speechAlertManager.speechSynth.stopSpeaking(at: .word)
            self.completion = completion
            speechAlertManager.speechSynth.delegate = self
            let utterance = AVSpeechUtterance(string: message)
            utterance.rate = 0.55
            utterance.voice = speechAlertManager.speechVoice
            speechAlertManager.speechSynth.speak(utterance)
        }
        
        // MARK: AVSpeechSynthesizerDelegate
        
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            try? AVAudioSession.sharedInstance().setActive(false)
            NSLog("Playing next on speech complete: '\(utterance.speechString)'")
            if let completion = self.completion {
                completion()
            } else {
                NSLog("Warning: No completion callback on speech complete")
            }
        }
    }
}
