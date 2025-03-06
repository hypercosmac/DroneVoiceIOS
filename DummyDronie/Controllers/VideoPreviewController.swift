//
//  DroneController.swift
//  DummyDronie
//
//  Created by Yeralin, Daniyar on 4/8/23.
//

import Foundation
import UIKit
import DJISDK

/// VideoPreviewController handles the video preview setup and teardown for DJI drone's camera feed.
class VideoPreviewController: NSObject, DJIVideoFeedListener, ObservableObject {
    
    /// A boolean property to indicate if the view preview is set up.
    var isViewPreviewSetup: Bool = false
    
    /// WebSocket connection for streaming video to AI model
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    
    /// AI model response data
    @Published var aiDecisions: [String: Any] = [:]
    @Published var isConnectedToAI: Bool = false
    
    /// WebSocket server URL
    private var serverURL: URL?
    
    /// Connect to AI model WebSocket server
    /// - Parameter urlString: The WebSocket server URL as a string
    func connectToAIServer(urlString: String) {
        guard let url = URL(string: urlString) else {
            log.error("Invalid WebSocket URL: \(urlString)")
            return
        }
        
        serverURL = url
        setupWebSocketConnection()
    }
    
    /// Sets up the WebSocket connection to the AI server
    private func setupWebSocketConnection() {
        guard let url = serverURL else {
            log.error("Server URL not set")
            return
        }
        
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        log.info("WebSocket connection established to \(url.absoluteString)")
        isConnectedToAI = true
        
        // Start receiving messages
        receiveMessage()
    }
    
    /// Receives messages from the WebSocket server
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self?.handleAIResponse(data: data)
                case .string(let string):
                    if let data = string.data(using: .utf8) {
                        self?.handleAIResponse(data: data)
                    }
                @unknown default:
                    log.error("Unknown message type received")
                }
                
                // Continue receiving messages
                self?.receiveMessage()
                
            case .failure(let error):
                log.error("WebSocket receive error: \(error)")
                self?.isConnectedToAI = false
                
                // Try to reconnect after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.setupWebSocketConnection()
                }
            }
        }
    }
    
    /// Handles AI model response data
    /// - Parameter data: The response data from the AI model
    private func handleAIResponse(data: Data) {
        do {
            if let jsonDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                DispatchQueue.main.async {
                    self.aiDecisions = jsonDict
                }
            }
        } catch {
            log.error("Failed to parse AI response: \(error)")
        }
    }
    
    /// Disconnects from the WebSocket server
    func disconnectFromAIServer() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnectedToAI = false
        log.info("Disconnected from AI server")
    }
    
    /// Sets up the video previewer for the DJI drone's camera feed.
    /// - Parameter fpvPreview: The UIView to display the video preview.
    func setupVideoPreviewer(fpvPreview: UIView) {
        guard let videoPreviewer = DJIVideoPreviewer.instance() else {
            log.error("Could not fetch DJIVideoPreviewer instance")
            return
        }
        guard let videoFeeder = DJISDKManager.videoFeeder() else {
            log.error("Could not fetch the video feeder instance")
            return
        }
        videoPreviewer.setView(fpvPreview)
        videoFeeder.primaryVideoFeed.add(self, with: nil)
        videoPreviewer.start()
        log.info("Setup video previewer")
        isViewPreviewSetup = true
    }
    
    /// Resets the video previewer and removes it from the DJI drone's camera feed.
    func resetVideoPreviewer() {
        guard let videoPreviewer = DJIVideoPreviewer.instance() else {
            log.error("Could not fetch DJIVideoPreviewer instance")
            return
        }
        guard let videoFeeder = DJISDKManager.videoFeeder() else {
            log.error("Could not fetch the video feeder instance")
            return
        }
        videoFeeder.primaryVideoFeed.remove(self)
        videoPreviewer.unSetView()
        log.info("Reset video previewer")
        isViewPreviewSetup = false
    }
    
    /// Processes the updated video data from the DJI drone's camera feed.
    @objc func videoFeed(_ videoFeed: DJIVideoFeed, didUpdateVideoData videoData: Data) {
        // Update local video previewer
        guard let videoPreviewer = DJIVideoPreviewer.instance() else {
            log.error("Could not fetch DJIVideoPreviewer instance")
            return
        }
        let nsVideoData = videoData as NSData
        let videoBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: nsVideoData.length)
        nsVideoData.getBytes(videoBuffer, length: nsVideoData.length)
        videoPreviewer.push(videoBuffer, length: Int32(nsVideoData.length))
        
        // Stream video data to WebSocket if connected
        if isConnectedToAI, let webSocketTask = webSocketTask {
            // Prepare message with video frame and metadata
            let message = prepareVideoMessage(videoData: videoData)
            
            // Send the message over WebSocket
            webSocketTask.send(message) { [weak self] error in
                if let error = error {
                    log.error("Failed to send video data: \(error)")
                    self?.isConnectedToAI = false
                    
                    // Try to reconnect after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self?.setupWebSocketConnection()
                    }
                }
            }
        }
    }
    
    /// Prepares video message for WebSocket transmission
    /// - Parameter videoData: The raw video data from the drone
    /// - Returns: WebSocket message
    private func prepareVideoMessage(videoData: Data) -> URLSessionWebSocketTask.Message {
        // For efficient binary transfer, send raw data
        // Add metadata if needed in a production app
        return .data(videoData)
        
        // Alternative: You could convert the frame to a Base64 string and send as JSON
        // let base64Video = videoData.base64EncodedString()
        // let jsonDict: [String: Any] = ["type": "video_frame", "data": base64Video, "timestamp": Date().timeIntervalSince1970]
        // if let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict) {
        //     return .data(jsonData)
        // }
        // return .string("{\"error\": \"Failed to encode video data\"}")
    }
    
    /// Deinitializer to clean up resources
    deinit {
        disconnectFromAIServer()
    }
}
