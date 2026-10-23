#!/bin/bash
set -e

# Uso: ./scripts/build_app.sh            → compilación de desarrollo (DynamicNotch.app en el proyecto, se abre sola)
#      ./scripts/build_app.sh --beta     → beta para probadores, sin herramientas de desarrollo (dist/, no se abre)
#      BETA_NUMBER=2 ./scripts/build_app.sh --beta
BETA=0
[ "${1:-}" = "--beta" ] && BETA=1
VERSION="2.1"
BUILD_NUMBER="2.1.0"
BETA_NUMBER="${BETA_NUMBER:-1}"

# Directory setup
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${PROJECT_DIR}/DynamicNotch.app"
BUILD_PATH="${PROJECT_DIR}/.build"
EXTRA_SWIFT_FLAGS=()
if [ "${BETA}" = "1" ]; then
    # Carpeta de compilación aparte: no se recompila todo al volver a la de desarrollo
    BUILD_PATH="${PROJECT_DIR}/.build-beta"
    EXTRA_SWIFT_FLAGS=(-Xswiftc -DBETA)
    VERSION="${VERSION}-beta.${BETA_NUMBER}"
    BUILD_NUMBER="${BUILD_NUMBER}.${BETA_NUMBER}"
    DIST_DIR="${PROJECT_DIR}/dist/DynamicNotch-${VERSION}"
    APP_BUNDLE="${DIST_DIR}/DynamicNotch.app"
fi
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
# Las acciones de Atajos (App Intents) necesitan los valores constantes que el compilador extrae del código;
# Xcode lo hace solo, con SwiftPM se pide aquí y luego se generan los metadatos (ver más abajo)
CONST_VALUES="${BUILD_PATH}/DynamicNotch.swiftconstvalues"
swift build --disable-sandbox -c release --build-path "${BUILD_PATH}" ${EXTRA_SWIFT_FLAGS[@]+"${EXTRA_SWIFT_FLAGS[@]}"} -Xcc -fmodules-cache-path="${CLANG_MODULE_CACHE_PATH}" \
    -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc "${PROJECT_DIR}/scripts/appintents_protocols.json" \
    -Xswiftc -emit-const-values-path -Xswiftc "${CONST_VALUES}"

echo "📦 Empaquetando DynamicNotch.app..."
STAGE_BUNDLE="/tmp/DynamicNotch_stage.app"
rm -rf "${STAGE_BUNDLE}"
mkdir -p "${STAGE_BUNDLE}/Contents/MacOS"
mkdir -p "${STAGE_BUNDLE}/Contents/Resources"

# Copy binary
cp -X -f "${BUILD_PATH}/release/DynamicNotch" "${STAGE_BUNDLE}/Contents/MacOS/DynamicNotch"
chmod +x "${STAGE_BUNDLE}/Contents/MacOS/DynamicNotch"

# Copy resources without extended attributes
if [ -d "${PROJECT_DIR}/Resources" ]; then
    cp -X -rf "${PROJECT_DIR}/Resources/"* "${STAGE_BUNDLE}/Contents/Resources/"
fi

# Puente de "lo que está sonando": biblioteca que carga /usr/bin/perl (ver Bridge/MediaRemoteBridge.swift)
xcrun swiftc -O -emit-library -module-name DNMediaBridge "${PROJECT_DIR}/Bridge/MediaRemoteBridge.swift" \
    -target arm64-apple-macosx14.0 -o "${STAGE_BUNDLE}/Contents/Resources/MediaRemoteBridge.dylib"

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
    <string>__BUILD_NUMBER__</string>
    <key>CFBundleShortVersionString</key>
    <string>__VERSION__</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>es</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>es</string>
        <string>en</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>DynamicNotch</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
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
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.luisrandom.DynamicNotch.activity</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>dynamicnotch</string>
            </array>
        </dict>
    </array>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Para mostrar en la isla tu próxima reunión con la cuenta regresiva y el botón para unirte. Sólo se lee; nunca se cambia nada.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Para mostrar en la isla tu próxima reunión con la cuenta regresiva y el botón para unirte. Sólo se lee; nunca se cambia nada.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Dynamic Notch necesita Bluetooth para detectar la conexión de tus AirPods y mostrar la animación correspondiente.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Dynamic Notch utiliza Bluetooth para monitorear el estado de conexión de tus AirPods y accesorios de audio.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Para encontrar tu tele en la red de tu casa y mostrar en ella los avisos de Casa (la lavadora terminó, la puerta del refri).</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_androidtvremote2._tcp</string>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <!-- La tele recibe los avisos por HTTP dentro de la red local (PiPup, puerto 7979) -->
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

sed -i '' -e "s/__BUILD_NUMBER__/${BUILD_NUMBER}/" -e "s/__VERSION__/${VERSION}/" "${STAGE_BUNDLE}/Contents/Info.plist"

# Metadatos de App Intents (Atajos y Siri): lo que Xcode genera al compilar una app
if [ -n "${DEVELOPER_DIR:-}" ] && xcrun --find appintentsmetadataprocessor >/dev/null 2>&1 && [ -f "${CONST_VALUES}" ]; then
    echo "🧩 Generando acciones de Atajos..."
    AI_DIR="${BUILD_PATH}/appintents"
    rm -rf "${AI_DIR}" && mkdir -p "${AI_DIR}"
    find "${PROJECT_DIR}/Sources/DynamicNotch" -name "*.swift" > "${AI_DIR}/sources.txt"
    echo "${CONST_VALUES}" > "${AI_DIR}/constvalues.txt"
    XCODE_BUILD_VERSION=$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}')
    xcrun appintentsmetadataprocessor \
        --output "${STAGE_BUNDLE}/Contents/Resources" \
        --toolchain-dir "${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain" \
        --module-name DynamicNotch \
        --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
        --xcode-version "${XCODE_BUILD_VERSION:-27A9275}" \
        --platform-family macOS \
        --deployment-target 14.0 \
        --target-triple arm64-apple-macosx14.0 \
        --source-file-list "${AI_DIR}/sources.txt" \
        --swift-const-vals-list "${AI_DIR}/constvalues.txt" \
        --force --quiet-warnings >/dev/null 2>&1 || echo "⚠️ No se pudieron generar las acciones de Atajos (la app funciona igual)"
fi

echo "✍️ Firmando app localmente con Designated Requirement estable..."
find "${STAGE_BUNDLE}" -name '._*' -delete 2>/dev/null || true
xattr -cr "${STAGE_BUNDLE}" 2>/dev/null || true
codesign --force --deep -s - --entitlements "${PROJECT_DIR}/entitlements.plist" -r='designated => identifier "com.luisrandom.DynamicNotch"' "${STAGE_BUNDLE}"

if [ "${BETA}" = "1" ]; then
    # Beta: carpeta con la app y la guía, y un .zip listo para mandar (la app de desarrollo no se toca)
    rm -rf "${DIST_DIR}" && mkdir -p "${DIST_DIR}"
    cp -R "${STAGE_BUNDLE}" "${APP_BUNDLE}"
    rm -rf "${STAGE_BUNDLE}"
    cp "${PROJECT_DIR}/docs/BETA_LEEME.md" "${DIST_DIR}/LEEME.md"
    ZIP="${PROJECT_DIR}/dist/DynamicNotch-${VERSION}.zip"
    rm -f "${ZIP}"
    ditto -c -k --norsrc --noextattr --keepParent "${DIST_DIR}" "${ZIP}"
    echo "✅ Beta lista: ${ZIP}"
    exit 0
fi

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
