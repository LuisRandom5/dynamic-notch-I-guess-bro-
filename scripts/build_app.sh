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
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
export COPYFILE_DISABLE=1
export CLANG_MODULE_CACHE_PATH="${PROJECT_DIR}/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="${PROJECT_DIR}/.build/ModuleCache"
mkdir -p "${CLANG_MODULE_CACHE_PATH}"
swift build --disable-sandbox -c release -Xcc -fmodules-cache-path="${CLANG_MODULE_CACHE_PATH}"

echo "📦 Empaquetando DynamicNotch.app..."
STAGE_BUNDLE="/tmp/DynamicNotch_stage.app"
rm -rf "${STAGE_BUNDLE}"
mkdir -p "${STAGE_BUNDLE}/Contents/MacOS"
mkdir -p "${STAGE_BUNDLE}/Contents/Resources"

# Copy binary
cp -X -f "${PROJECT_DIR}/.build/release/DynamicNotch" "${STAGE_BUNDLE}/Contents/MacOS/DynamicNotch"
chmod +x "${STAGE_BUNDLE}/Contents/MacOS/DynamicNotch"

# Copy resources without extended attributes
if [ -d "${PROJECT_DIR}/Resources" ]; then
    cp -X -rf "${PROJECT_DIR}/Resources/"* "${STAGE_BUNDLE}/Contents/Resources/"
fi

# Create Info.plist
cat << 'EOF' > "${STAGE_BUNDLE}/Contents/Info.plist"
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
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
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
    <key>NSAudioCaptureUsageDescription</key>
    <string>Sólo mientras reproduces música o video, para que las barras del notch sigan el sonido. No se graba ni se guarda nada.</string>
    <key>NSContactsUsageDescription</key>
    <string>Dynamic Notch necesita acceder a tus contactos para mostrar la foto y el nombre de quien te llama.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Para mostrar en la isla tu próxima reunión con la cuenta regresiva y el botón para unirte. Sólo se lee; nunca se cambia nada.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Para mostrar en la isla tu próxima reunión con la cuenta regresiva y el botón para unirte. Sólo se lee; nunca se cambia nada.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Dynamic Notch necesita Bluetooth para detectar la conexión de tus AirPods y mostrar la animación correspondiente.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Dynamic Notch utiliza Bluetooth para monitorear el estado de conexión de tus AirPods y accesorios de audio.</string>
</dict>
</plist>
EOF

echo "✍️ Firmando app localmente con Designated Requirement estable..."
find "${STAGE_BUNDLE}" -name '._*' -delete 2>/dev/null || true
xattr -cr "${STAGE_BUNDLE}" 2>/dev/null || true
codesign --force --deep -s - --entitlements "${PROJECT_DIR}/entitlements.plist" -r='designated => identifier "com.luisrandom.DynamicNotch"' "${STAGE_BUNDLE}"

rm -rf "${APP_BUNDLE}"
cp -R "${STAGE_BUNDLE}" "${APP_BUNDLE}"
rm -rf "${STAGE_BUNDLE}"

echo "✅ DynamicNotch.app creada y firmada exitosamente en: ${APP_BUNDLE}"
killall -9 DynamicNotch 2>/dev/null || true
sleep 0.3
# Esperar a que la instancia anterior termine de cerrarse antes de abrir la nueva
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x DynamicNotch >/dev/null || break
    sleep 0.2
done
open "${APP_BUNDLE}" 2>/dev/null || { nohup "${MACOS_DIR}/DynamicNotch" >/dev/null 2>&1 & disown 2>/dev/null || true; }
echo "🚀 DynamicNotch iniciado en segundo plano (instancia única)."
