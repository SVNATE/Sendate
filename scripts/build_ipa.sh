#!/bin/bash
#
# build_ipa.sh — Build Sendate iOS release and export signed IPA for App Store
#
# Output: build/ios/ipa/Sendate.ipa
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "═══════════════════════════════════════════════════"
echo "  Sendate iOS IPA Builder"
echo "═══════════════════════════════════════════════════"
echo ""

echo "▶ Building Signed IPA for App Store Distribution..."
cd "$PROJECT_DIR"
flutter build ipa --release --export-method app-store

echo ""
echo "═══════════════════════════════════════════════════"
echo "  ✓ IPA created successfully!"
echo "  You can now upload it via Transporter."
echo "═══════════════════════════════════════════════════"
