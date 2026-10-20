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
2. **Relevancia (`ActivityRelevance`)**: una sola escala 0–1000. AirPods 1000 · llamada entrante y temporizador sonando 950 · llamada en curso 920 · notificación 900 · AirDrop 880 · carga/batería 860 · temporizador en su último minuto 850 · agente pidiendo permiso 820 · temporizador 800 · Claude/agentes/descargas 700 · genérico 600 · música 500 · repisa 400. Lo que pide atención suma 100.

3. **Política de presentación (`PresentationEngine`)**: quién va en el notch, en las bolitas y en la cola se decide en una función pura (`PresentationEngine.decide`), sin SwiftUI ni singletons. `ActivityCenter` traduce cada `LiveActivity` a un `PresentationCandidate` (prioridad, urgencia, inicio, si es HUD del sistema y si puede ocupar el notch) y aplica la decisión con sus animaciones. Reglas: urgentes primero, luego prioridad; con la misma gana la que se inició primero; histéresis de 3 s; el HUD de volumen/brillo tiene preferencia y tras él el notch queda limpio unos segundos.

4. **Ciclo de vida (`ActivityLifecycle`, `ActivityRelevance`)**: escala única de relevancia (0–1000); alertas por actualización (`LiveActivity.alert`), límite de 8 h, contenido obsoleto (`LiveActivity.staleDate`) y `ActivityCenter.end(id:final:dismissAfter:onRemove:)` para terminar con resumen. Las bolitas brotan y se reabsorben con `LiquidSatelliteHost` + `ActivityCenter.departingSatellites` (no con transiciones de SwiftUI: en macOS 27 no les llegaba su valor).

5. **Bolitas**: vista `NotchSatelliteBubbleView` (`NotchBolitaView`). Hasta 2 a la vista, una por lado; `PresentationEngine.assignSides` les da un lado estable (`ActivityCenter.satelliteLayout`). Swipe a lo ancho → `ActivityCenter.cycleActivities`. Clic: `AppState.bubbleTapAction` (abrir app sólo si tiene ventana en el escritorio actual, ver `ActivitySourceApp`; traer al notch; expandir). Indicadores que nunca ocupan el notch: `LiveActivity.prefersBubble`. Avisos breves que se comportan como el HUD de volumen: `LiveActivity.isSystemNotice`.

6. **Tarjetas expandidas**: `IslandExpandedTemplate` (regiones leading/trailing/center/bottom, márgenes concéntricos, alto 84–160 pt reportado con `ActivityCenter.reportExpandedContentHeight`). Sin tarjeta propia → `DefaultActivityExpandedView`. Medidas de la HIG en `IslandMetrics`.

7. **Geometría de la superficie (`SurfaceGeometry`, `Core/SurfaceGeometry.swift`)**: describe dónde vive la isla: notch físico, notch virtual (pantallas sin notch, comportamiento actual) o isla flotante (Fase B). `NotchGeometry` es un alias. `ScreenService` la calcula con `SurfaceGeometry.resolve(screens:preferredIndex:)`, que es pura.

---

## 5. Motores de Bajo Nivel y Servicios (`Sources/DynamicNotch/Services/`)

### A. Detección y Control de Música (`MusicService.swift` y `Resources/MediaRemoteBridge.swift`)
- **Apple Music y Spotify**: Se escuchan notificaciones nativas del sistema (`com.apple.Music.playerInfo` y `com.spotify.client.PlaybackStateChanged`).
- **YouTube y Navegadores Web (Safari, Chrome, Arc, Brave, Firefox)**: Se utiliza `NowPlayingService`, el cual ejecuta en segundo plano un script en Swift (`MediaRemoteBridge.swift`) que accede vía `dlopen` al framework privado `/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote`.
- **Filtro Anti-Flicker**: Para evitar que el reproductor chiquito desaparezca "de la nada", `MusicService` incluye:
  - Verificación activa por AppleScript (`isAppleMusicActuallyPlaying`, `isSpotifyActuallyPlaying`) si `MediaRemote` emite un falso positivo de pausa.
  - Debounce de 2.5 segundos para reproductores web antes de confirmar una pausa real.

### B. Espectro y Visualizador de Audio (`AudioSpectrumEngine.swift`)
- Capta el audio del sistema (process tap de Core Audio, nunca el micrófono) sólo mientras algo suena, para que las barras sigan la música. Con audio protegido (DRM) llega silencio: `SongTempoAnalyzer` y `ProceduralMotionEngine` animan las barras al tempo real de la canción.

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

### G. Integraciones del sistema (`Activities/Providers/SystemStatusActivityProvider.swift`, `DownloadsActivityProvider.swift`)
- Bloq Mayús (monitor de `flagsChanged`), red/VPN (`NWPathMonitor` + interfaz principal en `SCDynamicStore`), cámara y micrófono en uso (`kCMIODevicePropertyDeviceIsRunningSomewhere` / `kAudioDevicePropertyDeviceIsRunningSomewhere`: **sólo se consulta, nunca se abren**).
- Descargas: `Progress.addSubscriber(forFileURL:)` sobre `~/Downloads`; una sola actividad con el progreso conjunto.

### H. Pantalla completa (`FullScreenMediaMonitor.swift`)
- Señal: `AXFullScreen` de la ventana enfocada de la app al frente (en MacBook con notch la ventana "Menubar" del Window Server nunca desaparece) y, en pantallas sin notch, la ausencia de "Menubar". Se esconde el notch si algo suena o la app es de video o un navegador; al volver, `ActivityCenter.holdBareNotchThenRestore()`.
- Todo lo que consulta `CGWindowList` corre fuera del hilo principal.

---

## 6. Mecanismo de Gestos (Swipe y Arrastre)

- **Trackpad**: `Window/TrackpadGestureRecognizer.swift` (máquina de estados, deduplica eventos por timestamp) → `Window/NotchGestureDispatcher.swift`, que decide según el contexto (notch cerrado, reproductor, repisa, tarjeta, notificación, llamada).
  - Notch cerrado: deslizar hacia abajo abre; a lo ancho, si empezó sobre la isla y hay 2+ actividades entre bolitas y cola, las recorre (si no, esconde la música).
  - Abierto: hacia arriba cierra siguiendo los dedos (cierre interactivo con desenfoque sostenido); a lo ancho cambia entre reproductor y repisa.
- **Clic y arrastre con mouse**: `NotchPanel.sendEvent` (tap al notch, arrastre hacia abajo). Los clics sobre bolitas los atiende la propia bolita (`lastSatelliteTapAt` evita el doble efecto).
- **Arrastrar archivos**: `DragDetectionProbe` abre la invitación al acercarse o al entrar al rectángulo de la tarjeta; `NotchHitTestView` recibe el arrastre y marca `isShelfDragTargeted` (verde).

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

Diagnóstico por HTTP en `127.0.0.1:48123` (`AgentIPCService`):

| Ruta | Para qué |
|---|---|
| `GET /debug/activities` | actividades, principal, bolitas, obsoletas y las que se van |
| `GET /debug/hit` | zonas de clic, estado de arrastre y marco del panel |
| `GET/POST /debug/hitches` | cuadros lentos (POST reinicia) |
| `GET /debug/audio` | captura de audio y niveles |
| `GET /debug/fullscreen` | detección de pantalla completa |
| `POST /debug/toggle-notch` | abrir/cerrar el reproductor |
| `POST /debug/cycle` | como el swipe a lo ancho (`{"forward": false}` regresa) |
| `POST /debug/expand` | expandir la tarjeta de una actividad (`{"id": "..."}`; vacío cierra) |
| `POST /debug/sample-activity` | descarga de ejemplo (`{"progress": 0.4}`, `{"remove": true}`) |
| `POST /debug/appearance` | estilo en vivo (`oled`, `darkGlass`, `clearGlass`) |
| `POST /timer`, `/progress`, `/claude` | temporizador, progreso de agentes, hooks de Claude Code |

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
5. **El micrófono nunca se usa**: la captura de audio del sistema (process tap) sólo corre mientras algo suena; la cámara y el micrófono sólo se consultan con `…IsRunningSomewhere`.
6. **Transiciones de las bolitas**: en macOS 27 una transición `.modifier` no le pasa su valor a la vista; para animar entrada y salida usa estado propio (`LiquidSatelliteHost`) y conserva la vista que se va (`departingSatellites`).

## Organización de los archivos grandes (octubre 2026)

- `Views/NotchContainerView.swift`: estado, `body` y vistas de contenido. Extensiones: `+Geometry` (tamaños, radios, escala, sombras, resortes), `+Gestures` (presionar y deslizar), `+Transitions` (abrir y cerrar). Constantes de física en `Views/NotchTuning.swift`.
- `Core/AppState.swift`: ajustes persistidos y estado. Extensiones: `+Subscriptions` (reacciones a servicios), `+Mode` (compacto, hover, abrir/cerrar, alertas), `+Shelf` (repisa). Opciones de los ajustes en `Core/AppSettingsTypes.swift`.
- `Activities/ActivityCenter.swift`: publicar, quitar y repartir roles con `PresentationEngine`. Extensiones: `+Carousel` (swipe, traer al notch, la música como bolita), `+Lifecycle` (alertas, 8 h, obsoleto, resumen), `+Fusion` (bolita → notch → tarjeta).
- API pública de actividades: `Activities/PublicActivityAPI.swift` y `docs/API.md`.

## Idiomas y Atajos

- **Idiomas:** el español es el idioma base (`CFBundleDevelopmentRegion = es`). Los `Text("…")` de SwiftUI se traducen solos; los textos que llegan como `String` (filas de Ajustes, menú, avisos) pasan por `L()` (`Core/Localization.swift`). Para traducir un texto nuevo, agrega `"texto en español" = "English text";` a `Resources/en.lproj/Localizable.strings`.
- **Atajos y Siri:** `Activities/ShortcutsIntents.swift` (App Intents). `build_app.sh` compila con `-emit-const-values-path` y genera `Metadata.appintents` con `appintentsmetadataprocessor`, como Xcode.

