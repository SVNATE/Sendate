#!/bin/bash
#
# build_dmg.sh — Build Sendate macOS release and create a styled DMG installer
#
# Usage:
#   ./scripts/build_dmg.sh                # Build app + DMG
#   ./scripts/build_dmg.sh --skip-build   # Only create DMG (app already built)
#   ./scripts/build_dmg.sh --install      # Build + DMG + install to /Applications
#
# Output: build/Sendate.dmg
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Sendate"
DMG_NAME="Sendate"
APP_PATH="$PROJECT_DIR/build/macos/Build/Products/Release/${APP_NAME}.app"
DMG_PATH="$PROJECT_DIR/build/${DMG_NAME}.dmg"
DMG_TEMP="$PROJECT_DIR/build/${DMG_NAME}_temp.dmg"
STAGING_DIR="$PROJECT_DIR/build/dmg_staging"
BG_IMG="$SCRIPT_DIR/dmg/background.png"
VOLUME_NAME="$APP_NAME"
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
ICON_SIZE=128

SKIP_BUILD=false
DO_INSTALL=false

for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=true ;;
        --install) DO_INSTALL=true ;;
    esac
done

echo "═══════════════════════════════════════════════════"
echo "  Sendate DMG Builder"
echo "═══════════════════════════════════════════════════"

# Step 1: Build macOS release (unless --skip-build)
if [ "$SKIP_BUILD" = false ]; then
    echo ""
    echo "▶ Building macOS release..."
    cd "$PROJECT_DIR"
    flutter build macos --release
    echo "✓ Build complete: $APP_PATH"
fi

# Verify app exists
if [ ! -d "$APP_PATH" ]; then
    echo "✗ Error: $APP_PATH not found. Run without --skip-build first."
    exit 1
fi

# Step 2: Clean previous artifacts
echo ""
echo "▶ Preparing DMG staging..."
rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH"
rm -f "$DMG_TEMP"
mkdir -p "$STAGING_DIR"

# Step 3: Copy app and create Applications symlink
cp -R "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

# Step 4: Create temporary read-write DMG
echo "▶ Creating disk image..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$DMG_TEMP" \
    -quiet

# Step 5: Mount and style the DMG
echo "▶ Styling DMG window..."
MOUNT_DIR="/Volumes/$VOLUME_NAME"

# Unmount if already mounted
if [ -d "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" -quiet -force 2>/dev/null || true
fi

hdiutil attach "$DMG_TEMP" -readwrite -noverify -quiet

# Copy background image into hidden folder in DMG
mkdir -p "$MOUNT_DIR/.background"
cp "$BG_IMG" "$MOUNT_DIR/.background/background.png"
if [ -f "$SCRIPT_DIR/dmg/background@2x.png" ]; then
    cp "$SCRIPT_DIR/dmg/background@2x.png" "$MOUNT_DIR/.background/background@2x.png"
fi

# Apply Finder window styling via AppleScript
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, $((100 + WINDOW_WIDTH)), $((100 + WINDOW_HEIGHT))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $ICON_SIZE
        set background picture of viewOptions to file ".background:background.png"
        -- Position app icon on the left
        set position of item "${APP_NAME}.app" of container window to {170, 200}
        -- Position Applications symlink on the right
        set position of item "Applications" of container window to {490, 200}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

# Wait for Finder to finish
sync
sleep 2

# Step 6: Set custom volume icon (uses the app icon)
# Copy app icon as volume icon
cp "$APP_PATH/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
SetFile -a C "$MOUNT_DIR" 2>/dev/null || true

# Step 7: Unmount
hdiutil detach "$MOUNT_DIR" -quiet

# Step 8: Convert to compressed read-only DMG
echo "▶ Compressing final DMG..."
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" -quiet
rm -f "$DMG_TEMP"

# Step 8.5: Sign the DMG
if [ -n "$APPLE_TEAM_ID" ]; then
    echo "▶ Code signing DMG with Team ID: $APPLE_TEAM_ID..."
    codesign --force --sign "$APPLE_TEAM_ID" "$DMG_PATH"
else
    echo "▶ Skipping code signing (APPLE_TEAM_ID not set)"
fi

# Step 9: Cleanup staging
rm -rf "$STAGING_DIR"

# Done
DMG_SIZE=$(du -sh "$DMG_PATH" | awk '{print $1}')
echo ""
echo "═══════════════════════════════════════════════════"
echo "  ✓ DMG created successfully!"
echo ""
echo "  Output: $DMG_PATH"
echo "  Size:   $DMG_SIZE"
echo "═══════════════════════════════════════════════════"

# Step 10: Install to /Applications (if --install flag)
if [ "$DO_INSTALL" = true ]; then
    echo ""
    echo "▶ Installing to /Applications..."
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP_PATH" "/Applications/${APP_NAME}.app"
    echo "✓ Installed: /Applications/${APP_NAME}.app"
    echo "▶ Resetting Launchpad..."
    defaults write com.apple.dock ResetLaunchPad -bool true && killall Dock
    echo "✓ Launchpad refreshed — Sendate is now visible!"
fi
