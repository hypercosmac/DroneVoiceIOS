# YOLO Model Resources

This directory contains the YOLOv8 model file used for object detection in the DroneAI application.

## Files

- `yolov8s.mlmodel`: YOLOv8 Small model converted to Core ML format for use with iOS.

## Usage

The model is loaded by the `YOLODetectionController` class in the application. Make sure this file is included in the app bundle during the build process.

## Troubleshooting

If you encounter errors related to the model not being found:

1. Ensure the model file is included in the "Copy Bundle Resources" build phase in Xcode
2. Check that the file name and extension match exactly what the code is looking for
3. Verify that the model is properly converted to Core ML format

## Model Information

- Model: YOLOv8s
- Size: ~22MB
- Classes: 80 COCO dataset classes
- Input Size: 640x640 pixels
- Framework: Core ML 