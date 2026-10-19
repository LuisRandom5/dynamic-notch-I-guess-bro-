#!/bin/bash
# Corre las pruebas unitarias. Las Command Line Tools no traen el framework Testing; se usa el de Xcode.
set -e
cd "$(dirname "$0")/.."
if [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
# Carpeta propia fuera de Documentos: no se mezcla con la compilación release de build_app.sh (otro
# toolchain) y codesign no choca con los atributos extendidos que deja la sincronización de Documentos
swift test --scratch-path "$HOME/Library/Caches/DynamicNotchTests" "$@"
