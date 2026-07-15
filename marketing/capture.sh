#!/usr/bin/env bash
# Helper for capturing demo recordings/screenshots from the iOS Simulator.
# This does NOT drive the app itself — pair it with in-app TileScript playback
# (see video-scripts/00-overview.md). It just handles boot + record + still capture.
#
# Prereqs: Xcode, an iPad simulator, and the app built & installed on it.
# For REAL AI sentences during capture, set OPENAI_API_KEY in the app's scheme
# (Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments ▸ Environment Variables),
# otherwise the app falls back to the Mock provider (fake sentences).
set -euo pipefail

SIM_NAME="${SIM_NAME:-iPad Pro 11-inch (M5)}"
OUTDIR="$(dirname "$0")/assets/screenshots"
mkdir -p "$OUTDIR"

usage() {
  cat <<EOF
Usage:
  ./capture.sh boot                 # boot the simulator named "\$SIM_NAME"
  ./capture.sh shot <name>          # save a PNG screenshot -> assets/screenshots/<name>.png
  ./capture.sh rec <name>           # start recording; Ctrl-C to stop -> assets/screenshots/<name>.mov
Env:
  SIM_NAME   simulator device name (default: "iPad Pro 11-inch (M5)")
EOF
}

case "${1:-}" in
  boot)
    xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
    open -a Simulator
    echo "Booted (or already running): $SIM_NAME"
    ;;
  shot)
    name="${2:?need a name}"
    xcrun simctl io booted screenshot "$OUTDIR/$name.png"
    echo "→ $OUTDIR/$name.png"
    ;;
  rec)
    name="${2:?need a name}"
    echo "Recording… press Ctrl-C to stop."
    xcrun simctl io booted recordVideo --codec h264 "$OUTDIR/$name.mov"
    ;;
  *)
    usage; exit 1 ;;
esac
