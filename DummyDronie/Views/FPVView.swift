//
//  FPVView.swift
//  DummyDronie
//
//  Created by Yeralin, Daniyar on 4/9/23.
//

import SwiftUI

/// FPVView is a UIViewRepresentable that displays the First Person View (FPV) from the DJI drone's camera.
struct FPVView: UIViewRepresentable {

    @ObservedObject var djiConnector: DJIConnector
    @ObservedObject var videoPreviewController: VideoPreviewController
    
    /// Creates the UIView for the FPV preview.
    func makeUIView(context: Context) -> UIView {
        // Container view
        let containerView = UIView(frame: UIScreen.main.bounds)
        containerView.backgroundColor = UIColor.darkGray
        containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.contentMode = .scaleToFill
        
        // Create a tag for the container to identify it
        containerView.tag = 100
        
        // Add a connecting label
        let label = UILabel()
        label.text = "Connecting to drone..."
        label.textAlignment = .center
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.tag = 101
        
        containerView.addSubview(label)
        
        // Center the label
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        
        return containerView
    }

    /// Updates the FPV preview by setting up the video preview if the drone is connected.
    func updateUIView(_ uiView: UIView, context: Context) {
        // Set the frame to full screen size
        uiView.frame = UIScreen.main.bounds
        
        // Update connection status label
        if let label = uiView.viewWithTag(101) as? UILabel {
            if djiConnector.isDroneConnected {
                label.isHidden = true
            } else {
                label.isHidden = false
                label.text = djiConnector.connectionStatus
            }
        }
        
        // If we're connected but video preview isn't set up yet, set it up
        if djiConnector.isDroneConnected && !videoPreviewController.isViewPreviewSetup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                videoPreviewController.setupVideoPreviewer(fpvPreview: uiView)
            }
        }
        
        // If we're disconnected but video preview is set up, reset it
        if !djiConnector.isDroneConnected && videoPreviewController.isViewPreviewSetup {
            videoPreviewController.resetVideoPreviewer()
        }
    }

    /// Handles the teardown of the video preview when the FPVView is dismantled.
    func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        videoPreviewController.resetVideoPreviewer()
    }
}

/// A SwiftUI view that displays connection status
struct ConnectionStatusView: View {
    @ObservedObject var djiConnector: DJIConnector
    @ObservedObject var videoPreviewController: VideoPreviewController
    
    var body: some View {
        VStack {
            HStack {
                // Connection status indicator
                HStack {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 10, height: 10)
                    
                    Text(djiConnector.connectionStatus)
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                
                Spacer()
                
                // Model status if relevant
                if !videoPreviewController.modelStatus.isEmpty && videoPreviewController.modelStatus != "YOLO model loaded successfully" {
                    Text(videoPreviewController.modelStatus)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                }
            }
            .padding([.top, .leading, .trailing], 16)
            
            Spacer()
        }
    }
    
    // Color based on connection status
    private var connectionColor: Color {
        if djiConnector.isDroneConnected {
            return .green
        } else if djiConnector.connectionStatus.contains("Connecting") {
            return .yellow
        } else if djiConnector.connectionStatus.contains("Error") {
            return .red
        } else {
            return .gray
        }
    }
}

/// A SwiftUI view that displays detected objects
struct DetectedObjectsView: View {
    @ObservedObject var videoPreviewController: VideoPreviewController
    
    var body: some View {
        ZStack(alignment: .top) {
            // Detection status indicator
            HStack {
                Spacer()
                Button(action: {
                    videoPreviewController.toggleObjectDetection()
                }) {
                    HStack {
                        Image(systemName: videoPreviewController.isObjectDetectionEnabled ? "eye" : "eye.slash")
                            .foregroundColor(videoPreviewController.isObjectDetectionEnabled ? .green : .red)
                        
                        Text(videoPreviewController.isObjectDetectionEnabled ? "Object Detection: ON" : "Object Detection: OFF")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                }
                .padding([.top, .trailing], 16)
            }
            
            // Display detected object count
            if videoPreviewController.isObjectDetectionEnabled && !videoPreviewController.detectedObjects.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Text("Detected: \(videoPreviewController.detectedObjects.count) objects")
                            .font(.caption)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        
                        Spacer()
                    }
                    .padding([.bottom, .leading], 16)
                }
            }
            
            // Performance metrics (optional, can be removed if not needed)
            if videoPreviewController.isObjectDetectionEnabled {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "FPS: %.1f", videoPreviewController.frameRate))
                                .font(.caption2)
                            Text(String(format: "Process: %.0f ms", videoPreviewController.processingTime * 1000))
                                .font(.caption2)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding([.bottom, .trailing], 16)
                }
            }
        }
    }
}
