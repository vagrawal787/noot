#!/bin/bash
set -e

# Noot Release Build Script
# Creates a signed .dmg for distribution

VERSION="${1:-1.0.0}"
APP_NAME="Noot"
PROJECT_DIR="Noot"
BUILD_DIR="build"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_TEMP="temp_dmg"

echo "=== Building ${APP_NAME} v${VERSION} ==="

# Change to project directory
cd "$(dirname "$0")/.."

# Clean previous builds
rm -rf "$BUILD_DIR"
rm -rf "$DMG_TEMP"
rm -f "$DMG_NAME"

# Build Release configuration
echo "Building Release configuration..."
xcodebuild -project "${PROJECT_DIR}/Noot.xcodeproj" \
    -scheme Noot \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    | xcpretty || xcodebuild -project "${PROJECT_DIR}/Noot.xcodeproj" \
    -scheme Noot \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES

# Find the built app
APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Built app not found at $APP_PATH"
    exit 1
fi

echo "App built successfully at $APP_PATH"

# Ad-hoc sign (required for Apple Silicon)
echo "Ad-hoc signing the app bundle..."
codesign --force --deep --sign - "$APP_PATH"

# Verify signature
echo "Verifying signature..."
codesign --verify --verbose "$APP_PATH"

# Create DMG
echo "Creating DMG..."
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG with hdiutil
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_NAME"

# Cleanup
rm -rf "$DMG_TEMP"

echo ""
echo "=== Build Complete ==="
echo "Created: $DMG_NAME"
echo ""
echo "To test installation:"
echo "  1. Open $DMG_NAME"
echo "  2. Drag Noot to Applications"
echo "  3. Launch Noot from Applications"
echo "  4. Allow in System Settings → Privacy & Security if prompted"
