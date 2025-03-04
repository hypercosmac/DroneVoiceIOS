//
//  ControlBarView.swift
//  DummyDronie
//
//  Created by Yeralin, Daniyar on 4/9/23.
//

import SwiftUI

struct ControlBarView: View {
    
    @State private var countdownDuration = Settings.loadSetting(.countdownDurationKey)
    @Binding var showSettings: Bool
    
    @State private var countdown: Double = 0
    
    @ObservedObject var djiConnector: DJIConnector
    @ObservedObject var flightController: FlightController
    @ObservedObject var cameraController: CameraController
    
    var body: some View {
        VStack {
            // Settings Button
            NavigationLink(destination: SettingsView(), isActive: $showSettings) {
                Button(action: {
                    showSettings.toggle()
                }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.blue)
                        .font(.system(size: 24))
                        .padding(.top, 20)
                }
            }
            
            Spacer()
            
            // Record Button
            Button(action: {
                if !cameraController.isRecording {
                    startCountdown {
                        cameraController.startVideoRecording()
                        flightController.startVerticalTakeoff()
                    }
                } else {
                    flightController.stopVerticalTakeoff()
                    cameraController.stopVideoRecording()
                }
            }) {
                if countdown > 0 {
                    Text("\(Int(countdown))")
                        .font(.system(size: 36))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Circle())
                } else {
                    Image(systemName: cameraController.isRecording ? "record.circle.fill" : "record.circle")
                        .foregroundColor(cameraController.isRecording ? .red : .blue)
                        .font(.system(size: 46))
                        .frame(width: 50, height: 50)
                }
            }
            .disabled(countdown > 0 || !djiConnector.isDroneConnected)
            .onChange(of: flightController.verticalTakeoffJob?.isValid) { isValid in
                // If the job is invalid, stop recording
                if !(isValid ?? false) {
                    cameraController.stopVideoRecording()
                }
            }
            
            Spacer()
            
            // Connection Status
            VStack {
                Image(systemName: djiConnector.isDroneConnected ? "wifi" : "wifi.slash")
                    .foregroundColor(djiConnector.isDroneConnected ? .green : .red)
                    .font(.system(size: 24))
                
                Text(djiConnector.isDroneConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundColor(djiConnector.isDroneConnected ? .green : .red)
            }
            .padding(.bottom, 20)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }
    
    private func startCountdown(completion: @escaping () -> Void) {
        countdown = countdownDuration
        guard countdown > 0 else {
            completion()
            return
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            countdown -= 1
            if countdown <= 0 {
                timer.invalidate()
                completion()
            }
        }
    }
}
