//
//  DummyDronieApp.swift
//  DummyDronie
//
//  Created by Yeralin, Daniyar on 3/15/23.
//

import SwiftUI
import SwiftyBeaver
import Foundation
import DJISDK

let log = SwiftyBeaver.self

// Define QoSHelper directly in this file to avoid import issues
class QoSHelper {
    static let shared = QoSHelper()
    
    // Create dedicated queues for different operations
    let bluetoothQueue = DispatchQueue(label: "com.dummydronie.bluetooth", qos: .userInteractive)
    let networkQueue = DispatchQueue(label: "com.dummydronie.network", qos: .userInitiated)
    let fileIOQueue = DispatchQueue(label: "com.dummydronie.fileio", qos: .utility)
    let backgroundQueue = DispatchQueue(label: "com.dummydronie.background", qos: .background)
    
    private init() {
        configureQoSSettings()
    }
    
    private func configureQoSSettings() {
        // Configure CoreBluetooth settings
        UserDefaults.standard.set(true, forKey: "CBCentralManagerOptionRestoreIdentifierKey")
        
        log.info("QoS helper initialized with optimized settings")
    }
    
    /// Execute a Bluetooth operation on the proper high-priority queue
    func executeBluetoothOperation(_ operation: @escaping () -> Void) {
        bluetoothQueue.async {
            operation()
        }
    }
    
    /// Execute a network operation on the proper queue
    func executeNetworkOperation(_ operation: @escaping () -> Void) {
        networkQueue.async {
            operation()
        }
    }
    
    /// Execute a file I/O operation on the proper queue
    func executeFileIOOperation(_ operation: @escaping () -> Void) {
        fileIOQueue.async {
            operation()
        }
    }
    
    /// Execute a background operation on the proper queue
    func executeBackgroundOperation(_ operation: @escaping () -> Void) {
        backgroundQueue.async {
            operation()
        }
    }
}

// Define loading screen directly in this file to avoid scope issues
struct AppLoadingScreen: View {
    @State private var isLoading = true
    @State private var loadingText = "Initializing..."
    @State private var counter = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let loadingTexts = [
        "Initializing...",
        "Loading SDK...",
        "Preparing drone connection..."
    ]
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                Image(systemName: "airplane")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 2.0)
                            .repeatForever(autoreverses: false),
                        value: isLoading
                    )
                
                Text("DummyDronie")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                Text(loadingText)
                    .font(.body)
                    .foregroundColor(.gray)
                    .padding(.top, 10)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1.5)
                    .padding(.top, 30)
            }
        }
        .onAppear {
            isLoading = true
        }
        .onReceive(timer) { _ in
            counter += 1
            loadingText = loadingTexts[counter % loadingTexts.count]
        }
    }
}

@main
struct DummyDronieApp: App {
    
    @StateObject var djiConnector = DJIConnector()
    @State private var isInitialized = false
    
    // Initialize QoSHelper early to set up proper thread priorities
    private let qosHelper = QoSHelper.shared
    
    init() {
        // Configure logging immediately
        let console = ConsoleDestination()
        console.minLevel = .info
        log.addDestination(console)
        log.info("App initializing")
        
        // Set up thread priorities for better performance
        _ = qosHelper
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isInitialized {
                    MainView(djiConnector: djiConnector)
                        .onAppear {
                            UIApplication.shared.isIdleTimerDisabled = true
                        }
                } else {
                    // Use the inline AppLoadingScreen instead of LaunchScreen
                    AppLoadingScreen()
                        .onAppear {
                            // Use proper QoS for initialization
                            qosHelper.executeNetworkOperation {
                                // Delay SDK registration to improve launch performance
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    // Register SDK in background
                                    djiConnector.registerWithSDK()
                                    
                                    // Give UI time to initialize before showing main view
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation {
                                            isInitialized = true
                                        }
                                    }
                                }
                            }
                        }
                }
            }
        }
    }
}
