#!/bin/bash
set -e

# Directory setup
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${PROJECT_DIR}/DynamicNotch.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 Compilando Dynamic Notch en Swift..."
cd "${PROJECT_DIR}"
swift build -c release

echo "📦 Empaquetando DynamicNotch.app..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy binary
cp "${PROJECT_DIR}/.build/release/DynamicNotch" "${MACOS_DIR}/DynamicNotch"
chmod +x "${MACOS_DIR}/DynamicNotch"

# Create Info.plist
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleName</key>
    <string>Dynamic Notch</string>
    <key>CFBundleDisplayName</key>
    <string>Dynamic Notch</string>
    <key>CFBundleIdentifier</key>
    <string>com.luisrandom.DynamicNotch</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>DynamicNotch</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Dynamic Notch necesita controlar la música para mostrar canciones y controles.</string>
</dict>
</plist>
EOF

echo "✍️ Firmando app localmente (ad-hoc signing)..."
xattr -cr "${APP_BUNDLE}"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✅ DynamicNotch.app creada y firmada exitosamente en: ${APP_BUNDLE}"
