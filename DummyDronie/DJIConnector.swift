//
//  DJIConnector.swift
//  DummyDronie
//
//  Created by Yeralin, Daniyar on 4/9/23.
//

import Foundation
import DJISDK

class DJIConnector: NSObject, DJISDKManagerDelegate, DJIAppActivationManagerDelegate, ObservableObject {
    
    @Published private(set) var isDroneConnected: Bool = false
    @Published private(set) var connectionStatus: String = "Not connected"
    
    private var connectionRetryCount = 0
    private let maxRetryCount = 3
    private var connectionTimer: Timer?
    private var retryTimer: Timer?
    private var isSDKRegistered = false
    
    // Add a dedicated queue for SDK operations with appropriate QoS
    private let sdkOperationQueue = DispatchQueue(label: "com.dummydronie.sdkoperations", qos: .userInitiated)
    
    // Custom timer properties to avoid CoreBluetooth priority inversions
    private var connectionCheckWorkItem: DispatchWorkItem?
    
    deinit {
        stopConnectionTimer()
    }
    
    func registerWithSDK() {
        // If already registered, don't register again
        guard !isSDKRegistered else {
            log.info("SDK already registered")
            return
        }
        
        let appKey = Bundle.main.object(forInfoDictionaryKey: SDK_APP_KEY_INFO_PLIST_KEY) as? String
        
        guard appKey != nil && appKey!.isEmpty == false else {
            log.error("Please enter your app key in the info.plist")
            updateConnectionStatus("Error: Missing app key")
            return
        }
        
        // Reset connection state
        connectionRetryCount = 0
        
        log.info("Trying to register DJI SDK manager with app key: \(appKey!)")
        updateConnectionStatus("Registering SDK...")
        
        // Use our dedicated queue with proper QoS instead of global queue
        sdkOperationQueue.async { [weak self] in
            // Safely unwrap self before passing to registerApp
            guard let strongSelf = self else {
                log.error("Self reference lost during SDK registration")
                return
            }
            DJISDKManager.registerApp(with: strongSelf)
        }
    }
    
    func didUpdateDatabaseDownloadProgress(_ progress: Progress) {
        let percentage = Float(progress.completedUnitCount) / Float(progress.totalUnitCount) * 100
        log.info("SDK is downloading DB file: \(percentage)%")
        updateConnectionStatus("Downloading database: \(Int(percentage))%")
    }
    
    func appRegisteredWithError(_ error: Error?) {
        if let error = error {
            log.error("SDK registered with an error: \(error.localizedDescription)")
            updateConnectionStatus("Registration error: \(error.localizedDescription)")
            return
        }
        
        log.info("Successfully registered the DJI SDK manager")
        updateConnectionStatus("Connecting to drone...")
        
        isSDKRegistered = true
        
        // Use our dedicated queue with proper QoS
        sdkOperationQueue.async {
            // Small delay to allow UI to initialize fully before connecting
            Thread.sleep(forTimeInterval: 0.5)
            DJISDKManager.startConnectionToProduct()
        }
        
        // Start a timer to check connection status
        startConnectionTimer()
    }
    
    func productConnected(_ product: DJIBaseProduct?) {
        guard let product = product else {
            log.error("DJI product is not found")
            updateConnectionStatus("Error: Product not found")
            isDroneConnected = false
            return
        }
        
        // Log product details for debugging
        log.info("Product connected: \(product)")
        
        // Access product model using string interpolation
        let modelString = String(describing: product.model)
        log.info("Product model: \(modelString)")
        
        if product.model == "Only RemoteController" {
            log.info("Connected to remote controller only")
            updateConnectionStatus("Connected to remote controller only")
            isDroneConnected = false
        } else {
            log.info("DJI product connected: \(product.model ?? "unknown")")
            updateConnectionStatus("Connected: \(product.model ?? "unknown")")
            isDroneConnected = true
            
            // Configure product behavior
            configureProductSettings()
        }
    }
    
    func productChanged(_ product: DJIBaseProduct?) {
        guard let product = product else {
            log.error("DJI product disconnected or not found")
            updateConnectionStatus("Error: Product disconnected")
            isDroneConnected = false
            return
        }
        
        if product.model == "Only RemoteController" {
            log.info("Changed to remote controller only")
            updateConnectionStatus("Connected to remote controller only")
            isDroneConnected = false
        } else {
            log.info("DJI product changed: \(product.model ?? "unknown")")
            updateConnectionStatus("Connected: \(product.model ?? "unknown")")
            isDroneConnected = true
        }
    }
    
    func productDisconnected() {
        log.info("DJI drone disconnected")
        updateConnectionStatus("Disconnected")
        isDroneConnected = false
    }
    
    // MARK: - Private Methods
    
    private func updateConnectionStatus(_ status: String) {
        DispatchQueue.main.async {
            self.connectionStatus = status
        }
    }
    
    private func startConnectionTimer() {
        stopConnectionTimer()
        
        // Create a new work item for connection checks
        let workItem = DispatchWorkItem { [weak self] in
            self?.checkConnectionStatus()
        }
        connectionCheckWorkItem = workItem
        
        // Schedule the work item on a high-priority queue
        sdkOperationQueue.asyncAfter(deadline: .now() + 5.0, execute: workItem)
        
        log.info("Started custom connection timer with proper QoS")
    }
    
    private func stopConnectionTimer() {
        // Cancel any existing connection timer
        connectionTimer?.invalidate()
        connectionTimer = nil
        
        // Cancel any existing work item
        connectionCheckWorkItem?.cancel()
        connectionCheckWorkItem = nil
    }
    
    private func checkConnectionStatus() {
        if !isDroneConnected {
            if let product = DJISDKManager.product() {
                log.info("Product found but not marked as connected: \(product.model ?? "unknown")")
                productConnected(product)
            } else {
                log.info("No product found, trying to reconnect...")
                // Try reconnection with proper QoS queue
                sdkOperationQueue.async {
                    DJISDKManager.startConnectionToProduct()
                }
            }
        }
        
        // Schedule next check - this replaces the Timer
        let workItem = DispatchWorkItem { [weak self] in
            self?.checkConnectionStatus()
        }
        connectionCheckWorkItem = workItem
        sdkOperationQueue.asyncAfter(deadline: .now() + 5.0, execute: workItem)
    }
    
    private func configureProductSettings() {
        // Configure optimal settings for the connected product
        sdkOperationQueue.async { [weak self] in
            // Small delay to allow app to finish launching before configuring settings
            Thread.sleep(forTimeInterval: 0.3)
            
            // Set up aircraft and camera settings
            if let aircraft = DJISDKManager.product() as? DJIAircraft {
                log.info("Configuring DJI aircraft settings")
                
                // Configure video feed settings
                if let camera = aircraft.camera {
                    log.info("Camera found - configuring camera settings")
                    
                    // Set camera mode
                    camera.setMode(.recordVideo, withCompletion: { error in
                        if let error = error {
                            log.error("Error setting camera mode: \(error.localizedDescription)")
                        } else {
                            log.info("Camera mode set to record video")
                        }
                    })
                } else {
                    log.warning("No camera found on the aircraft")
                }
                
                // Start the video feed if available
                if let videoFeeder = DJISDKManager.videoFeeder() {
                    log.info("Video feeder initialized and ready for use")
                } else {
                    log.warning("Video feeder is not available")
                }
                
                // Check flight controller status
                if let flightController = aircraft.flightController {
                    log.info("Flight controller found")
                } else {
                    log.warning("Flight controller not available")
                }
            } else {
                log.warning("Connected product is not an aircraft or could not be accessed")
            }
        }
    }
}
