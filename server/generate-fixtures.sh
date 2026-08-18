#!/usr/bin/env bash
# [Intent] Generate sample test media fixtures for AVPlayer, Chromecast, and VLCKit testing
set -euo pipefail

MEDIA_DIR="./media"
mkdir -p "$MEDIA_DIR"

echo "==> Generating standard test media fixtures..."

# 1. Standard MP4 (H.264 + AAC) - Native AVPlayer & Chromecast compliant
ffmpeg -y -f lavfi -i testsrc=duration=30:size=1920x1080:rate=30 \
       -f lavfi -i sine=frequency=440:duration=30 \
       -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 192k \
       "$MEDIA_DIR/sample_1080p_h264.mp4"

# 2. MKV (HEVC / H.265 + FLAC) - Non-native VLCKit fallback test
ffmpeg -y -f lavfi -i testsrc=duration=30:size=1920x1080:rate=30 \
       -f lavfi -i sine=frequency=880:duration=30 \
       -c:v libx265 -c:a flac \
       "$MEDIA_DIR/sample_1080p_h265.mkv"

# 3. Audio Test: MP3 with ID3 metadata
ffmpeg -y -f lavfi -i sine=frequency=523.25:duration=60 \
       -c:a libmp3lame -b:a 320k \
       -metadata title="C Major Sine Tone" \
       -metadata artist="Acoustic Lab" \
       -metadata album="Frequency Test Suite" \
       "$MEDIA_DIR/sample_audio.mp3"

# 4. Audio Test: High-Res FLAC (24-bit 96kHz)
ffmpeg -y -f lavfi -i sine=frequency=440:duration=60:sample_rate=96000 \
       -c:a flac -sample_fmt s32 \
       "$MEDIA_DIR/sample_hires.flac"

# 5. HLS Stream Generation (.m3u8) for in-app stream testing
mkdir -p "$MEDIA_DIR/hls"
ffmpeg -y -f lavfi -i testsrc=duration=120:size=1280x720:rate=30 \
       -f lavfi -i sine=frequency=440:duration=120 \
       -c:v libx264 -c:a aac \
       -hls_time 4 -hls_playlist_type vod \
       "$MEDIA_DIR/hls/master.m3u8"

echo "==> Fixtures generated successfully in $MEDIA_DIR."
