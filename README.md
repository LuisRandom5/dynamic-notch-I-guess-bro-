# 🍏 Dynamic Notch (macOS Nativo)

> **La Isla Dinámica del iPhone en tu Mac**, con notch o sin él, escrita en **Swift, SwiftUI y AppKit**. Pensada para sentirse como una función oficial de Apple, gastando poco CPU y batería.

---

## ✨ Qué hace

- 🏝️ **Isla Dinámica en cualquier Mac:**
  - Con notch, la isla abraza la cámara.
  - Sin notch (MacBook Air viejas o un monitor externo), es una cápsula flotante del alto de la barra de menús, separada del borde como en el iPhone.
  - Desde el menú eliges la pantalla y la forma (isla o notch).
- 🫧 **Varias actividades a la vez:**
  - Una en el notch y hasta dos bolitas líquidas a los lados; el resto espera en cola.
  - Deslizar a lo ancho recorre las actividades, incluida la música.
  - Las bolitas se ocultan mientras ves su app.
- 🎵 **Música (Apple Music, Spotify y navegadores):**
  - Carátula, barras que siguen el sonido, controles con las animaciones de Apple Music y letras.
  - Se esconde en pantalla completa.
- 💬 **Avisos al estilo iPhone:**
  - WhatsApp con respuesta rápida; dice si es foto, sticker, audio, etc.
  - Carga, carga completa y batería baja.
  - Bloq Mayús, red y VPN.
  - Cámara y micrófono en uso, Notas de Voz grabando y Concentración.
  - Descargas y próxima reunión, con botón para unirte.
  - Opción para ocultar el texto de los mensajes al grabar la pantalla.
- 🤖 **Claude y agentes:** una bolita que muestra en qué está trabajando Claude Code, con su tarjeta de progreso.
- 🧩 **API para tus scripts y apps:**
  - Pon tu propia actividad en la isla (builds, tests, descargas, deploys) con `dynamicnotch run tests -- swift test`.
  - También por HTTP local o con `dynamicnotch://` desde Atajos.
  - Ver [docs/API.md](docs/API.md).
- 🗣️ **Atajos, Siri e inglés:** acciones nativas en la app Atajos, y la interfaz en inglés si tu Mac está en inglés.
- 📁 **Repisa:** arrastra archivos al notch para guardarlos un rato y llevarlos a otra app.
- ⚡ **Nativa y ligera:**
  - Swift, SwiftUI y AppKit, sin Electron.
  - ~2 % de CPU en reposo y ~13 % con música y las barras activas, medido en una MacBook Pro M-series.
  - Nunca usa el micrófono.

---

## 🚀 Compilación y Ejecución

### 1. Compilar y empaquetar la app (.app):
```bash
./scripts/build_app.sh
```
Esto genera `DynamicNotch.app` firmada localmente para tu Mac.

### 2. Abrir la app:
```bash
open DynamicNotch.app
```
O simplemente haz doble clic en `DynamicNotch.app` desde Finder, o cópiala a tu carpeta `/Applications`.

### 3. Salir de la app:
Haz clic en el icono de la cápsula en tu barra de menús y selecciona **"Salir de Dynamic Notch"**, o ejecuta:
```bash
pkill DynamicNotch
```
