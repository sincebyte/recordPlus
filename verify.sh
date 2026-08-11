#!/bin/bash
# verify.sh - Validate ProRes 4444 output with Alpha channel
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <output.mov>"
    exit 1
fi

INPUT="$1"

if [ ! -f "$INPUT" ]; then
    echo "Error: File not found: $INPUT"
    exit 1
fi

echo "=== Verifying: $INPUT ==="
echo ""

echo "File Info:"
ls -lh "$INPUT"
echo ""

echo "--- ffprobe Stream Info ---"
ffprobe -v error -show_entries stream=codec_name,codec_type,width,height,pix_fmt,r_frame_rate,duration \
    -of default=noprint_wrappers=1 "$INPUT"
echo ""

echo "--- Pixel Format Check ---"
PIX_FMT=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 "$INPUT")
echo "Pixel Format: $PIX_FMT"

if [ "$PIX_FMT" = "yuva444p10le" ]; then
    echo "✓ PASS: RGBA pixel format detected (yuva444p10le)"
elif [ "$PIX_FMT" = "yuva444p12le" ]; then
    echo "✓ PASS: RGBA pixel format detected (yuva444p12le)"
else
    echo "✗ WARNING: Expected yuva444p10le, got $PIX_FMT"
fi

echo ""
echo "--- Codec Check ---"
CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INPUT")
echo "Codec: $CODEC"

if [ "$CODEC" = "prores" ]; then
    echo "✓ PASS: ProRes codec detected"
else
    echo "✗ WARNING: Expected prores, got $CODEC"
fi

echo ""
echo "=== Verification Complete ==="