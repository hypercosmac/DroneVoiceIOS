#!/bin/bash

# Create directory for scripts if it doesn't exist
mkdir -p $(dirname "$0")

# Script to analyze memory usage in the DummyDronie app
echo "=== DummyDronie Memory Usage Analysis Tool ==="
echo ""
echo "This script helps identify large resources that might impact app startup."
echo ""

echo "=== Checking for large files in the app bundle ==="
find "$(dirname "$0")/.." -type f -size +1M -exec ls -lh {} \; | sort -rh

echo ""
echo "=== Analyzing YOLO model size ==="
YOLO_PATH="$(dirname "$0")/../Resources/yolov8s.mlmodel"
if [ -f "$YOLO_PATH" ]; then
  echo "YOLO model found: $(ls -lh "$YOLO_PATH")"
  echo "Size: $(du -h "$YOLO_PATH" | cut -f1)"
else
  echo "YOLO model not found at expected path: $YOLO_PATH"
fi

echo ""
echo "=== Recommendations ==="
echo "1. Consider using on-demand loading for large resources"
echo "2. Optimize launch sequence to defer non-critical initialization"
echo "3. Add a launch screen to improve perceived performance"
echo "4. Build with release configuration for debugging on device"
echo ""

echo "Memory analysis complete." 