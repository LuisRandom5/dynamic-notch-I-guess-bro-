# 🍏 Dynamic Notch (macOS Nativo)

> **Isla Dinámica 100% nativa para el Notch de tu MacBook**, escrita en **Swift, SwiftUI y AppKit**. Diseñada para integrarse en macOS con el mismo nivel de rendimiento, consumo de batería y fluidez que una función oficial de Apple.

- 🧩 **API para tus scripts y apps:**
  - Pon tu propia actividad en la isla (builds, tests, descargas, deploys) con `dynamicnotch run tests -- swift test`, por HTTP local o con `dynamicnotch://` desde Atajos. Ver [docs/API.md](docs/API.md).

---

## ✨ Características Nativas

- ⚡ **100% Nativo en Swift & SwiftUI:**
  - Sin Electron, sin navegadores embebidos, sin consumo desmedido de RAM.
  - ~0.3% de CPU en reposo y respuesta instantánea a 60/120Hz ProMotion.
- 📐 **Detección Automática de Hardware:**
  - Utiliza las APIs de macOS (`NSScreen.auxiliaryTopLeftArea` y `auxiliaryTopRightArea`) para calcular al milímetro el notch físico de tu MacBook Pro o Air.
- 🪟 **Panel Flotante Sin Pérdida de Foco (`NSPanel.nonactivatingPanel`):**
  - Flota sobre la barra de menús, ventanas y aplicaciones a pantalla completa (`.fullScreenAuxiliary`).
  - **Hit-Testing Inteligente:** Clics fuera del notch atraviesan la ventana transparente hacia las apps que tengas debajo.
- 🎵 **Música en Tiempo Real (Spotify & Apple Music):**
  - Escucha instantánea de eventos del sistema mediante `DistributedNotificationCenter` (cero consumo por sondeo continuo).
  - Título, artista, álbum, carátula en alta definición y controles de reproducción.
- ⚡ **Conexión MagSafe en Vivo:**
  - Detecta mediante `IOKit` el instante exacto en que conectas el cargador para mostrar la animación de carga rápida con el porcentaje de batería real.
- 📁 **Notch Shelf (Bandeja de Arrastrar y Soltar):**
  - Arrastra capturas, fotos o documentos directamente al notch para guardarlos temporalmente y moverlos después a otras apps.
- 📳 **Retroalimentación Háptica en Trackpad:**
  - Genera micro-pulsaciones táctiles en el Trackpad Force Touch de tu MacBook al expandirse o interactuar.
- 🧭 **Icono en la Barra de Menús (Menu Bar Item):**
  - Menú discreto para activar/desactivar, alternar expansión al pasar el cursor (hover), probar alertas y salir.

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
