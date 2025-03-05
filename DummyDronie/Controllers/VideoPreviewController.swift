//
//  DroneController.swift
//  DummyDronie
//
//  Created by Yeralin, Daniyar on 4/8/23.
//

import Foundation
import UIKit
import DJISDK
import AVFoundation
import Vision
import CoreImage
import Combine

/// Represents a detected object
struct Detection: Identifiable {
    let id = UUID()
    let box: CGRect
    let confidence: Float
    let label: String
    let color: UIColor
}

/// Connection status enum to provide UI feedback
enum DroneConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting to drone..."
        case .connected:
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    static func == (lhs: DroneConnectionStatus, rhs: DroneConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected):
            return true
        case (.connecting, .connecting):
            return true
        case (.connected, .connected):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

/// Frame source options for the detection pipeline
enum FrameSource {
    case screenshot
    case directSDK
    case avCapture
}

/// YOLODetectionController handles the object detection using YOLOv8 model.
class YOLODetectionController: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    /// Published properties for UI updates
    @Published var detectedObjects: [Detection] = []
    @Published var isDetectionActive: Bool = true
    @Published var processingTime: TimeInterval = 0
    @Published var modelAvailable: Bool = false
    
    // Colors for different object classes
    private let colors: [UIColor] = {
        var colorSet: [UIColor] = []
        for _ in 0...80 {
            let color = UIColor(
                red: CGFloat.random(in: 0...1),
                green: CGFloat.random(in: 0...1),
                blue: CGFloat.random(in: 0...1),
                alpha: 1
            )
            colorSet.append(color)
        }
        return colorSet
    }()
    
    // Core ML request for YOLO inference
    private lazy var yoloRequest: VNCoreMLRequest? = {
        do {
            // Load the YOLO model - trying multiple locations
            var modelURL: URL?
            
            // Location 1: Main bundle
            if let bundleURL = Bundle.main.url(forResource: "yolov8s", withExtension: "mlmodel") {
                log.info("Found YOLO model in main bundle")
                modelURL = bundleURL
            } 
            // Location 2: Resources directory
            else if let resourcesPath = Bundle.main.resourcePath {
                let resourcesURL = URL(fileURLWithPath: resourcesPath).appendingPathComponent("Resources")
                let potentialURL = resourcesURL.appendingPathComponent("yolov8s.mlmodel")
                
                if FileManager.default.fileExists(atPath: potentialURL.path) {
                    log.info("Found YOLO model in Resources directory: \(potentialURL.path)")
                    modelURL = potentialURL
                } else {
                    log.error("YOLO model not found in Resources: \(potentialURL.path)")
                }
            }
            
            // Location 3: Project directory YOLO folder
            if modelURL == nil {
                let projectDir = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent()
                let yoloDir = projectDir.appendingPathComponent("YOLO")
                let potentialURL = yoloDir.appendingPathComponent("yolov8s.mlmodel")
                
                if FileManager.default.fileExists(atPath: potentialURL.path) {
                    log.info("Found YOLO model in YOLO directory: \(potentialURL.path)")
                    modelURL = potentialURL
                } else {
                    log.error("YOLO model not found in YOLO directory: \(potentialURL.path)")
                }
            }
            
            // Try to find the model in some common locations
            let fileManager = FileManager.default
            let homeDirectory = NSHomeDirectory()
            let possibleLocations = [
                "\(homeDirectory)/Documents/yolov8s.mlmodel",
                "\(homeDirectory)/Downloads/yolov8s.mlmodel",
                Bundle.main.bundlePath + "/../yolov8s.mlmodel",
                Bundle.main.bundlePath + "/../YOLO/yolov8s.mlmodel",
                Bundle.main.bundlePath + "/../Resources/yolov8s.mlmodel"
            ]
            
            for location in possibleLocations {
                if fileManager.fileExists(atPath: location) {
                    log.info("Found YOLO model at: \(location)")
                    modelURL = URL(fileURLWithPath: location)
                    break
                }
            }
            
            // If still not found, use FileManager to search in the Documents directory
            if modelURL == nil {
                do {
                    let documentsURL = try fileManager.url(
                        for: .documentDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: false
                    )
                    
                    if let enumerator = fileManager.enumerator(at: documentsURL, includingPropertiesForKeys: nil) {
                        while let url = enumerator.nextObject() as? URL {
                            if url.lastPathComponent == "yolov8s.mlmodel" {
                                log.info("Found YOLO model at: \(url.path)")
                                modelURL = url
                                break
                            }
                        }
                    }
                } catch {
                    log.error("Error searching Documents directory: \(error.localizedDescription)")
                }
            }
            
            guard let modelURL = modelURL else {
                log.error("YOLO model file 'yolov8s.mlmodel' not found in any location")
                // Update UI on main thread to show error
                DispatchQueue.main.async { [weak self] in
                    self?.isDetectionActive = false
                }
                return nil
            }
            
            log.info("Loading YOLO model from: \(modelURL.path)")
            
            let compiledModelURL = try MLModel.compileModel(at: modelURL)
            let model = try MLModel(contentsOf: compiledModelURL)
            
            // Get class labels
            guard let classes = model.modelDescription.classLabels as? [String] else {
                log.error("Could not get class labels from the model")
                return nil
            }
            self.classes = classes
            log.info("YOLO model loaded successfully with \(classes.count) classes")
            
            // Create Vision request
            let vnModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: vnModel)
            request.imageCropAndScaleOption = .scaleFill
            
            return request
        } catch {
            log.error("Failed to create YOLO request: \(error.localizedDescription)")
            return nil
        }
    }()
    
    private var classes: [String] = []
    private let ciContext = CIContext()
    private var frameCounter = 0
    private var frameInterval = 2 // Process every 2nd frame to improve performance
    
    // Operation queue for better management of detection tasks
    let detectionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.droneai.detection"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1  // Sequential processing
        return queue
    }()
    
    // For cancelling ongoing tasks
    private var detectionCancellable: AnyCancellable?
    
    // MARK: - Lifecycle
    
    override init() {
        super.init()
        
        // First try to copy the model if it's not already in place
        copyYOLOModelIfNeeded()
        
        // Check if model is available
        modelAvailable = isYOLOModelAvailable()
        // Pre-warm ML model when controller is initialized
        _ = yoloRequest
    }
    
    deinit {
        detectionCancellable?.cancel()
        detectionQueue.cancelAllOperations()
    }
    
    // MARK: - Public Methods
    
    /// Attempts to copy the YOLO model from project sources to app bundle if needed
    private func copyYOLOModelIfNeeded() {
        // Check if model already exists in bundle Resources
        let resourcesPath = Bundle.main.resourcePath ?? ""
        let resourcesURL = URL(fileURLWithPath: resourcesPath).appendingPathComponent("Resources")
        let targetURL = resourcesURL.appendingPathComponent("yolov8s.mlmodel")
        
        // If model already exists in target location, no need to copy
        if FileManager.default.fileExists(atPath: targetURL.path) {
            log.info("YOLO model already exists at target location: \(targetURL.path)")
            return
        }
        
        // Create Resources directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: resourcesURL.path) {
            do {
                try FileManager.default.createDirectory(
                    at: resourcesURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                log.info("Created Resources directory at: \(resourcesURL.path)")
            } catch {
                log.error("Failed to create Resources directory: \(error.localizedDescription)")
                return
            }
        }
        
        // Look for the model in YOLO directory in the project
        let projectDir = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent()
        let potentialSources = [
            projectDir.appendingPathComponent("YOLO/yolov8s.mlmodel"),
            projectDir.appendingPathComponent("DummyDronie/Resources/yolov8s.mlmodel"),
            projectDir.appendingPathComponent("YOLO/Example_Implementation/Yolov8-RealTime-iOS/yolov8s.mlpackage/Data/com.apple.CoreML/model.mlmodel")
        ]
        
        for sourceURL in potentialSources {
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                do {
                    try FileManager.default.copyItem(at: sourceURL, to: targetURL)
                    log.info("Successfully copied YOLO model from \(sourceURL.path) to \(targetURL.path)")
                    return
                } catch {
                    log.error("Failed to copy YOLO model from \(sourceURL.path): \(error.localizedDescription)")
                }
            }
        }
        
        log.error("Could not find a source YOLO model to copy")
    }
    
    /// Checks if the YOLO model file exists in the bundle
    func isYOLOModelAvailable() -> Bool {
        // Check in main bundle
        if Bundle.main.url(forResource: "yolov8s", withExtension: "mlmodel") != nil {
            return true
        }
        
        // Check in Resources directory
        let resourcesPath = Bundle.main.resourcePath ?? ""
        let resourcesURL = URL(fileURLWithPath: resourcesPath).appendingPathComponent("Resources")
        let modelURL = resourcesURL.appendingPathComponent("yolov8s.mlmodel")
        
        return FileManager.default.fileExists(atPath: modelURL.path)
    }
    
    /// Process a UIImage for object detection
    /// - Parameter image: The UIImage to process
    /// - Returns: An optional UIImage with detection boxes drawn
    func processFrame(image: UIImage) -> UIImage? {
        // Skip if model isn't available
        if !modelAvailable {
            return nil
        }
        
        // Skip frames for performance
        frameCounter += 1
        if frameCounter < frameInterval {
            return nil
        }
        frameCounter = 0
        
        // If detection is disabled, just return nil
        if !isDetectionActive {
            return nil
        }
        
        // Track processing time for performance monitoring
        let startTime = CACurrentMediaTime()
        let result = performDetection(on: image)
        let endTime = CACurrentMediaTime()
        processingTime = endTime - startTime
        
        return result
    }
    
    /// Process a frame asynchronously using Combine
    /// - Parameter image: The input image to process
    /// - Returns: A publisher that will emit the processed image with detections
    func processFrameAsync(image: UIImage) -> AnyPublisher<UIImage?, Never> {
        return Future<UIImage?, Never> { [weak self] promise in
            guard let self = self else {
                promise(.success(nil))
                return
            }
            
            // Skip if model isn't available
            if !self.modelAvailable {
                promise(.success(nil))
                return
            }
            
            self.detectionQueue.addOperation {
                let result = self.processFrame(image: image)
                promise(.success(result))
            }
        }.eraseToAnyPublisher()
    }
    
    /// Toggle detection on/off
    func toggleDetection() {
        isDetectionActive.toggle()
        
        if !isDetectionActive {
            // Cancel any ongoing operations when detection is disabled
            detectionQueue.cancelAllOperations()
            detectionCancellable?.cancel()
        }
    }
    
    // MARK: - Private Methods
    
    private func performDetection(on image: UIImage) -> UIImage? {
        guard let request = yoloRequest, let cgImage = image.cgImage else {
            log.error("YOLO request is not available or invalid image")
            return nil
        }
        
        do {
            // Perform the detection
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            
            // Process the results
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                return nil
            }
            
            // Convert results to Detection objects
            var detections: [Detection] = []
            let imageSize = CGSize(
                width: cgImage.width,
                height: cgImage.height
            )
            
            for result in results {
                // Skip low confidence detections
                if result.confidence < 0.5 {
                    continue
                }
                
                // Convert normalized coordinates to pixel coordinates
                let boundingBox = result.boundingBox
                let flippedBox = CGRect(
                    x: boundingBox.minX,
                    y: 1 - boundingBox.maxY,
                    width: boundingBox.width,
                    height: boundingBox.height
                )
                
                let box = VNImageRectForNormalizedRect(
                    flippedBox,
                    Int(imageSize.width),
                    Int(imageSize.height)
                )
                
                guard let label = result.labels.first?.identifier,
                      let colorIndex = classes.firstIndex(of: label) else {
                    continue
                }
                
                let detection = Detection(
                    box: box,
                    confidence: result.confidence,
                    label: label,
                    color: colors[min(colorIndex, colors.count - 1)]
                )
                
                detections.append(detection)
            }
            
            // Update published property on the main thread
            DispatchQueue.main.async {
                self.detectedObjects = detections
            }
            
            // Draw detection boxes on the image
            return drawDetections(detections, on: image)
            
        } catch {
            log.error("Detection error: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func drawDetections(_ detections: [Detection], on image: UIImage) -> UIImage? {
        let size = image.size
        
        // Create a graphics context
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        // Draw the original image
        image.draw(in: CGRect(origin: .zero, size: size))
        
        // Draw detection boxes
        for detection in detections {
            let invertedBox = CGRect(
                x: detection.box.minX,
                y: size.height - detection.box.maxY,
                width: detection.box.width,
                height: detection.box.height
            )
            
            // Draw bounding box
            context.setStrokeColor(detection.color.cgColor)
            context.setLineWidth(3.0)
            context.stroke(invertedBox)
            
            // Draw label
            let text = "\(detection.label) \(Int(detection.confidence * 100))%"
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.white,
                .backgroundColor: detection.color.withAlphaComponent(0.7)
            ]
            
            let textSize = text.size(withAttributes: textAttributes)
            let textRect = CGRect(
                x: invertedBox.minX,
                y: invertedBox.minY - textSize.height,
                width: textSize.width + 10,
                height: textSize.height
            )
            
            // Draw text background
            context.setFillColor(detection.color.withAlphaComponent(0.7).cgColor)
            context.fill(textRect)
            
            // Draw text
            text.draw(in: CGRect(
                x: textRect.minX + 5,
                y: textRect.minY,
                width: textRect.width - 10,
                height: textRect.height
            ), withAttributes: textAttributes)
        }
        
        // Get the resulting image
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resultImage
    }
}

/// VideoPreviewController handles the video preview setup and teardown for DJI drone's camera feed.
class VideoPreviewController: NSObject, DJIVideoFeedListener, ObservableObject {
    
    // MARK: - Properties
    
    /// A boolean property to indicate if the view preview is set up.
    @Published var isViewPreviewSetup: Bool = false
    
    /// Connection status for UI feedback
    @Published var connectionStatus: DroneConnectionStatus = .disconnected
    
    /// Model status for UI feedback
    @Published var modelStatus: String = "Checking YOLO model..."
    
    /// The YOLO detection controller for object detection
    private var yoloDetectionController = YOLODetectionController()
    
    /// Property to toggle object detection
    @Published var isObjectDetectionEnabled: Bool = true {
        didSet {
            yoloDetectionController.isDetectionActive = isObjectDetectionEnabled
        }
    }
    
    /// Published property with detected objects
    @Published var detectedObjects: [Detection] = []
    
    /// Current preview view
    private weak var currentPreviewView: UIView?
    
    /// Performance metrics
    @Published var framesProcessed: Int = 0
    @Published var processingTime: TimeInterval = 0
    @Published var frameRate: Double = 0
    
    /// Used to throttle object detection
    private var lastDetectionTime = Date()
    private let detectionInterval: TimeInterval = 0.5 // Lowered frequency to reduce load
    private var frameRateTimer: Timer?
    private var frameCount = 0
    private var lastFrameTime = Date()
    
    /// Frame source selection
    private var frameSource: FrameSource = .screenshot
    
    /// Combine subscribers
    private var cancellables = Set<AnyCancellable>()
    
    // Dedicated queues with appropriate QoS levels
    private let videoProcessingQueue = DispatchQueue(label: "com.droneai.video.processing", qos: .userInitiated)
    private let uiUpdateQueue = DispatchQueue.main
    private let lockQueue = DispatchQueue(label: "com.droneai.lock", attributes: .concurrent)
    
    // Operation queue for frame capturing
    private let frameCaptureQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.droneai.frameCapture"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    // Semaphore to limit concurrent frame processing
    private let frameProcessingSemaphore = DispatchSemaphore(value: 1)
    
    // Add lazy loading flag for the ML model
    private var modelLoaded = false
    private var isLoadingModel = false
    
    // MARK: - Lifecycle
    
    override init() {
        super.init()
        
        // Don't load the model immediately
        // This will be done later when needed
        
        // Set up logging for debugging model loading issues
        log.info("VideoPreviewController initialized - ML model will be loaded on demand")
        
        setupObservers()
        startFrameRateMonitoring()
    }
    
    deinit {
        resetVideoPreviewer()
        stopFrameRateMonitoring()
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    private func setupObservers() {
        // Monitor detection results
        yoloDetectionController.$detectedObjects
            .receive(on: RunLoop.main)
            .sink { [weak self] detections in
                self?.detectedObjects = detections
            }
            .store(in: &cancellables)
        
        // Monitor processing time
        yoloDetectionController.$processingTime
            .receive(on: RunLoop.main)
            .sink { [weak self] time in
                self?.processingTime = time
            }
            .store(in: &cancellables)
        
        // Monitor model availability
        yoloDetectionController.$modelAvailable
            .receive(on: RunLoop.main)
            .sink { [weak self] available in
                if available {
                    self?.modelStatus = "YOLO model loaded successfully"
                } else {
                    self?.modelStatus = "Error: YOLO model not found. Object detection disabled."
                    self?.isObjectDetectionEnabled = false
                }
            }
            .store(in: &cancellables)
        
        // Set up notification observers for application lifecycle events
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.applicationWillResignActive()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.applicationDidBecomeActive()
            }
            .store(in: &cancellables)
    }
    
    private func startFrameRateMonitoring() {
        frameRateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let currentTime = Date()
            let elapsedTime = currentTime.timeIntervalSince(self.lastFrameTime)
            if elapsedTime > 0 {
                self.frameRate = Double(self.frameCount) / elapsedTime
            }
            self.frameCount = 0
            self.lastFrameTime = currentTime
        }
    }
    
    private func stopFrameRateMonitoring() {
        frameRateTimer?.invalidate()
        frameRateTimer = nil
    }
    
    private func applicationWillResignActive() {
        // Pause video processing when app goes to background
        isObjectDetectionEnabled = false
    }
    
    private func applicationDidBecomeActive() {
        // Resume operations when app becomes active again
        if isViewPreviewSetup {
            // Re-enable detection if it was previously enabled
            isObjectDetectionEnabled = true
        }
    }
    
    // MARK: - Video Preview Setup
    
    /// Sets up the video previewer for the DJI drone's camera feed.
    /// - Parameter fpvPreview: The UIView to display the video preview.
    func setupVideoPreviewer(fpvPreview: UIView) {
        // Ensure we're on the main thread for UI operations
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.setupVideoPreviewer(fpvPreview: fpvPreview)
            }
            return
        }
        
        // Update connection status
        connectionStatus = .connecting
        
        // Check if SDK is registered and initialized
        if DJISDKManager.product() == nil {
            log.warning("No product detected. Waiting for connection...")
            connectionStatus = .connecting
            
            // Setup a retry timer if needed
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self, self.connectionStatus == .connecting else { return }
                
                if DJISDKManager.product() != nil {
                    self.setupVideoPreviewer(fpvPreview: fpvPreview)
                } else {
                    self.connectionStatus = .error("Timeout waiting for product connection")
                    log.error("Timeout waiting for product connection")
                }
            }
            return
        }
        
        // Try to get DJI components
        guard let videoPreviewer = DJIVideoPreviewer.instance() else {
            log.error("Could not fetch DJIVideoPreviewer instance")
            connectionStatus = .error("Failed to initialize video previewer")
            return
        }
        
        guard let videoFeeder = DJISDKManager.videoFeeder() else {
            log.error("Could not fetch the video feeder instance")
            connectionStatus = .error("Failed to initialize video feeder")
            return
        }
        
        // First, reset any existing video previewer
        resetVideoPreviewer()
        
        // Store the current preview view
        currentPreviewView = fpvPreview
        
        // Configure the video preview view
        fpvPreview.contentMode = .scaleAspectFit
        fpvPreview.backgroundColor = UIColor.black
        
        do {
            // Set up video previewer
        videoPreviewer.setView(fpvPreview)
            
            // Additional setup for better reliability
            // Use proper hardware decode method if available, or remove if not supported
            videoPreviewer.enableFastUpload = true
            
            // Start video previewer
            videoPreviewer.start()
            
            // Add self as listener on appropriate queue
        videoFeeder.primaryVideoFeed.add(self, with: nil)
            
            // Log success
            log.info("Setup video previewer successfully")
        isViewPreviewSetup = true
            connectionStatus = .connected
            
            // Clear any existing overlays
            if let currentView = currentPreviewView {
                removeDetectionOverlays(from: currentView)
            }
            
        } catch let error {
            log.error("Error setting up video previewer: \(error.localizedDescription)")
            connectionStatus = .error("Failed to setup video preview: \(error.localizedDescription)")
            
            // Try to recover
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.resetVideoPreviewer()
                self?.setupVideoPreviewer(fpvPreview: fpvPreview)
            }
        }
    }
    
    /// Resets the video previewer and removes it from the DJI drone's camera feed.
    func resetVideoPreviewer() {
        // Ensure we're on the main thread for UI operations
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.resetVideoPreviewer()
            }
            return
        }
        
        guard isViewPreviewSetup else { return }
        
        // Update connection status
        connectionStatus = .disconnected
        
        // Try to get DJI components
        guard let videoPreviewer = DJIVideoPreviewer.instance() else {
            log.error("Could not fetch DJIVideoPreviewer instance")
            return
        }
        
        guard let videoFeeder = DJISDKManager.videoFeeder() else {
            log.error("Could not fetch the video feeder instance")
            return
        }
        
        // Clean up frame capture resources
        frameCaptureQueue.cancelAllOperations()
        
        // Remove from video feed
        videoFeeder.primaryVideoFeed.remove(self)
        
        // Stop video previewer
        videoPreviewer.unSetView()
        
        // Remove any detection overlays
        if let currentView = currentPreviewView {
            removeDetectionOverlays(from: currentView)
        }
        
        log.info("Reset video previewer")
        isViewPreviewSetup = false
        currentPreviewView = nil
    }
    
    /// Toggle object detection on/off
    func toggleObjectDetection() {
        lockQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self.isObjectDetectionEnabled.toggle()
            self.yoloDetectionController.toggleDetection()
            
            DispatchQueue.main.async {
                // If turning off, remove any existing overlays
                if !self.isObjectDetectionEnabled, let currentView = self.currentPreviewView {
                    self.removeDetectionOverlays(from: currentView)
                }
            }
        }
    }
    
    // MARK: - Video Feed Processing
    
    /// Processes the updated video data from the DJI drone's camera feed.
    @objc func videoFeed(_ videoFeed: DJIVideoFeed, didUpdateVideoData videoData: Data) {
        // Ensure model is loaded before processing video
        if !modelLoaded && !isLoadingModel {
            loadModelIfNeeded()
        }
        
        // Process video data on appropriate queue to avoid blocking the video feed
        videoProcessingQueue.async { [weak self] in
            guard let self = self, self.isViewPreviewSetup else { return }
            
        guard let videoPreviewer = DJIVideoPreviewer.instance() else {
            log.error("Could not fetch DJIVideoPreviewer instance")
            return
        }
            
            // Convert Data to NSData for compatibility with DJI SDK
        let nsVideoData = videoData as NSData
            
            // Allocate buffer for video data
        let videoBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: nsVideoData.length)
            
            // Copy video data to buffer
        nsVideoData.getBytes(videoBuffer, length: nsVideoData.length)
            
            // Push video data to video previewer
        videoPreviewer.push(videoBuffer, length: Int32(nsVideoData.length))
            
            // Free the allocated memory to prevent memory leaks
            videoBuffer.deallocate()
            
            // Update frame counting for metrics
            self.frameCount += 1
            
            // Check if we should capture a frame for object detection (using semaphore to limit concurrency)
            if self.isObjectDetectionEnabled && Date().timeIntervalSince(self.lastDetectionTime) >= self.detectionInterval {
                // Try to acquire the semaphore with timeout
                let result = self.frameProcessingSemaphore.wait(timeout: .now() + 0.1)
                
                if result == .success {
                    self.lastDetectionTime = Date()
                    
                    // Use a dedicated operation for frame capture
                    let captureOperation = BlockOperation { [weak self] in
                        self?.captureCurrentFrame()
                        // Release the semaphore when done
                        self?.frameProcessingSemaphore.signal()
                    }
                    
                    // Set priority and add to queue
                    captureOperation.queuePriority = .high
                    self.frameCaptureQueue.addOperation(captureOperation)
                } else {
                    // If we couldn't acquire the semaphore, it means we're still 
                    // processing the previous frame - no need to signal
                    log.debug("Skipping frame capture - previous frame still processing")
                }
            }
        }
    }
    
    /// Capture the current frame from the preview view
    private func captureCurrentFrame() {
        // Run on main thread because we need to access UI views
        uiUpdateQueue.async { [weak self] in
            guard let self = self, 
                  let currentView = self.currentPreviewView, 
                  currentView.bounds.width > 0, 
                  currentView.bounds.height > 0 else { return }
            
            // Skip if YOLO model isn't available
            if !self.yoloDetectionController.modelAvailable {
                return
            }
            
            // Create an image context with the same size as the view
            UIGraphicsBeginImageContextWithOptions(currentView.bounds.size, false, 1.0)
            
            // Render the view into the image context
            if let context = UIGraphicsGetCurrentContext() {
                currentView.layer.render(in: context)
                
                // Get the image from the context
                if let image = UIGraphicsGetImageFromCurrentImageContext() {
                    // End the image context before processing to free resources
                    UIGraphicsEndImageContext()
                    
                    // Increment frames processed metric
                    self.framesProcessed += 1
                    
                    // Process frame asynchronously using Combine
                    self.yoloDetectionController.processFrameAsync(image: image)
                        .receive(on: self.uiUpdateQueue)
                        .sink { [weak self] processedImage in
                            guard let self = self, 
                                  self.isObjectDetectionEnabled,
                                  let currentView = self.currentPreviewView,
                                  let detectionImage = processedImage else { return }
                            
                            self.updateDetectionOverlay(on: currentView, with: detectionImage)
                        }
                        .store(in: &self.cancellables)
                } else {
                    UIGraphicsEndImageContext()
                }
            } else {
                UIGraphicsEndImageContext()
            }
        }
    }
    
    /// Update the detection overlay on the specified view
    private func updateDetectionOverlay(on view: UIView, with image: UIImage) {
        // Remove any previous detection overlays
        removeDetectionOverlays(from: view)
        
        // Create and add overlay
        let overlayView = UIImageView(image: image)
        overlayView.frame = view.bounds
        overlayView.contentMode = .scaleAspectFill
        overlayView.tag = 999
        overlayView.backgroundColor = UIColor.clear
        overlayView.isUserInteractionEnabled = false // Ensure it doesn't block touch events
        
        view.addSubview(overlayView)
    }
    
    /// Remove all detection overlays from a view
    private func removeDetectionOverlays(from view: UIView) {
        view.subviews.forEach { subview in
            if subview.tag == 999 {
                subview.removeFromSuperview()
            }
        }
    }
    
    /// Process a frame for object detection
    private func processFrameForObjectDetection(_ image: UIImage) {
        // This method is now obsolete, as we're using the Combine-based approach
        // Kept for backwards compatibility but not used
    }
    
    // MARK: - Public API
    
    /// Get current performance metrics
    func getPerformanceMetrics() -> [String: Any] {
        return [
            "frameRate": frameRate,
            "processingTime": processingTime,
            "framesProcessed": framesProcessed,
            "detectionActive": isObjectDetectionEnabled
        ]
    }
    
    /// Set the frame source for object detection
    func setFrameSource(_ source: FrameSource) {
        self.frameSource = source
        
        // Reset capture settings based on the new source
        switch source {
        case .screenshot:
            // Using current implementation
            break
        case .directSDK:
            // For future implementation when direct SDK access is available
            log.info("Direct SDK frame access not yet implemented")
        case .avCapture:
            // For future implementation when AVCapture is used
            log.info("AVCapture frame source not yet implemented")
        }
    }
    
    // Add a method to lazy load the ML model
    private func loadModelIfNeeded() {
        // If already loaded or currently loading, do nothing
        guard !modelLoaded && !isLoadingModel else {
            return
        }
        
        isLoadingModel = true
        
        // Load model in background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            log.info("Beginning YOLO model loading in background")
            
            // Call the existing findYOLOModel method
            self?.findYOLOModel()
            
            DispatchQueue.main.async {
                self?.modelLoaded = true
                self?.isLoadingModel = false
                log.info("YOLO model loaded successfully")
            }
        }
    }
}
