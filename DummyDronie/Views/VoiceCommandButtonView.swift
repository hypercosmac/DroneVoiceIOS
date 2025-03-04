//
//  VoiceCommandButtonView.swift
//  DummyDronie
//
//  Created by AI Assistant on 5/15/23.
//

import SwiftUI

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
        .overlay(
            // Recognized text display
            Text(voiceCommandController.recognizedText)
                .padding(8)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(8)
                .opacity(voiceCommandController.isListening ? 1 : 0)
                .frame(width: 200, alignment: .center)
                .offset(y: -80)
        )
        // Command confirmation alert
        .alert(isPresented: $voiceCommandController.showConfirmation) {
            Alert(
                title: Text("Confirm Command"),
                message: Text("Do you want to execute 'Take Off'?"),
                primaryButton: .destructive(Text("Yes")) {
                    voiceCommandController.executeCommand()
                },
                secondaryButton: .cancel() {
                    voiceCommandController.cancelCommand()
                }
            )
        }
    }
} 