//
//  VoiceCommandController.swift
//  DummyDronie
//
//  Created by AI Assistant on 5/15/23.
//

import Foundation
import Speech
import SwiftUI
import DJISDK

class VoiceCommandController: NSObject, ObservableObject {
    
    // Speech recognizer and request objects
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Published properties for UI updates
    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var showConfirmation = false
    @Published var commandToConfirm = ""
    
    // Reference to FlightController
    private var flightController: FlightController
    
    // Initialize with flight controller
    init(flightController: FlightController) {
        self.flightController = flightController
        super.init()
        
        // Check for authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    log.info("Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    log.error("Speech recognition not authorized: \(authStatus)")
                @unknown default:
                    log.error("Unknown speech recognition auth status")
                }
            }
        }
    }
    
    // Start listening for voice commands
    func startListening() {
        // Cancel any ongoing task
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            log.error("Failed to set up audio session: \(error.localizedDescription)")
            return
        }
        
        // Set up recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        // Check for audio input
        guard let inputNode = audioEngine.inputNode else {
            log.error("Audio engine has no input node")
            return
        }
        
        guard let recognitionRequest = recognitionRequest else {
            log.error("Recognition request object is nil")
            return
        }
        
        // Enable partial results
        recognitionRequest.shouldReportPartialResults = true
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                // Update recognized text
                self.recognizedText = result.bestTranscription.formattedString
                isFinal = result.isFinal
                
                // Check for "take off" command
                if result.bestTranscription.formattedString.lowercased().contains("take off") {
                    log.info("Take off command detected")
                    self.commandToConfirm = "takeoff"
                    self.showConfirmation = true
                    self.stopListening()
                }
            }
            
            if error != nil || isFinal {
                // Stop audio engine
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self.isListening = false
            }
        }
        
        // Set up audio tap
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            log.info("Started listening for voice commands")
        } catch {
            log.error("Failed to start audio engine: \(error.localizedDescription)")
        }
    }
    
    // Stop listening
    func stopListening() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        // Clear engine and request
        if let inputNode = audioEngine.inputNode {
            inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        log.info("Stopped listening for voice commands")
    }
    
    // Execute confirmed command
    func executeCommand() {
        switch commandToConfirm {
        case "takeoff":
            log.info("Executing take off command")
            takeOff()
        default:
            log.error("Unknown command: \(commandToConfirm)")
        }
        
        // Reset confirmation state
        showConfirmation = false
        commandToConfirm = ""
    }
    
    // Cancel command
    func cancelCommand() {
        showConfirmation = false
        commandToConfirm = ""
        log.info("Command cancelled")
    }
    
    // Take off function using DJI SDK
    private func takeOff() {
        guard let aircraft = DJISDKManager.product() as? DJIAircraft else {
            log.error("Aircraft is not found")
            return
        }
        
        aircraft.flightController?.startTakeoff(completion: { (error) in
            if let error = error {
                log.error("Take off failed: \(error.localizedDescription)")
            } else {
                log.info("Take off command sent successfully")
            }
        })
    }
} 