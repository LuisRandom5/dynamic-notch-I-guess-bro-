# Dynamic Notch — Architecture, Engines & AI Handover Guide

> **Documento de Contexto y Arquitectura Técnica para Modelos de Inteligencia Artificial (Claude, ChatGPT, Gemini, Cursor, Codex).**  
> Si eres un modelo de lenguaje analizando este repositorio por primera vez, lee atentamente este documento para entender la arquitectura completa, el árbol de componentes, los motores de bajo nivel de macOS y las reglas de diseño antes de modificar cualquier línea de código.

---

## 1. Visión General del Proyecto

- **Nombre**: Dynamic Notch (macOS)
- **Objetivo**: Recrear de manera hiperrealista y nativa la experiencia de la **Dynamic Island** de Apple, integrada directamente en la muesca física (notch) de MacBook Pro / MacBook Air (Apple Silicon y pantallas con o sin muesca).
- **Stack Técnico**:
  - **Swift 5.9 / Swift 6** nativo compilado con Swift Package Manager (`Package.swift`).
  - **AppKit + SwiftUI híbrido**: Ventana flotante `NSPanel` a nivel de sistema que aloja vistas reactivas SwiftUI (`NotchContainerView`).
  - **Sin dependencias pesadas de terceros**: Todo está construido usando APIs de bajo nivel de macOS (`CoreGraphics`, `MediaRemote`, `SceneKit`, `IOBluetooth`, `Contacts`, `TelephonyUtilities`, `AVFoundation`).

---

## 2. Jerarquía de Ventanas y Sistema de Hit-Testing (Crítico)

En macOS, colocar una ventana flotante sobre el notch sin interferir con la barra de menú nativa ni con las demás aplicaciones requiere una arquitectura muy precisa:

### Componentes Principales (`Sources/DynamicNotch/Window/`):
1. **`NotchPanel` (`NSPanel`)**:
   - `level = .statusWindow` o `.popUpMenu` (se sitúa por encima de todas las ventanas normales y de la barra de menú).
   - `styleMask = [.borderless, .nonactivatingPanel]`.
   - `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`.
   - `allowsKeyInput = true` únicamente cuando el cuadro de respuesta rápida (`QuickReplyNotificationView`) está enfocado para escribir.
   - **Manejo Central de Eventos (`sendEvent`)**: En `NotchPanel.sendEvent(_ event: NSEvent)`, todos los eventos de la ventana pasan primero por aquí antes de distribuirse a SwiftUI. Aquí se intercepta el **swipe hacia abajo (scrollWheel y drag down)** para abrir respuestas rápidas de manera 100% infalible.

2. **`NotchHitTestView` (`NSView`)**:
   - Es el `contentView` de `NotchPanel`.
   - **`hitTest(_ point: NSPoint)` dinámico**: No cubre toda la pantalla. Solo devuelve `self` o la jerarquía de SwiftUI dentro del área calculada por `hitAreaRect`. Todo lo que esté fuera devuelve `nil`, permitiendo hacer click transparente en la barra de menú y en otras apps de macOS.
   - Maneja el arrastre de archivos desde el Finder (`NSDraggingDestination`).

3. **`NotchWindowManager`**:
   - Singleton responsable de recalcular las dimensiones de la ventana y el área de contacto (`updateHitAreaForCurrentState`) según el estado actual (notch en reposo, minirreproductor con alas, menú expandido, bandeja o notificación activa).

---

## 3. Máquina de Estados y Modos (`NotchMode`)

Ubicación: `Sources/DynamicNotch/Core/AppState.swift`

El notch se rige por un autómata de estados:
- **`.idle`**: Reposo puro. Cubre exactamente las dimensiones del hardware de la cámara (por ejemplo, 182x33 pt). Si no hay música ni archivos, descansa aquí.
- **`.compact`**: Modo minirreproductor de dos alas simétricas:
  - **Ala izquierda (Leading)**: Carátula del álbum con rotación 3D al cambiar de pista.
  - **Área central**: Despeje exacto del sensor de la cámara física.
  - **Ala derecha (Trailing)**: Visualizador de audio reactivo (`AudioVisualizer`) y/o badge de archivos.
  - **Regla de oro**: Cuando hay música sonando, el modo en reposo es `.compact`. Al pausar, se retiene durante 30 segundos antes de colapsar a `.idle`.
- **`.expanded`**: Reproductor extendido a pantalla completa (ancho 430 pt, alto 196 pt) con portada ampliada, barra de progreso interactiva (scrubber), controles de transporte, toggle de reproducción aleatoria y control de volumen.
- **`.shelf`**: Bandeja o repisa para soltar archivos (Drag & Drop, 204 pt de altura).

---

## 4. Sistema de Live Activities (`ActivityCenter`)

Ubicación: `Sources/DynamicNotch/Activities/`

`ActivityCenter.shared` gestiona actividades flotantes con colas de prioridad:
1. **Estilos de Actividad (`LiveActivityStyle`)**:
   - **`.pill`**: Mensajes cortos estilo cápsula (silencio, estado).
   - **`.sliderPill`**: HUDs interactivos con barra deslizante horizontal (HUD de volumen).
   - **`.airpodsPill`**: Conexión de AirPods con modelo 3D fotorrealista en SceneKit (`AirPodsSceneView`).
   - **`.card`**: Tarjetas de contenido enriquecido (Notificaciones interactivas de WhatsApp Web, FaceTime, llamadas telefónicas).
2. **Prioridades**:
   - `100`: Llamadas entrantes (`CallDetectorService`).
   - `90`: AirPods conectados / desconectados (`AirPodsActivityProvider`).
   - `85`: Notificaciones interactivas con Quick Reply (`NotificationActivityProvider`).
   - `70`: HUD de volumen.

3. **Política de presentación (`PresentationEngine`)**: quién va en el notch, en las bolitas y en la cola se decide en una función pura (`PresentationEngine.decide`), sin SwiftUI ni singletons. `ActivityCenter` traduce cada `LiveActivity` a un `PresentationCandidate` (prioridad, urgencia, inicio, si es HUD del sistema y si puede ocupar el notch) y aplica la decisión con sus animaciones. Reglas: urgentes primero, luego prioridad; con la misma gana la que se inició primero; histéresis de 3 s; el HUD de volumen/brillo tiene preferencia y tras él el notch queda limpio unos segundos.

4. **Geometría de la superficie (`SurfaceGeometry`, `Core/SurfaceGeometry.swift`)**: describe dónde vive la isla: notch físico, notch virtual (pantallas sin notch, comportamiento actual) o isla flotante (Fase B). `NotchGeometry` es un alias. `ScreenService` la calcula con `SurfaceGeometry.resolve(screens:preferredIndex:)`, que es pura.

---

## 5. Motores de Bajo Nivel y Servicios (`Sources/DynamicNotch/Services/`)

### A. Detección y Control de Música (`MusicService.swift` y `Resources/MediaRemoteBridge.swift`)
- **Apple Music y Spotify**: Se escuchan notificaciones nativas del sistema (`com.apple.Music.playerInfo` y `com.spotify.client.PlaybackStateChanged`).
- **YouTube y Navegadores Web (Safari, Chrome, Arc, Brave, Firefox)**: Se utiliza `NowPlayingService`, el cual ejecuta en segundo plano un script en Swift (`MediaRemoteBridge.swift`) que accede vía `dlopen` al framework privado `/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote`.
- **Filtro Anti-Flicker**: Para evitar que el reproductor chiquito desaparezca "de la nada", `MusicService` incluye:
  - Verificación activa por AppleScript (`isAppleMusicActuallyPlaying`, `isSpotifyActuallyPlaying`) si `MediaRemote` emite un falso positivo de pausa.
  - Debounce de 2.5 segundos para reproductores web antes de confirmar una pausa real.

### B. Espectro y Visualizador de Audio (`AudioSpectrumEngine.swift`)
- Monitorea el flujo de audio del sistema o micrófono para generar las barras reactivas del visualizador cuando la música está sonando.

### C. Intercepción de Volumen con Sonido (`VolumeInterceptorService.swift`)
- Utiliza `CGEventTap` a nivel de sesión HID para capturar las pulsaciones de las teclas de subir/bajar volumen de macOS y reproducir el sonido nativo de confirmación (`AudioServicesPlaySystemSound(1001)`).

### D. Bandeja de Archivos (`ShelfStorageService.swift` y `DragDetectionProbe.swift`)
- Permite arrastrar archivos de macOS y "soltarlos" en el notch.
- Los archivos se respaldan en `~/Library/Application Support/DynamicNotch/Shelf/`.
- Permite arrastrarlos hacia afuera hacia el escritorio o cualquier otra aplicación mediante `NSItemProvider`.

### E. WhatsApp Web Observer (`WhatsAppWebObserverService.swift`)
- Lee notificaciones de WhatsApp Web en Safari y Google Chrome para emitir alertas enriquecidas sin requerir la API comercial de Meta ni la aplicación de escritorio de WhatsApp.
- Consume avatares de la libreta de contactos (`ContactLookupService.swift`) mediante el framework `Contacts`.

### F. Respuesta Rápida (`MessageReplyService.swift` y `QuickReplyNotificationView.swift`)
- Permite escribir y despachar respuestas directamente desde el notch mediante scripts AppleScript dirigidos a la pestaña activa de WhatsApp Web, sin desenfocar la aplicación actual.

---

## 6. Mecanismo de Gestos (Swipe y Arrastre)

Los gestos en macOS tienen dos naturalezas:
1. **Swipe con Trackpad (Dos dedos)**: Se emite como un evento `NSEvent.type == .scrollWheel`.
   - `rawDeltaY > 0` o `fingerDeltaY > 0`: Dedos deslizándose hacia abajo (hacia el usuario).
   - Se intercepta en `NotchPanel.sendEvent` para disparar `NotificationActivityProvider.shared.expandQuickReply()`.
2. **Arrastre con Click (Mouse Drag)**:
   - `leftMouseDown` registra el punto de inicio `y`.
   - `leftMouseDragged` con `deltaY < -8` (coordenadas de pantalla invertidas de macOS) dispara `expandQuickReply()`.
3. **Swipe hacia arriba**:
   - `deltaY > 15` o `scrollWheel` hacia arriba contrae o descarta la notificación.

---

## 7. Compilación, Empaquetado y Ejecución

El proyecto cuenta con un script de compilación automatizado:

```bash
# Compilar y empaquetar la aplicación
./scripts/build_app.sh
```

El script realiza lo siguiente:
1. Ejecuta `swift build -c release`.
2. Crea el paquete de aplicación `DynamicNotch.app/Contents/MacOS/DynamicNotch`.
3. Copia los recursos de `Resources/` a `DynamicNotch.app/Contents/Resources/`.
4. Inyecta el `Info.plist` con permisos de accesibilidad, eventos de Apple, micrófono y automatización.
5. Firma localmente la aplicación con `codesign` estable.

Pruebas unitarias de la lógica pura (`Tests/DynamicNotchTests`, framework Testing):
```bash
./scripts/test.sh
```
Usa el toolchain de Xcode (`DEVELOPER_DIR`), porque las Command Line Tools no traen Testing, y compila en `~/Library/Caches/DynamicNotchTests`.

Para ejecutar en segundo plano (daemon):
```bash
killall -9 DynamicNotch 2>/dev/null || true
./DynamicNotch.app/Contents/MacOS/DynamicNotch &
```

---

## 8. Reglas de Oro para Nuevos Modelos de IA

1. **Nunca rompas la ventana flotante**: No cambies `NotchPanel` a `NSWindow` estándar con barra de título. El panel debe ser transparente y sin bordes.
2. **Cuidado con los hilos**: Todo cambio a `@Published` en `AppState`, `MusicService`, `ActivityCenter` y `NotificationActivityProvider` DEBE ocurrir en el hilo principal (`DispatchQueue.main.async`).
3. **Conserva `MediaRemoteBridge.swift`**: Este script es copiado al bundle en `Contents/Resources/`. Si modificas la lógica de detección universal de YouTube/navegadores, actualiza tanto `Resources/MediaRemoteBridge.swift` como la versión empaquetada.
4. **Respeta los resortes de Apple**: Las animaciones usan `AnimationSpeedManager.shared.spring(response:dampingFraction:)`. No uses animaciones lineales o temporizadas fijas (`.linear`, `.easeInOut`) para las formas principales del notch; deben sentirse elásticas y físicas.
