# Informe Técnico de Solución: Motor de Espectro de Audio en Tiempo Real & Quick Reply de WhatsApp

## 1. Diagnóstico de Causas Raíz del Espectro de Audio (`AudioSpectrumEngine.swift`)

El visualizador de 6 barras (`AudioVisualizer.swift`) y el monitor en tiempo real no seguían el ritmo real de las canciones debido a **6 fallos encadenados**:

1. **Desactivación Forzada del Tap Digital en `init()` y Caída al Oscilador de 124 BPM**:
   - `AudioSpectrumEngine.init()` sobrescribía `enableSystemAudioTap = false` en `UserDefaults` y llamaba a `teardownProcessTap()` en cada inicio de la app.
   - `AppDelegate` nunca invocaba `AudioSpectrumEngine.shared.startCapture()`.
   - Como resultado, `getMagnitudes()` caía siempre en `generateRealisticMusicMagnitudes()`, un oscilador sintético fijo a **124.0 BPM** (`let bpm: Double = 124.0`).

2. **Atenuación de `-31.86 dB` (`39.2x`) por Doble Normalización (`vDSP_HANN_NORM` + `/ Float(halfFFT)`)**:
   - En `setupAccelerate()`, se usaba `vDSP_HANN_NORM`, que en `Accelerate` multiplica la ventana por $\sqrt{\frac{8}{3N}} = 0.0255155$ para $N = 4096$ (`-31.86 dB`).
   - En la Etapa 1 del pipeline se volvía a dividir entre `Float(halfFFT)` (`2048.0`), reduciendo las magnitudes reales 39.2 veces y hundiéndolas entre `-49 dBFS` y `-75 dBFS`, por debajo del umbral del Noise Gate (`-45 dB`).

3. **Acumulación de Latencia en el Ring Buffer (`sampleBuffer`)**:
   - `accumulateAndAnalyze` añadía bloques de 512–2048 muestras pero solo retiraba `hopSize = 512` por callback, acumulando hasta `8192` muestras (~170 ms de atraso).
   - Además, una ventana Hann simétrica de 4096 muestras situaba el centro de energía 42.6 ms en el pasado.

4. **Ponderación Psicoacústica $1/f$ Insuficiente y Falta de Contraste de Transitorios (Onsets)**:
   - `pinkNoiseWeights = [1.00, 1.08, 1.18, 1.28, 1.38, 1.48]` solo compensaba `+3.4 dB` en Brilliance (6–14 kHz), cuando la caída natural por bin en música y Ruido Rosa (-3 dB/octava) a lo largo de 6.6 octavas es de `~19.8 dB`.
   - En canciones masterizadas con alta compresión, mapear únicamente el nivel dB continuo sin extraer los ataques locales (onsets) por banda mantenía las barras graves estáticas arriba y las agudas aplastadas.

5. **Lectura de un Solo Buffer en `processIncomingAudioBuffer`**:
   - Solo se leía `inputBufferList.pointee.mBuffers`, ignorando buffers adicionales en `UnsafeMutableAudioBufferListPointer`.

6. **Aplanamiento Visual en `AudioVisualizer.swift`**:
   - Elevaba todas las 6 barras a `minH` (`6.0 pt`) cuando cualquier banda superaba `0.015`, impidiendo que las bandas silenciosas descansaran en `3.5 pt`.

---

## 2. Solución Implementada

### A. `Sources/DynamicNotch/Services/AudioSpectrumEngine.swift`
- **CoreAudio Process Tap Activo por Defecto**: `enableSystemAudioTap = true` desde el arranque (`enableSystemAudioTapV2`), usando `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` con `isPrivate = true` y `muteBehavior = .unmuted`.
- **Lectura Nativa de `sampleRate` y Auto-Recuperación**: Se consulta `kAudioTapPropertyFormat` en el tap y se reconstruye automáticamente el dispositivo agregado al conmutar entre altavoces internos, AirPods, Bluetooth o HDMI.
- **Ventana `vDSP_HANN_DENORM` de 2048 Muestras en FFT de 4096 Puntos**:
  - Corrige los `-31.86 dB` de pérdida.
  - Analiza siempre las **2048 muestras más recientes** (centro de masa a solo 21.3 ms, cero cola acumulada en `sampleBuffer`) con zero-padding a 4096 puntos para mantener 11.7 Hz/bin de resolución.
- **Ponderación $1/f$ Calibrada + Extractor de Onsets por Banda**:
  - Pesos calibrados `[1.00, 1.42, 2.10, 3.10, 4.35, 5.75]`.
  - Seguidor lento por banda (`bandSlowDB[i]`) que extrae golpes de bombo, bajo, caja, voz y platos (`onsetDeltaDB`), combinando **58% nivel espectral sostenido + 48% articulación de transitorios** con compresión `tanh`.
- **Silencio Real Garantizado**:
  - `getMagnitudes()` jamás cae al oscilador de 124 BPM en modo real. Si la música se pausa o hay un silencio acústico, las barras caen limpiamente a `0.0`.

### B. `Sources/DynamicNotch/Services/SpectrumMetrics.swift`
- Presets recalibrados (`attackMs = 10 ms`, `releaseMs = 115 ms`, `noiseGateDB = -50 dB`, `spatialDiffusion = 0.06`, `includeAppAudioInTap = true`).

### C. `Sources/DynamicNotch/Views/AudioVisualizer.swift` & `AnimatedEqualizerView.swift`
- Muestreo a **60 FPS** (`1.0 / 60.0 s`) con respuesta independiente por banda desde `restingDot` (`3.5 pt`) hasta `maxH` (`18.0 pt`) y resorte rápido (`response: 0.055`).

---

## 3. Resumen de la Corrección de WhatsApp (Swipe-Down & Quick Reply)

- **`NotificationActivityProvider.swift`**: Gestiona dimensiones canónicas compacta (`396x96`) y expandida (`424x186`), pausa el auto-cierre al abrir Quick Reply y activa `setAllowsKeyInput(true)`.
- **`LiveActivityContainerView.swift` & `QuickReplyNotificationView.swift`**: Elimina el uso de `AnyView` que destruía el foco del `TextField`, quita el reset `expanded = false` en `.onAppear` y asegura el foco con `focusReplyField()`.
- **`NotchPanel.swift`**: Unifica la detección de swipe-down con trackpad (`scrollWheel`) y ratón (`leftMouseDragged`) en `sendEvent` reenviando siempre `super.sendEvent(event)`.
- **`WhatsAppWebObserverService.swift` & `MessageReplyService.swift`**: Evita falsos positivos al iterar múltiples pestañas y entrega la respuesta directamente en WhatsApp Web mediante `deliverQuickReply(message:recipient:)`.
