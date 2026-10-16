# Guía de Continuación e Implementación para Gemini 3.8
**Proyecto:** Dynamic Notch para macOS (macOS 15 Sequoia / macOS 26 Tahoe)
**Fecha:** 15 de Octubre de 2026
**Rama de Respaldo en GitHub:** `backup/pre-oct15-improvements` (commit `ee88ead`)

---

## PARTE 1: CONTEXTO DE LOS CAMBIOS RECIÉN IMPLEMENTADOS (15/OCT/2026)

Antes de iniciar la nueva tarea del **Reproductor Grande para la Pantalla de Bloqueo**, ten en cuenta todos los cambios arquitectónicos y de optimización que ya están compilados y funcionando en el repositorio:

### 1. Optimización de Rendimiento y Recursos (CPU / GPU / IPC)
- **[`Sources/DynamicNotch/DragDrop/DragDetectionProbe.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/DragDrop/DragDetectionProbe.swift)**:
  - Se eliminó el `Timer` perpetuo de 20 Hz que corría 24/7.
  - Ahora usa `startActiveMousePolling()` y `stopActiveMousePolling()` activados únicamente entre `leftMouseDown`/`leftMouseDragged` y `leftMouseUp` (**0% CPU en reposo**).
- **[`Resources/MediaRemoteBridge.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Resources/MediaRemoteBridge.swift) y [`Sources/DynamicNotch/Services/NowPlayingService.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Services/NowPlayingService.swift)**:
  - **IPC Diferencial de Carátulas**: `MediaRemoteBridge.swift` ya no codifica ni envía megabytes de Base64 en cada tick; guarda `lastSentArtworkTrackKey` y `lastSentArtworkByteCount` y solo envía `artworkBase64` cuando cambia la canción o los bytes de la imagen.
  - **Fin de la tormenta de reintentos en YouTube**: Se reemplazó la recursión infinita `asyncAfter(0.5s)` para videos sin carátula por un único `DispatchWorkItem` cancelable con un máximo de **2 reintentos por pista**.
  - **Comandos de Aleatorio y Repetición**: Se agregaron los comandos `6` (`MRMediaRemoteSendCommand(25)` para Shuffle) y `7` (`MRMediaRemoteSendCommand(26)` para Repeat), expuestos en `NowPlayingService.shared.toggleShuffle()` y `toggleRepeat()`.
  - **Nota importante para `macOS 15.4+ / macOS 26`**: `NowPlayingService` lanza `/usr/bin/swift` ejecutando `MediaRemoteBridge.swift` porque el binario firmado por Apple (`/usr/bin/swift`) conserva el entitlement privado para leer `MediaRemote.framework`, algo que Apple bloqueó para procesos de terceros en macOS 15.4+.
- **[`Sources/DynamicNotch/Services/WhatsAppWebObserverService.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Services/WhatsAppWebObserverService.swift)**:
  - Ahora es `ObservableObject` con `isEnabled` y `pollInterval` persistidos en `UserDefaults`.
  - Precompila y guarda en caché las instancias `NSAppleScript` por navegador en una cola serial dedicada en lugar de recompilar código fuente AppleScript cada 2.5 s.
- **[`Sources/DynamicNotch/Services/CallDetectorService.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Services/CallDetectorService.swift)**:
  - Añadido `isEnabled` persistido, intervalo subido a `3.0s` con `tolerance = 0.6`, guardia `isScanningDiscord` y límite duro en el recorrido `AXUIElement` (`depth <= 10`, `visitedNodes <= 150`).
- **[`Sources/DynamicNotch/Views/AudioVisualizer.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Views/AudioVisualizer.swift)**:
  - Añadido `ArtworkGradientCache` indexado por `ObjectIdentifier(nsImage)` y soporte para `AppState.shared.visualizerColorStyle` (`.adaptive`, `.vibrant`, `.pureWhite`).

### 2. Corrección de Desaparición del Mini-Player y Nuevo Hover Sostenido con Sombra Fija
- **[`Sources/DynamicNotch/Core/AppState.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Core/AppState.swift)**:
  - Se creó `reconcileCompactMode()` para garantizar que siempre que `musicService.hasActiveMusic && showCompactWhenPlaying` sea verdadero y no haya una Live Activity bloqueando, el Notch regrese a `.compact` y nunca quede atrapado en `.minimal`.
  - Se reemplazó el antiguo espasmo de `0.18s` (`triggerHeartbeat`) por `setHoverState(_ hovering: Bool)`: mientras el cursor permanece sobre el Notch, la píldora se expande suavemente (`hoverScaleAmount`, por defecto `1.035`) con sombra profunda y fija (`hoverShadowIntensity`), regresando a su tamaño normal únicamente cuando el cursor sale.
- **[`Sources/DynamicNotch/Activities/ActivityCenter.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Activities/ActivityCenter.swift)**:
  - `remove(id:)` y `dismissWithAnimation(id:)` limpian `isHoldingBareNotch` y llaman a `AppState.shared.reconcileCompactMode()`.
- **[`Sources/DynamicNotch/Views/NotchContainerView.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Views/NotchContainerView.swift)**:
  - Se activó la sombra multicapa estilo Dynamic Island también cuando `effectiveAppearanceMode == .clearGlass` en modo compacto/colapsado.
  - Se corrigió `performExpand()` y `performCollapse()` para que visitar la pestaña `.shelf` nunca atrape `activeTab` ni oculte el mini-player al cerrar.

### 3. Controles de Reproducción, AirPods 3D PBR, Banco de Mini-Apps y Panel de Ajustes
- **[`Sources/DynamicNotch/Views/PlayerControlButton.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Views/PlayerControlButton.swift)** y **[`Sources/DynamicNotch/Views/NotchPlayerView.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Views/NotchPlayerView.swift)**:
  - Botones de control con cápsula translúcida en hover, borde especular, onda expansiva e indicador luminoso inferior (`isActive`, `activeTint`) para Shuffle, Repeat (`MusicRepeatMode`: `.off`, `.all`, `.one`) y AirPlay.
  - Iconos opcionales de acceso rápido en la esquina superior derecha del Notch (`pinTimerMiniAppInNotch`, `pinAudioMonitorMiniAppInNotch`) que abren overlays integrados (`activeMiniAppOverlay`) sin añadir una tercera página al paginado principal (`● ○`).
- **[`Sources/DynamicNotch/Activities/Templates/ActivityAirPodsPillView.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Activities/Templates/ActivityAirPodsPillView.swift)**:
  - Escena 3D SceneKit con materiales PBR (`ceramicWhite`, `siliconeTip`, `blackGrill`, `chromeRing`), iluminación de estudio de 3 puntos y `rendersContinuously = false` al terminar el giro (**0% GPU en reposo**).
- **[`Sources/DynamicNotch/Activities/Providers/TimerActivityProvider.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Activities/Providers/TimerActivityProvider.swift)** y **[`Sources/DynamicNotch/Activities/Templates/TimerCardView.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Activities/Templates/TimerCardView.swift)**:
  - Soporte completo para **Temporizador** (presets `1m`, `5m`, `10m`, `15m`, `25m Pomodoro`) y **Cronómetro con vueltas (`StopwatchLap`)**, además de `TimerMiniAppOverlayView` y `AudioMonitorMiniAppOverlayView`.
- **[`Sources/DynamicNotch/Views/Settings/SettingsView.swift`](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/Sources/DynamicNotch/Views/Settings/SettingsView.swift)**:
  - Ampliado a 6 pestañas (`Apariencia`, `Gestos`, `Drag & Drop`, `Multimedia`, `Mini-Apps`, `Sistema`).

---

## PARTE 2: PLAN DETALLADO PARA GEMINI 3.8 — REPRODUCTOR GRANDE EN LA PANTALLA DE BLOQUEO DE MAC

### Objetivo General
Cuando el Mac esté bloqueado y haya música o audio reproduciéndose, mostrar un reproductor grande, minimalista y elegante (`~420 pt` de ancho), centrado horizontalmente debajo del reloj de la pantalla de bloqueo de **macOS Tahoe (macOS 26) / macOS 15+**, con estética nativa Liquid Glass Regular. Al desbloquear, debe desaparecer de inmediato con una animación suave (`fade + blur`) sin dejar ventanas fantasma ni retrasar el desbloqueo.

---

### PASO 0: PRUEBA DE VIABILIDAD (EJECUTAR PRIMERO, ANTES DE DISEÑAR LA UI)

#### 0.1. Cómo dibujan apps sobre la pantalla de bloqueo en macOS (SkyLight + AppKit Private SPIs)
macOS bloquea la pantalla levantando un escudo de nivel alto (`CGShieldingWindowLevel()`, típicamente nivel `1000` o superior gestionado por `loginwindow` / `LockScreen.app`) y cambiando a un **Space de sistema de bloqueo** donde las ventanas normales de usuario no se renderizan.

Para que una ventana de un proceso de usuario aparezca sobre la pantalla de bloqueo en macOS 15 / macOS 26 (Tahoe), se requiere combinar **dos mecanismos privados**:

1. **Propiedad de `NSWindow` / `NSPanel`**:
   - `window.canBecomeVisibleWithoutLogin = true` (API pública/semipública de AppKit desde OS X 10.5+, crítica para que WindowServer permita rasterizar la ventana cuando la sesión está bloqueada).
   - `window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`
   - `window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)` (o nivel absoluto `1002` / `2000` por encima del escudo).
   - `window.sharingType = .readOnly` (o `.none` según pruebas).

2. **SkyLight Unmanaged Space con Nivel Absoluto Alto (`SkyLight.framework`)**:
   En macOS 13–26, el `LockScreen` crea su propio `CGSSpace` de nivel alto (típicamente `SLSSpaceAbsoluteLevel` >= `300` o `400`). Incluso con `canBecomeVisibleWithoutLogin = true` y `.canJoinAllSpaces`, WindowServer a veces oculta las ventanas del Space de usuario durante el bloqueo a menos que la ventana se asigne a un **Space dedicado creado vía SkyLight** con un nivel absoluto superior al del Lock Screen:
   - Ruta del framework: `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`
   - Símbolos C privados a cargar **exclusivamente mediante `dlopen` + `dlsym`** (para nunca causar crash de enlazado dinámico si Apple cambia un símbolo):
     ```swift
     typealias SLSMainConnectionIDFunc = @convention(c) () -> Int32
     typealias SLSSpaceCreateFunc = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
     typealias SLSSpaceDestroyFunc = @convention(c) (Int32, UInt64) -> Int32
     typealias SLSSpaceSetAbsoluteLevelFunc = @convention(c) (Int32, UInt64, Int32) -> Int32
     typealias SLSShowSpacesFunc = @convention(c) (Int32, CFArray) -> Int32
     typealias SLSHideSpacesFunc = @convention(c) (Int32, CFArray) -> Int32
     typealias SLSSpaceAddWindowsAndRemoveFromSpacesFunc = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32
     ```
   - **Flujo SkyLight al bloquear**:
     1. Obtener `cid = SLSMainConnectionID()`.
     2. Crear un space `spaceID = SLSSpaceCreate(cid, 1, nil)` (o reutilizar uno único durante la vida de la sesión de bloqueo).
     3. Asignar nivel absoluto alto: `SLSSpaceSetAbsoluteLevel(cid, spaceID, 400)` (probar niveles `300`, `400` y `500`; el reloj y fondo del LockScreen suelen estar en `200–300`).
     4. Mostrar el space: `SLSShowSpaces(cid, [NSNumber(value: spaceID)] as CFArray)`.
     5. Mover el `windowNumber` del `LockScreenPanel` a ese space:
        `SLSSpaceAddWindowsAndRemoveFromSpaces(cid, spaceID, [NSNumber(value: panel.windowNumber)] as CFArray, 7)`.
   - **Flujo SkyLight al desbloquear (Cero Ventanas Fantasma)**:
     1. Ordenar `panel.orderOut(nil)` inmediatamente.
     2. Llamar `SLSHideSpaces(cid, [NSNumber(value: spaceID)] as CFArray)`.
     3. Llamar `SLSSpaceDestroy(cid, spaceID)` y poner `spaceID = 0`.

#### 0.2. Detección Confiable de Bloqueo y Desbloqueo
Suscribirse en `DistributedNotificationCenter.default()` a:
- `"com.apple.screenIsLocked"` → Estado pasa a bloqueado (`isScreenLocked = true`).
- `"com.apple.screenIsUnlocked"` → Estado pasa inmediatamente a desbloqueado (`isScreenLocked = false`).
Además, suscribirse en `NSWorkspace.shared.notificationCenter` a:
- `NSWorkspace.screensDidSleepNotification` (pausar renderizado/animaciones cuando la pantalla física se apaga para ahorrar batería).
- `NSWorkspace.screensDidWakeNotification` (revalidar si sigue bloqueado y si hay música activa).
- `NSWorkspace.sessionDidResignActiveNotification` (cambio rápido de usuario).

#### 0.3. Riesgos y Limitaciones que debes reportar al usuario en el Paso 0
1. **Imposibilidad de distribuir en Mac App Store**: El uso de `SkyLight.framework` (`SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, etc.) y niveles sobre `CGShieldingWindowLevel()` está prohibido por las reglas de revisión de App Store y el App Sandbox de la tienda. Solo es viable para distribución directa (DMG / Homebrew / notarización fuera de la tienda).
2. **Riesgo de rotura entre versiones de macOS**: Apple puede cambiar los valores de `SLSSpaceAbsoluteLevel` del `LockScreen` en actualizaciones menores de macOS 26. Por ello es obligatorio cargar los símbolos con `dlsym` y tener un **Kill Switch** automático si alguno devuelve `nil` o código de error.
3. **Prueba inicial obligatoria**: Antes de construir `LockScreenPlayerView`, crea un prototipo mínimo en `LockScreenSkyLightBridge.swift` que muestre un rectángulo de prueba (`420 x 200 pt`, color azul translúcido con texto `"PRUEBA LOCK SCREEN DYNAMIC NOTCH"`) al recibir `"com.apple.screenIsLocked"` (y con un botón en Ajustes que lo active tras 3 segundos para que el usuario bloquee con `Cmd+Ctrl+Q`) y verifica con el usuario que se ve debajo del reloj y desaparece limpio al desbloquear.

---

### PASO 1: MÁQUINA DE ESTADOS (`LockScreenManager.swift`)

Crear `Sources/DynamicNotch/LockScreen/LockScreenManager.swift` como `ObservableObject` singleton (`LockScreenManager.shared`):

1. **Estados (`LockScreenState`)**:
   - `.unlocked`: Nada en pantalla. `LockScreenPanel` oculto (`orderOut`) y `SLSSpace` destruido.
   - `.lockedIdle`: Mac bloqueado pero sin reproducción activa (`!musicService.currentTrack.isPlaying` y fuera de ventana de gracia). Nada visible.
   - `.lockedPlaying`: Mac bloqueado y reproduciendo. Aparece el reproductor con **fade + escala `0.96 → 1.0` + blur de entrada (`radius: 12 → 0`) en `~350 ms`**.
   - `.lockedPaused(remainingSeconds: Int)`: Mac bloqueado y música recién pausada. Permanece visible durante un tiempo configurable (`lockScreenPauseTimeoutSeconds`, por defecto `30 s`). Si no se reanuda al agotarse el contador, transiciona a `.lockedIdle` desvaneciéndose suavemente. Si se reanuda (`isPlaying == true`), cancela el timer y vuelve a `.lockedPlaying`.
   - `.transitioningOut`: Al recibir `"com.apple.screenIsUnlocked"`, ejecuta salida rápida (`120–150 ms` con `fade + blur`) o `orderOut` inmediato para no retrasar ni un milisegundo la animación de desbloqueo de Touch ID / contraseña.

2. **Cambio de canción (Estado 5)**:
   - Cuando cambia `musicService.currentTrack.title` o `artist` estando en `.lockedPlaying`:
   - **NO** recrear ni reiniciar la ventana.
   - Realizar **crossfade** de la carátula (`id(track.title + track.artist)` con `.transition(.opacity.animation(.easeInOut(duration: 0.35)))`) y deslizamiento horizontal suave + fade para título y artista (`.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))`).

---

### PASO 2: DISEÑO VISUAL NATIVO ESTILO macOS TAHOE (`LockScreenPlayerView.swift`)

Crear `Sources/DynamicNotch/LockScreen/LockScreenPlayerView.swift` siguiendo estrictamente estas especificaciones:

1. **Geometría y Posicionamiento bajo el Reloj**:
   - **Ancho de tarjeta**: `420 pt` fijos.
   - **Radio de esquina de tarjeta**: `36 pt` (`RoundedRectangle(cornerRadius: 36, style: .continuous)`), concéntrico con el padding interno de `24 pt` y la carátula de radio `20–24 pt`.
   - **Posición vertical bajo el reloj del sistema**:
     - En macOS Sequoia / Tahoe, el reloj grande de la pantalla de bloqueo ocupa el tercio superior (desde `~12%` hasta `~32%` desde el borde superior de la pantalla).
     - Posicionar el borde superior de la tarjeta a `screenFrame.maxY - (screenFrame.height * 0.36) + userVerticalOffset` (donde `userVerticalOffset` es un slider en Ajustes de `-160 pt` a `+160 pt`, por defecto `0 pt`), asegurando que nunca solape el reloj superior ni el avatar/campo de contraseña inferior (`~140 pt` desde el borde inferior).
     - En pantallas de menor altura (ej. MacBook Air 13" `1440x900` vs MacBook Pro 16" o monitores 4K), escalar ligeramente el tamaño de la carátula (`min(280, screenFrame.height * 0.28)`) para que jamás toque el reloj ni el campo de Touch ID/contraseña.

2. **Material Liquid Glass Regular (Sin Cristal sobre Cristal)**:
   - La tarjeta exterior usa **Liquid Glass Regular**:
     - En `macOS 26.0+`: `GlassEffectContainer` con `.glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 36, style: .continuous))` + borde especular sutil de `0.8 pt`.
     - Fallback en `macOS 15`: `VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow, state: .active)` con clip `RoundedRectangle(cornerRadius: 36, style: .continuous)`.
   - **Regla de Oro**: El contenido interior (botones, barra de progreso, slider de volumen) **NO** debe usar `glassEffect` ni `NSVisualEffectView` (cero cristal sobre cristal); solo opacidades puras de blanco (`.primary`, `.secondary`, `Color.white.opacity(...)`).
   - **Accesibilidad**:
     - Si `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` está activo: usar fondo sólido oscuro (`Color(red: 0.08, green: 0.08, blue: 0.10)`).
     - Si `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` está activo: desactivar la escala `0.96 → 1.0` y los desplazamientos de texto, usando únicamente fundidos de opacidad (`.opacity`).
     - Si `accessibilityDisplayShouldIncreaseContrast` está activo: incrementar el borde a `Color.white.opacity(0.45)` con grosor `1.5 pt` y textos secundarios a `0.85` de opacidad.

3. **Jerarquía Interna (De arriba a abajo, rejilla de 4/8 pt, padding interno 24 pt)**:
   - **Carátula Grande (`~280 x 280 pt`, o `56 x 56 pt` si está en modo privacidad)**:
     - `RoundedRectangle(cornerRadius: 24, style: .continuous)`
     - Sombra suave: `.shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 10)`
     - **Halo Opcional (apagado por defecto)**: Toggle `lockScreenShowArtworkHalo` (default `false`). Si el usuario lo activa, coloca detrás de la carátula un `Circle()` con el color dominante (`ArtworkGradientCache.colors(for: track.artwork).top`) con `.blur(radius: 40)` y `.opacity(0.28)`.
   - **Espacio**: `20 pt`
   - **Título y Artista**:
     - Alineación **centrada** (la más limpia y equilibrada bajo el reloj centrado de macOS Tahoe y con una carátula cuadrada centrada de 280 pt; puedes ofrecer un toggle opcional Centrado/Izquierda en Ajustes con Centrado por defecto).
     - **Título**: `.font(.system(size: 22, weight: .semibold))`, `.foregroundStyle(.primary)`, `.lineLimit(1)` (o `MarqueeText` si excede el ancho).
     - **Artista**: `.font(.system(size: 17, weight: .regular))`, `.foregroundStyle(.secondary)`, `.lineLimit(1)`.
   - **Espacio**: `16 pt`
   - **Barra de Progreso Fina y Tiempos**:
     - Barra interactiva (`Capsule()` de `4 pt` de alto en reposo, `6 pt` al arrastrar) que llama a `musicService.seek(to:)`.
     - Debajo de los extremos de la barra: tiempo transcurrido a la izquierda (`0:42`) y tiempo restante a la derecha (`-2:18`) con `.font(.system(size: 12, weight: .medium))`, `.monospacedDigit()`, `.foregroundStyle(.secondary)`.
   - **Espacio**: `16 pt`
   - **Controles Multimedia Grandes y Centrados (`HStack(spacing: 40)`)**:
     - **Anterior**: `Image(systemName: "backward.fill")`, `.font(.system(size: 26, weight: .medium))` → `musicService.previousTrack()`.
     - **Play / Pausa (el más grande)**: `Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")`, `.font(.system(size: 38, weight: .semibold))` → `musicService.togglePlayPause()`.
     - **Siguiente**: `Image(systemName: "forward.fill")`, `.font(.system(size: 26, weight: .medium))` → `musicService.nextTrack()`.
   - **Deslizador de Volumen Discreto Opcional (`lockScreenShowVolumeSlider`, default `true`)**:
     - `HStack(spacing: 10)` con `speaker.fill` (`11 pt`, `.tertiary`), barra fina de `4 pt` conectada a `AudioDeviceService.shared.setVolume(_:)`, y `speaker.wave.3.fill` (`11 pt`, `.tertiary`).

---

### PASO 3: INTERACCIÓN, SEGURIDAD Y PRIVACIDAD

1. **Seguridad Estricta en la Pantalla de Bloqueo (`LockScreenPanel.swift`)**:
   - Subclase de `NSPanel` con `styleMask: [.borderless, .nonactivatingPanel]`.
   - `override var canBecomeKey: Bool { false }` y `override var canBecomeMain: Bool { false }` — **NUNCA debe robar el foco del teclado** para que el usuario pueda escribir su contraseña de macOS en cualquier momento sin hacer clic fuera.
   - **Prohibido abrir aplicaciones**: A diferencia de `NotchPlayerView`, hacer clic en la carátula en `LockScreenPlayerView` **NO** debe llamar a `musicService.openMusicApp()` ni ejecutar ningún `NSWorkspace.shared.open(...)`. Tampoco debe haber menús contextuales ni botones de ajustes del sistema. Únicamente los 5 controles multimedia (`previousTrack`, `togglePlayPause`, `nextTrack`, `seek`, `setVolume`).

2. **Modo de Privacidad ("Ocultar detalles en pantalla bloqueada")**:
   - Propiedad en `AppState`: `lockScreenHideMediaDetails: Bool` (persistida en `UserDefaults`).
   - Cuando está activa:
     - No muestra la carátula real (muestra un icono minimalista `music.note` sobre un recuadro neutro translúcido compacto),
     - Sustituye el título por `"Reproduciendo audio"` y el artista por `"Contenido oculto en pantalla bloqueada"`.
     - Mantiene operativos la barra de progreso y los botones de reproducción.
   - **Pregunta en el Primer Uso (`hasPromptedLockScreenPrivacy`)**:
     - La primera vez que el usuario activa el Reproductor de Pantalla de Bloqueo (o la primera vez que se detecta reproducción al bloquear), mostrar un diálogo/banner limpio preguntando si desea **Mostrar carátula y título en la pantalla bloqueada** o **Ocultar detalles por privacidad**, guardando `hasPromptedLockScreenPrivacy = true`.

3. **Kill Switch Automático**:
   - Si `LockScreenSkyLightBridge.shared.isSupported` es `false` (por ejemplo, si `dlsym` no encuentra los símbolos de `SkyLight` en una versión futura de macOS, o si la geometría de `NSScreen.main` es inválida), desactivar automáticamente `enableLockScreenPlayer = false` y mostrar un aviso claro en la pestaña Multimedia/Sistema de `SettingsView`.

---

### PASO 4: MULTIPANTALLA, CASOS BORDE Y CERO FUGAS DE MEMORIA

1. **Multipantalla**:
   - Por defecto, mostrar el reproductor únicamente en la pantalla principal (`NSScreen.screens.first`).
   - Añadir toggle en Ajustes: `Mostrar en todas las pantallas al bloquear` (`lockScreenShowOnAllDisplays`, default `false`).
   - Escuchar `NSApplication.didChangeScreenParametersNotification` para reposicionar o cerrar paneles si se conecta/desconecta un monitor externo o se cierra la tapa (modo clamshell).
2. **Cero Fugas tras 100 Ciclos de Bloqueo/Desbloqueo**:
   - Reutilizar una única instancia de `LockScreenPanel` (o destruir explícitamente el `SLSSpace` en cada desbloqueo verificando que `SLSSpaceDestroy` se llame siempre en un bloque `defer` / `cleanup()`).
   - Cuando la pantalla entra en reposo (`NSWorkspace.screensDidSleepNotification`), pausar cualquier `TimelineView` o `Timer` de UI del Lock Screen Player hasta `screensDidWakeNotification`.

---

### PASO 5: PANEL DE DEBUG Y SIMULADOR (`LockScreenDebugWindow.swift`)

Crear `Sources/DynamicNotch/LockScreen/LockScreenDebugWindow.swift` accesible desde `SettingsView` (pestaña `Multimedia`):
- Permite probar el reproductor en pantalla **sin tener que bloquear el Mac cada vez**:
  - Botón: **Simular Bloqueo (`screenIsLocked`)** / **Simular Desbloqueo (`screenIsUnlocked`)**
  - Botón: **Simular Reproducción / Pausa (con cuenta atrás de 30 s visible)**
  - Botón: **Simular Cambio de Canción (Crossfade + Slide)**
  - Toggle en vivo: **Modo Privacidad (Ocultar detalles)**
  - Slider en vivo: **Desfase Vertical bajo el reloj (`-160 pt ... +160 pt`)**
  - Botón: **Prueba Real de 5 Segundos (Activa el Space SkyLight real para que bloquees con `Cmd+Ctrl+Q` y se cierre solo a los 10 s por seguridad)**.
  - Indicador de diagnóstico del **Kill Switch** (`SkyLight symbols loaded: ✅/❌`, `Active Space ID`, `Window Level`).
