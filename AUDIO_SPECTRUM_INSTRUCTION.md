# Instructivo Técnico: Arquitectura, Metodología y Estado Actual del Espectro Reactivo de Audio (Dynamic Notch)

> **Documento preparado para**: Modelo Gemini 4.0  
> **Objetivo**: Proporcionar un diagnóstico técnico completo, arquitectura detallada, metodología matemática/DSP y estado del sistema de barras reactivas al audio en Dynamic Notch para su rediseño e implementación real.  
> **Estado del Módulo**: ❌ **No funcional en audio real** (las barras reflejan valores sintéticos desfasados y no siguen el ritmo de la música reproducida).

---

## 1. Resumen Ejecutivo del Problema

En la interfaz de **Dynamic Notch** (específicamente en el reproductor expandido `NotchPlayerView` y en la cápsula compacta `NotchCompactView`), existe un visualizador de 6 barras verticales (`AudioVisualizer.swift`) diseñado para moverse al compás del audio del sistema (Apple Music, Spotify, YouTube, etc.).

Actualmente, **las barras no reaccionan a las canciones reales**. Muestran movimientos rítmicos repetitivos y valores que no coinciden con la intensidad, transitorios, silencios ni tempo de las canciones.

### La Causa Raíz Inmediata
El motor `AudioSpectrumEngine.swift` tiene una implementación DSP completa basada en FFT de 4096 puntos y CoreAudio Process Tap. Sin embargo, **la captura de audio real del sistema (`enableSystemAudioTap`) se encuentra desactivada por defecto (`false`)** debido a que los Process Taps y la captura digital en macOS provocaban alertas intrusivas de permisos del sistema y el punto naranja/púrpura de grabación en la barra de menús.

Al estar desactivado el tap real, el método principal `getMagnitudes() -> [Float]` cae en un fallback denominado `generateRealisticMusicMagnitudes()`. Dicho método contiene un **oscilador sintético con un tempo fijo y cableado a 124.0 BPM (`let bpm: Double = 124.0`)** que modula ondas senoidales y decaimientos exponenciales contra el reloj del sistema (`CFAbsoluteTimeGetCurrent()`). Por tanto:
* No importa qué canción se reproduzca, qué género sea, ni qué tempo tenga (desde baladas a 65 BPM hasta rock a 170 BPM): las barras oscilan siempre en una coreografía matemática a 124 BPM.
* Durante partes silenciosas de una pista, pausas o solos acústicos, las barras siguen oscilando intensamente con bombos y cajas ficticias.

---

## 2. Mapa de Archivos del Módulo de Audio

| Archivo | Ruta Relativa | Responsabilidad |
| :--- | :--- | :--- |
| `AudioSpectrumEngine.swift` | `Sources/DynamicNotch/Services/AudioSpectrumEngine.swift` | Motor singleton principal. Contiene el bucle de captura, FFT con Accelerate vDSP, pipeline DSP de 5 etapas, fallback sintético y entrega de datos a la UI vía `getMagnitudes()`. |
| `SpectrumMetrics.swift` | `Sources/DynamicNotch/Services/SpectrumMetrics.swift` | Constantes, bandas de frecuencia, umbrales de compresión tanh, noise gate, balística de ataque/caída y presets de respuesta. |
| `AudioVisualizer.swift` | `Sources/DynamicNotch/Views/AudioVisualizer.swift` | Componente SwiftUI de 6 cápsulas con gradiente dinámico. Consume `getMagnitudes()` a 40–60 FPS. |
| `AudioDeviceService.swift` | `Sources/DynamicNotch/Services/AudioDeviceService.swift` | Monitoreo de cambios de hardware de salida (bocinas internas, AirPods, Bluetooth, HDMI). |
| `MusicService.swift` | `Sources/DynamicNotch/Services/MusicService.swift` | Servicio de reproducción y metadatos de medios (título, artista, estado `isPlaying`). |
| `MediaRemoteBridge.swift` | `DynamicNotch.app/Contents/Resources/MediaRemoteBridge.swift` | Script puente en Swift que consulta el framework privado `MediaRemote` para conocer qué app reproduce audio y su estado de reproducción. **Nota**: MediaRemote solo expone metadatos y controles de transporte, **no proporciona buffers PCM de audio**. |

---

## 3. Metodología y Construcción Técnica Actual

El sistema fue diseñado originalmente con un pipeline DSP profesional en 5 etapas dentro de `AudioSpectrumEngine.swift`:

```
[ Fuente de Audio ]
        │
        ▼
[ CoreAudio Process Tap / Ring Buffer (8192 muestras) ]
        │
        ▼
[ Ventana Hann (4096 muestras, salto de 512 = 10.6ms a 48kHz) ]
        │
        ▼
[ FFT Real con Accelerate vDSP (vDSP_fft_zrip) ]
        │
        ▼
[ Etapa 1: Energía Raw en 6 Bandas (Pico 70% + RMS 30%) ]
        │
        ▼
[ Etapa 2: Ponderación Psicoacústica / Ruido Rosa ]
        │
        ▼
[ Etapa 3: AGC Global + Noise Gate (-45dB) + Compresión Tanh ]
        │
        ▼
[ Etapa 4: Balística IEC (Ataque 14ms / Release 130ms) + Difusión Espacial ]
        │
        ▼
[ getMagnitudes() -> [Float] (Buffer atómico para SwiftUI) ]
```

### 3.1. Definición de las 6 Bandas de Frecuencia (`SpectrumMetrics.bands`)
1. **Sub-Bass**: 60 Hz – 150 Hz (Bombos sub, bajo profundo).
2. **Bass**: 150 Hz – 400 Hz (Cuerpo del bajo, pegada de percusión).
3. **Low-Mids**: 400 Hz – 1,000 Hz (Voces masculinas, fundamental de guitarras).
4. **High-Mids**: 1,000 Hz – 2,500 Hz (Voces femeninas, cajas, ataque de instrumentos).
5. **Presence**: 2,500 Hz – 6,000 Hz (Claridad vocal, platillos, brillo armónico).
6. **Brilliance**: 6,000 Hz – 14,000 Hz (Aire, hi-hats, transitorios ultra-altos).

### 3.2. Ponderación por Curva de Ruido Rosa (`pinkNoiseWeights`)
Para compensar la caída natural de energía $1/f$ de la música acústica y electrónica:
* Banda 0 (Sub-Bass): `1.00`
* Banda 1 (Bass): `1.08`
* Banda 2 (Low-Mids): `1.18`
* Banda 3 (High-Mids): `1.28`
* Banda 4 (Presence): `1.38`
* Banda 5 (Brilliance): `1.48`

### 3.3. Compresión Dinámica y Noise Gate
* **Noise Gate con Histéresis**: Abre a `-45.0 dBFS` y cierra a `-52.0 dBFS` con retención de 200 ms (`noiseGateHoldMs`) para evitar cortes abruptos entre frases musicales.
* **Compresión Tanh**:
  $$\text{output} = \frac{\tanh(\text{ratio} \times 1.5)}{\tanh(1.5)}$$
  Evita saturación y recorte digital cuando la canción alcanza picos altos.
* **Balística de Envolvente**:
  * Ataque: 14 ms (`SpectrumMetrics.attackMs`).
  * Caída: 130 ms (`SpectrumMetrics.releaseMs`).
  * Difusión espacial de 16% entre barras adyacentes para que el movimiento sea armónico y no salte bruscamente de una barra a otra.

---

## 4. Por Qué Está Fallando y Cómo se Produce el Desfase

### 4.1. El Atajo Sintético en `getMagnitudes()`
En `AudioSpectrumEngine.swift` (líneas 858–891):
```swift
public func getMagnitudes() -> [Float] {
    // 1. Audio Real del Sistema (DESACTIVADO POR DEFECTO: enableSystemAudioTap = false)
    if enableSystemAudioTap && isRealAudioActive {
        os_unfair_lock_lock(&lock)
        let copy = currentMagnitudes
        os_unfair_lock_unlock(&lock)
        return copy
    }
    
    // ...
    // 4. Música reproduciéndose en el sistema
    if MusicService.shared.currentTrack.isPlaying || AudioSignalGenerator.shared.activeSignal != .off {
        return generateRealisticMusicMagnitudes() // <-- AQUÍ ENTRA SIEMPRE
    }
    
    return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
}
```

### 4.2. El Generador Sintético (`generateRealisticMusicMagnitudes()`)
Líneas 944–1027 de `AudioSpectrumEngine.swift`:
```swift
let bpm: Double = 124.0
let beatDuration = 60.0 / bpm

let beatProgress = now.truncatingRemainder(dividingBy: beatDuration) / beatDuration
let barProgress = now.truncatingRemainder(dividingBy: beatDuration * 4.0) / (beatDuration * 4.0)

let kickDecay = exp(-beatProgress * 4.8)
let subBassHit = Float(max(0.0, kickDecay) * 0.85)

let halfBarProgress = now.truncatingRemainder(dividingBy: beatDuration * 2.0) / (beatDuration * 2.0)
let snarePhase = halfBarProgress - 0.5
let snareHit = snarePhase > 0 ? (exp(-snarePhase * 6.5) * 0.70) : 0.0
// ...
```
**Efecto visible para el usuario**:
* Las barras "bailan" siempre al mismo ritmo matemático de 124 BPM.
* No existe correlación con el audio del altavoz o auriculares.
* Si una canción se pausa en la app de música pero el estado tarda 1 segundo en reflejarlo, las barras siguen saltando.
* Si suena un solo de guitarra o un podcast, la barra de sub-bass sigue golpeando como si hubiera un bombo constante.

---

## 5. El Reto de Captura en macOS (Restricciones del Sistema)

Para que Gemini 4.0 proponga la solución idónea, es crucial comprender el ecosistema de audio en macOS 14 (Sonoma) y macOS 15 (Sequoia):

1. **Restricción de Audio Global**: En macOS no existe un API público simple tipo `AudioRecord` de Android o `WASAPI Loopback` de Windows que entregue el stream maestro sin permisos.
2. **Process Taps (`AudioHardwareCreateProcessTap`)**:
   * Introducido formalmente en macOS 14.2.
   * Permite crear un tap de audio por proceso o global excluyendo procesos.
   * Requiere crear un `AggregateDevice` privado con `kAudioAggregateDeviceTapListKey`.
   * **Gotcha de macOS**: En ciertas configuraciones de sandboxing o sin entitlements de audio del sistema, macOS puede no alimentar el IOProc o requerir privilegios elevados.
3. **ScreenCaptureKit (`SCStream`)**:
   * Permite capturar audio del sistema mediante `SCStreamConfiguration.capturesAudio = true` y `excludesCurrentProcessAudio = true`.
   * **Ventaja**: Captura PCM de alta fidelidad directamente del motor de audio de las aplicaciones.
   * **Desventaja histórica**: En versiones previas de macOS requería permiso de "Grabación de Pantalla" (Screen Recording). Sin embargo, en macOS 14.4+ / 15 existen configuraciones orientadas a audio.
4. **Virtual Audio Loopback (BlackHole / Soundflower)**:
   * Funciona perfecto pero requiere que el usuario instale un driver KEXT/DriverKit de terceros, lo cual es inaceptable para una experiencia de usuario transparente en Dynamic Notch.

---

## 6. Requerimientos para Gemini 4.0

El objetivo para el modelo **Gemini 4.0** es resolver este dilema e implementar un analizador que cumpla con los siguientes criterios:

1. **Reactivación / Implementación de Audio Real**:
   * Las 6 magnitudes devueltas por `getMagnitudes() -> [Float]` deben corresponder a la energía frecuencial real del audio sonando en los altavoces o audífonos.
   * Los picos de la Banda 0 (Sub-Bass) deben sincronizarse exactamente con los golpes de bombo/bajos de la pista real.
   * Los silencios deben llevar las barras a su estado de reposo mínimo (`minHeight: 3.5 pt` o puntos estáticos).

2. **Cero o Mínima Fricción de Privacidad**:
   * Evitar que macOS bombardee al usuario con cuadros de diálogo invasivos innecesarios.
   * Si se utiliza Process Tap de CoreAudio (`CATapDescription`), asegurar que la inicialización del Aggregate Device y el `AudioDeviceIOProcID` reciban muestras de forma confiable en cualquier dispositivo de salida (Bocinas internas, AirPods, Bocinas Bluetooth, USB DAC).

3. **Frecuencia y Rendimiento de la UI**:
   * `AudioVisualizer.swift` lee `getMagnitudes()` a ~40–60 Hz. La función debe ser thread-safe (como el `os_unfair_lock` actual) y tomar menos de 0.05 ms por llamada para no degradar la fluidez de la animación en SwiftUI.
   * El procesamiento pesado de FFT debe correr en la cola dedicada en segundo plano (`com.dynamicnotch.audiospectrum`).

4. **Contrato de Salida de la API**:
   * La función `getMagnitudes()` DEBE seguir devolviendo un arreglo de 6 elementos tipo `[Float]` con valores normalizados en el rango `[0.0, 1.0]`.

---

## 7. Formato del Reporte de Cambios Requerido de Gemini 4.0

Una vez que Gemini 4.0 diseñe y aplique la solución, deberá generar un archivo de reporte estructurado (por ejemplo, `AUDIO_CHANGES_REPORT.md`) con las siguientes secciones:
1. **Resumen de la Solución Adoptada**: Explicación de la técnica empleada para capturar o alimentar el audio real (Process Tap depurado, ScreenCaptureKit, CoreAudio HAL listener u otra alternativa).
2. **Archivos Modificados**: Lista exacta de archivos y funciones intervenidas.
3. **Diffs o Código Reemplazado**: Bloques de código con explicaciones de los cambios en el pipeline DSP.
4. **Instrucciones de Verificación**: Pasos para compilar, probar con una canción de prueba y verificar que las barras sigan el ritmo real.
