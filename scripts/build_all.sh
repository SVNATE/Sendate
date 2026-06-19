#!/bin/bash
#
# build_all.sh — Build Sendate for all platforms
#
# Usage:
#   ./scripts/build_all.sh           # Build Android APK + macOS DMG
#   ./scripts/build_all.sh android   # Only Android
#   ./scripts/build_all.sh macos     # Only macOS
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

TARGET="${1:-all}"

echo "═══════════════════════════════════════════════════"
echo "  Sendate Build System"
echo "═══════════════════════════════════════════════════"
echo ""

# Android APK
if [[ "$TARGET" == "all" || "$TARGET" == "android" ]]; then
    echo "▶ Building Android release APK..."
    flutter build apk --release
    APK_SIZE=$(du -sh build/app/outputs/flutter-apk/app-release.apk | awk '{print $1}')
    echo "✓ Android APK: build/app/outputs/flutter-apk/app-release.apk ($APK_SIZE)"
    echo ""
fi

# macOS DMG
if [[ "$TARGET" == "all" || "$TARGET" == "macos" ]]; then
    echo "▶ Building macOS release + DMG..."
    "$SCRIPT_DIR/build_dmg.sh"
    echo ""
fi

echo "═══════════════════════════════════════════════════"
echo "  ✓ Build complete!"
echo "═══════════════════════════════════════════════════"
