#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "=== Record++ Build Script ==="
echo "Project: $PROJECT_DIR"

if command -v xcodegen &> /dev/null; then
    echo "Generating Xcode project..."
    cd "$PROJECT_DIR"
    xcodegen generate
    echo "Opening Xcode project..."
    open RecordPlusPlus.xcodeproj
else
    echo "xcodegen not found. Installing..."
    brew install xcodegen
    cd "$PROJECT_DIR"
    xcodegen generate
    open RecordPlusPlus.xcodeproj
fi

echo "=== Done ==="
echo ""
echo "To build from command line:"
echo "  xcodebuild -project RecordPlusPlus.xcodeproj -scheme RecordPlusPlus -configuration Release build"
echo ""
echo "To verify output with ffprobe:"
echo "  ffprobe -v error -show_entries stream=codec_name,pix_fmt -of default=noprint_wrappers=1 output.mov"