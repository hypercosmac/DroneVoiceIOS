//
//  ContentView.swift
//  DummyDronie
//
//  Created by Yeralin, Daniyar on 3/15/23.
//

import SwiftUI
import DJISDK
import Speech
import AVFoundation

// Import the proper files by forward declaration if needed
// The compiler needs to know about these types

struct VoiceCommandButtonView: View {
    @ObservedObject var voiceCommandController: VoiceCommandController
    @State private var buttonScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(voiceCommandController.isListening ? Color.red.opacity(0.8) : Color.blue.opacity(0.8))
                .frame(width: 70, height: 70)
                .scaleEffect(buttonScale)
                .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 3)
            
            // Microphone icon
            Image(systemName: voiceCommandController.isListening ? "mic.fill" : "mic")
                .font(.system(size: 32))
                .foregroundColor(.white)
        }
        .padding(.bottom, 30)
        .padding(.leading, 30)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !voiceCommandController.isListening {
                        buttonScale = 1.3
                        voiceCommandController.startListening()
                    }
                }
                .onEnded { _ in
                    buttonScale = 1.0
                    voiceCommandController.stopListening()
                }
        )
        // Add double tap gesture for testing takeoff
        .onTapGesture(count: 2) {
            log.info("Double tap detected - executing takeoff")
            voiceCommandController.takeOff()
        }
        // Add triple tap gesture for testing landing
        .onTapGesture(count: 3) {
            log.info("Triple tap detected - executing landing")
            voiceCommandController.land()
        }
    }
}

// Add VoiceCommandController class inline to fix the dependency issue
class VoiceCommandController: NSObject, ObservableObject {
    
    // Speech recognizer and request objects
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Published properties for UI updates
    @Published var isListening = false
    @Published var recognizedText = ""
    
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
        
        // Get audio input node - no need for guard let since it's not optional
        let inputNode = audioEngine.inputNode
        
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
                log.info("Recognized text: \(self.recognizedText)")
                isFinal = result.isFinal
                
                // Check for recognized commands - directly execute without confirmation
                let normalizedText = result.bestTranscription.formattedString.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Check for "take off" command
                if normalizedText.contains("take off") || 
                   normalizedText.contains("takeoff") || 
                   normalizedText.contains("take-off") {
                    log.info("Take off command detected: '\(normalizedText)'")
                    
                    // Execute immediately without confirmation
                    DispatchQueue.main.async {
                        self.stopListening()
                        self.takeOff()
                    }
                }
                
                // Check for "land" command
                if normalizedText.contains("land") ||
                   normalizedText.contains("landing") {
                    log.info("Land command detected: '\(normalizedText)'")
                    
                    // Execute immediately without confirmation
                    DispatchQueue.main.async {
                        self.stopListening()
                        self.land()
                    }
                }
            }
            
            if error != nil || isFinal {
                // Stop audio engine
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                if let error = error {
                    log.error("Speech recognition error: \(error.localizedDescription)")
                }
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.isListening = false
                }
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
        
        // Clear engine and request - no need for if let since inputNode is not optional
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        log.info("Stopped listening for voice commands")
    }
    
    // Take off function using DJI SDK - public so it can be called directly
    func takeOff() {
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
    
    // Land function using DJI SDK - public so it can be called directly
    func land() {
        guard let aircraft = DJISDKManager.product() as? DJIAircraft else {
            log.error("Aircraft is not found")
            return
        }
        
        aircraft.flightController?.startLanding(completion: { (error) in
            if let error = error {
                log.error("Landing failed: \(error.localizedDescription)")
            } else {
                log.info("Land command sent successfully")
            }
        })
    }
}

struct MainView: View {
    
    @ObservedObject var djiConnector: DJIConnector
    @StateObject private var videoPreviewController = VideoPreviewController()
    @StateObject private var flightController = FlightController()
    @StateObject private var cameraController = CameraController()
    @State private var showSettings = false
    
    // Create voice command controller
    @StateObject private var voiceCommandController: VoiceCommandController
    
    init(djiConnector: DJIConnector) {
        self.djiConnector = djiConnector
        
        // We need to initialize flightController before voiceCommandController
        let tempFlightController = FlightController()
        _flightController = StateObject(wrappedValue: tempFlightController)
        
        // Then pass the flight controller to the voice command controller
        _voiceCommandController = StateObject(wrappedValue: VoiceCommandController(flightController: tempFlightController))
    }
    
    var body: some View {
        ZStack {
            // FPV Background View
            FPVView(djiConnector: djiConnector,
                    videoPreviewController: videoPreviewController)
                .edgesIgnoringSafeArea(.all)
            
            // Status Overlay (Battery, Altitude, Distance)
            VStack {
                HStack {
                    StatusView(flightController: flightController)
                        .padding(.top, 16)
                        .padding(.leading, 16)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                        .padding(8)
                    Spacer()
                }
                Spacer()
            }
            
            // Right Control Bar
            HStack {
                Spacer()
                ControlBarView(showSettings: $showSettings,
                               djiConnector: djiConnector,
                               flightController: flightController,
                               cameraController: cameraController)
                    .frame(width: 60)
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(8)
                    .padding(.trailing, 16)
            }
            
            // Voice Command Button (positioned at bottom left)
            VStack {
                Spacer()
                HStack {
                    VoiceCommandButtonView(voiceCommandController: voiceCommandController)
                    Spacer()
                }
            }
            
            // Full-width recognized text display
            VStack {
                if voiceCommandController.isListening {
                    Text(voiceCommandController.recognizedText)
                        .padding(12)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .medium))
                        .cornerRadius(10)
                        .padding(.horizontal, 20)
                        .padding(.top, 50)
                        .transition(.opacity)
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: voiceCommandController.isListening)
            
            // Virtual Joysticks Overlay (if needed)
            if djiConnector.isDroneConnected {
                VStack {
                    Spacer()
                    HStack {
                        // Left Virtual Joystick (Throttle/Yaw)
                        VirtualJoystickView(
                            onJoystickMoved: { (x, y) in
                                // Handle left joystick - throttle (y) and yaw (x)
                                flightController.sendVirtualStickCommands(
                                    throttle: Float(-y * 2.0), // Negative Y for up movement
                                    yaw: Float(x * 30.0),     // X for rotation
                                    pitch: 0,
                                    roll: 0
                                )
                            }
                        )
                        .frame(width: 120, height: 120)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(60)
                        .padding(.leading, 120)
                        
                        Spacer()
                        
                        // Right Virtual Joystick (Pitch/Roll)
                        VirtualJoystickView(
                            onJoystickMoved: { (x, y) in
                                // Handle right joystick - pitch (y) and roll (x)
                                flightController.sendVirtualStickCommands(
                                    throttle: 0,
                                    yaw: 0,
                                    pitch: Float(-y * 15.0),  // Negative Y for forward motion
                                    roll: Float(x * 15.0)     // X for lateral movement
                                )
                            }
                        )
                        .frame(width: 120, height: 120)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(60)
                        .padding(.trailing, 100)
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .ignoresSafeArea()
        .onReceive(djiConnector.$isDroneConnected) { isConnected in
            if isConnected {
                flightController.setupDelegates()
                cameraController.setupDelegates()
            }
        }
    }
}

struct VirtualJoystickView: View {
    @State private var position = CGPoint(x: 0, y: 0)
    @State private var isDragging = false
    var onJoystickMoved: (Double, Double) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * 0.4, height: geometry.size.height * 0.4)
                    .position(
                        x: geometry.size.width/2 + position.x,
                        y: geometry.size.height/2 + position.y
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let center = CGPoint(x: geometry.size.width/2, y: geometry.size.height/2)
                                let newPosition = CGPoint(
                                    x: value.location.x - center.x,
                                    y: value.location.y - center.y
                                )
                                
                                // Calculate distance from center
                                let distance = sqrt(newPosition.x * newPosition.x + newPosition.y * newPosition.y)
                                let maxDistance = min(geometry.size.width, geometry.size.height) / 2.5
                                
                                if distance <= maxDistance {
                                    position = newPosition
                                } else {
                                    // Normalize to max distance
                                    let scale = maxDistance / distance
                                    position = CGPoint(
                                        x: newPosition.x * scale,
                                        y: newPosition.y * scale
                                    )
                                }
                                
                                // Normalize x and y to -1.0...1.0 range
                                let normalizedX = Double(position.x / maxDistance)
                                let normalizedY = Double(position.y / maxDistance)
                                onJoystickMoved(normalizedX, normalizedY)
                                isDragging = true
                            }
                            .onEnded { _ in
                                // Reset position when drag ends
                                position = CGPoint(x: 0, y: 0)
                                onJoystickMoved(0, 0)
                                isDragging = false
                            }
                    )
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var djiConnector = DJIConnector()
    
    static var previews: some View {
        MainView(djiConnector: djiConnector)
    }
}

