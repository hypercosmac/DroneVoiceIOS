//
//  YOLODetectionController.swift
//  DummyDronie
//
//  Created on 3/05/24.
//

import Foundation
import Vision
import UIKit
import CoreML
import AVFoundation

/// YOLODetectionController handles the object detection using YOLOv8 model.
class YOLODetectionController: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    /// Published properties for UI updates
    @Published var detectedObjects: [Detection] = []
    @Published var isDetectionActive: Bool = true
    
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
            // Load the YOLO model
            let modelURL = Bundle.main.url(forResource: "yolov8s", withExtension: "mlmodel")!
            let compiledModelURL = try MLModel.compileModel(at: modelURL)
            let model = try MLModel(contentsOf: compiledModelURL)
            
            // Get class labels
            guard let classes = model.modelDescription.classLabels as? [String] else {
                log.error("Could not get class labels from the model")
                return nil
            }
            self.classes = classes
            
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
    
    // MARK: - Public Methods
    
    /// Process a pixel buffer for object detection
    /// - Parameter pixelBuffer: The CVPixelBuffer to process
    /// - Returns: An optional UIImage with detection boxes drawn
    func processFrame(pixelBuffer: CVPixelBuffer) -> UIImage? {
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
        
        return performDetection(on: pixelBuffer)
    }
    
    /// Toggle detection on/off
    func toggleDetection() {
        isDetectionActive.toggle()
    }
    
    // MARK: - Private Methods
    
    private func performDetection(on pixelBuffer: CVPixelBuffer) -> UIImage? {
        guard let request = yoloRequest else {
            log.error("YOLO request is not available")
            return nil
        }
        
        do {
            // Perform the detection
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            try handler.perform([request])
            
            // Process the results
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                return nil
            }
            
            // Convert results to Detection objects
            var detections: [Detection] = []
            let imageSize = CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
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
            
            // Update published property
            DispatchQueue.main.async {
                self.detectedObjects = detections
            }
            
            // Draw detection boxes on the image
            return drawDetections(detections, on: pixelBuffer)
            
        } catch {
            log.error("Detection error: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func drawDetections(_ detections: [Detection], on pixelBuffer: CVPixelBuffer) -> UIImage? {
        // Create a CIImage from the pixel buffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        let size = ciImage.extent.size
        
        // Create a graphics context
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        // Draw the original image
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
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

/// Represents a detected object
struct Detection: Identifiable {
    let id = UUID()
    let box: CGRect
    let confidence: Float
    let label: String
    let color: UIColor
} 