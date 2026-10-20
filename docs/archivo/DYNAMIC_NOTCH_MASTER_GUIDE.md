# Dynamic Notch — Guía Maestra de Arquitectura, Componentes y Funcionamiento

> **Documento de Referencia Técnica Completa para Claude Pro y Antigravity AI**  
> *Versión 2.0 • macOS Sonoma (14.2+) y macOS Sequoia (15.0+)*  
> *Autor: Antigravity Pair-Programming Suite*

---

## 1. Visión General y Filosofía de Diseño

**Dynamic Notch** es una experiencia inmersiva para macOS que transforma el notch físico de las MacBook (o genera una isla virtual en monitores externos y Macs sin notch) en una **Dynamic Island** hiper-fluida inspirada en iOS y Apple Silicon.

### Principios Fundamentales:
1. **Alineación Orgánica con el Hardware**: Anclado en el centro superior de la pantalla principal (`NSScreen`), respetando safe area insets y curvaturas de pantalla reales.
2. **Estética Liquid Glass**: Interpolación continua de curvas Bézier con radios independientes (`topLeading`, `topTrailing`, `bottomLeading`, `bottomTrailing`), difusión de color adaptativa basada en la carátula de música actual, y gradientes de alta resolución.
3. **Fidelidad Sonora Digital Cero-Micrófono**: Captura el audio de macOS vía `CATapDescription` (macOS 14.2+) de forma digital y sin encender el indicador naranja de privacidad del micrófono, procesado mediante vDSP FFT (4096 puntos).
4. **Interacción Háptica y Gestual por Trackpad**: Reconocimiento de deslizamientos de 2 dedos (scroll wheel con rechazo de inercia), overscroll elástico con factor de arrastre (rubber-banding) y soporte de arrastrar y soltar (Shelf / Drawer).
5. **Orquestación de Actividades en Vivo (Live Activities)**: Cola de prioridades para música, temporizadores, llamadas entrantes, notificaciones interactivas de WhatsApp con respuesta rápida, y satélites desprendidos para monitorear el progreso de agentes de IA.

---

## 2. Jerarquía de Ventanas y Sistema de Hit-Testing (AppKit & SwiftUI)

La arquitectura de ventanas se ubica en `Sources/DynamicNotch/Window/`.

```
                    ┌────────────────────────────────────────┐
                    │            NSScreen.main               │
                    └───────────────────┬────────────────────┘
                                        │
                                        ▼
                    ┌────────────────────────────────────────┐
                    │               NotchPanel               │
                    │      (NSPanel, .floating + 1,          │
                    │   ignoresMouseEvents = false, clear)   │
                    └───────────────────┬────────────────────┘
                                        │
                                        ▼
                    ┌────────────────────────────────────────┐
                    │            NotchHitTestView            │
                    │ (Hit test dinámico: notch + satélites) │
                    └───────────────────┬────────────────────┘
                                        │
                                        ▼
                    ┌────────────────────────────────────────┐
                    │       NSHostingView<NotchContainer>    │
                    │    (Contenedor raíz en SwiftUI)        │
                    └───────────────────┬────────────────────┘
                                        │
        ┌───────────────────────────────┴───────────────────────────────┐
        ▼                                                               ▼
┌───────────────────────────────┐                       ┌───────────────────────────────┐
│     ElasticPillShape View     │                       │       NotchBolitaView         │
│  (Cuerpo Central del Notch)   │                       │ (Burbujas Satélite Flotantes) │
└───────────────────────────────┘                       └───────────────────────────────┘
```

### 2.1 `NotchPanel` (`NotchPanel.swift`)
- Hereda de `NSPanel`.
- **Configuración de Ventana**:
  - `styleMask = [.borderless, .nonactivatingPanel]`
  - `level = .floating + 1` (garantiza estar por encima de la barra de menús sin invadir ventanas modales del sistema ni el dock).
  - `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`.
  - `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]` (visible en todos los Spaces y durante aplicaciones a pantalla completa).
  - `isMovable = false`.

### 2.2 `NotchHitTestView` (`NotchPanel.swift`)
- macOS envía clics a través de `hitTest(_ point: NSPoint)`.
- **Problema que resuelve**: Como el panel ocupa todo el ancho superior de la pantalla para permitir animaciones elásticas, si fuera interactivo en toda su extensión, bloquearía los clics a la barra de menús y pestañas de Safari.
- **Mecanismo de Intersección**:
  - Mantiene 3 rectángulos activos: `hitAreaRect` (cuerpo del notch), `satelliteHitAreaRect` (bolitas satélite derechas) y `leftSatelliteHitAreaRect` (bolitas satélite izquierdas).
  - Si el punto cae fuera de estas áreas, retorna `nil` de inmediato $\to$ el evento atraviesa limpiamente hacia las ventanas subyacentes del usuario.
  - Si el punto cae sobre el satélite, `mouseDown` redirige directamente a la acción del satélite (abrir el HUD del agente) sin disparar la expansión del reproductor musical.

### 2.3 `NotchWindowManager` (`NotchWindowManager.swift`)
- Administrador global del ciclo de vida del panel.
- Monitorea eventos de resolución de pantalla (`NSApplication.didChangeScreenParametersNotification`).
- Calcula las dimensiones geométricas usando `ScreenService.shared.currentGeometry`.
- Configura monitores globales y locales de eventos (`NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown])`).

---

## 3. Modos de la Isla y Estados del Sistema

Ubicación: `Sources/DynamicNotch/Core/AppState.swift`

| Modo | Descripción | Dimensiones Típicas |
| :--- | :--- | :--- |
| **`.idle`** | Reposo absoluto. Se mimetiza con el notch de hardware o una píldora negra simétrica. | Hardware: $\sim 180\text{--}210 \times 32\text{ pt}$<br>Simulado: $160 \times 32\text{ pt}$ |
| **`.compact`** | Modo comprimido con música reproduciéndose. Añade dos alas laterales ($52\text{ pt}$ cada una) para carátula y ecualizador. | Ancho: Notch $+ 104\text{ pt}$<br>Alto: $32\text{ pt}$ |
| **`.expanded`** | Reproductor de música expandido con controles, título, artista, scrubber y visualizador de 6 barras. | $380 \times 160\text{ pt}$<br>(Detalle de volumen: $380 \times 220\text{ pt}$) |
| **`.shelf`** | Cajón / bandeja temporal de archivos mediante Drag and Drop. Permite soltar documentos e imágenes. | $340 \times 98\text{ pt}$ |

### Transiciones de Estado
- `.idle` $\xrightarrow{\text{Música iniciada}}$ `.compact`
- `.compact` $\xrightarrow{\text{Swipe Down / Tap}}$ `.expanded`
- `.expanded` $\xrightarrow{\text{Swipe Up / Tap exterior}}$ `.compact` o `.idle`
- `.expanded` $\xrightarrow{\text{Swipe Izq / Der}}$ `.shelf` (alterna entre música y bandeja temporal de archivos).

---

## 4. Pipeline de Gestos por Trackpad y Deslizamiento (Scroll Wheel)

Implementado en `NotchWindowManager.swift` y `NotchPanel.swift`.

### 4.1 Inversión y Normalización
macOS reporta `scrollingDeltaY` invertido según la configuración de "Desplazamiento natural" del usuario (`event.isDirectionInvertedFromDevice`).
```swift
let fingerDy = isInverted ? rawDy : -rawDy // > 0: dedos hacia abajo (hacia el usuario)
let fingerDx = isInverted ? rawDx : -rawDx // > 0: dedos hacia la derecha
```

### 4.2 Jerarquía Estricta de Prioridades
Para evitar que un gesto interfiera con otro, el despachador sigue una cadena de responsabilidad:

1. **Prioridad 0: Actividades Expandidas / HUDs Modales**
   - Si la tarjeta de detalles del agente o una actividad en vivo está expandida:
   - `Swipe Up` (dedos hacia arriba) $\to$ Colapsa la actividad o HUD inmediatamente con respuesta háptica.
2. **Prioridad 1: Notificación Interactiva Activa (WhatsApp / Mensajes)**
   - Si `NotificationActivityProvider.shared.isNotificationActive == true`:
   - `Swipe Down` $\to$ Dispara `expandQuickReply()` para escribir la respuesta inmediata.
   - `Swipe Up` $\to$ Dispara `dismissNotification()` para descartar la tarjeta.
3. **Prioridad 2: Llamada Entrante o Activa (FaceTime / Teléfono)**
   - `Swipe Down` $\to$ Expande de píldora compacta a tarjeta completa de llamada (`expandToCard()`).
   - `Swipe Up` $\to$ Contrae de nuevo a píldora compacta (`collapseToPill()`).
4. **Prioridad 3: Diálogo de Pregunta / Autorización de Agente**
   - Si hay una confirmación pendiente en pantalla (`currentPayload != nil`):
   - `Swipe Down` $\to$ Expande opciones de terminal.
   - `Swipe Up` $\to$ Cancela/descarta el diálogo.
5. **Prioridad 4: Reproductor de Música (Modos `.idle` o `.compact`)**
   - `Swipe Down` $\to$ Dispara `AppState.shared.expand()`.
   - **Regla Crítica**: La existencia de tareas secundarias (como el indicador de progreso del agente de IA) **no debe bloquear** el gesto hacia abajo para abrir el reproductor.
6. **Prioridad 5: Modo Expandido (`.expanded`)**
   - `Swipe Up` $\to$ Si el detalle de volumen está abierto, lo cierra; si no, colapsa el reproductor a `.compact`.
   - `Swipe Down` $\to$ Expande el control deslizante de volumen de alta precisión.
   - `Swipe Horizontal` $\to$ Navega hacia la bandeja de archivos (`.shelf`).

---

## 5. Motor de Audio y Espectro DSP (AudioSpectrumEngine)

Ubicación: `Sources/DynamicNotch/Services/AudioSpectrumEngine.swift` y `SpectrumMetrics.swift`.

### 5.1 Captura Digital de Audio del Sistema (macOS 14.2+)
En macOS 14.2 y posterior, Apple introdujo `CATapDescription`:
- `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`
- `isPrivate = true`
- **Ventaja**: Captura la señal de audio digital limpia que sale hacia altavoces o auriculares (Spotify, Apple Music, YouTube, Safari, QuickTime) **sin requerir permisos de micrófono** y sin mostrar el punto naranja en la barra de menús.
- Si el tap no está disponible o el sistema está en silencio, conmuta automáticamente a `ProceduralMotionEngine.swift` para mantener una ondulación rítmica orgánica.

### 5.2 Algoritmo DSP y Banco de Filtros
1. **Buffer de Muestreo**: Ring buffer de punto flotante a $44.1\text{ kHz} / 48\text{ kHz}$.
2. **Transformada Rápida de Fourier (FFT)**:
   - Ventana Hann de 4096 muestras (`vDSP_hann_window`).
   - `vDSP_fft_zrip` para calcular el espectro real a complejo.
   - Magnitudes al cuadrado convertidas a decibelios ($\text{dBFS}$).
3. **Bandas Frecuenciales Logarítmicas (6 Bandas)**:
   - **Banda 0 (Sub-graves)**: $30\text{ Hz} \sim 90\text{ Hz}$ (Bombos, 808s).
   - **Banda 1 (Graves)**: $90\text{ Hz} \sim 250\text{ Hz}$ (Bajo eléctrico, sintes bajos).
   - **Banda 2 (Medios-Bajos)**: $250\text{ Hz} \sim 600\text{ Hz}$ (Cuerpo vocal, caja/snare).
   - **Banda 3 (Medios)**: $600\text{ Hz} \sim 2000\text{ Hz}$ (Presencia vocal, guitarras).
   - **Banda 4 (Medios-Altos)**: $2\text{ kHz} \sim 6\text{ kHz}$ (Ataque, articulación vocal).
   - **Banda 5 (Agudos)**: $6\text{ kHz} \sim 16\text{ kHz}$ (Platillos, brillo, aire).
4. **Ponderación de Ruido Rosa (Pink Noise Tilt)**:
   - Como la energía de la música disminuye de forma natural con la frecuencia ($\sim 3\text{ dB/octava}$), se aplica una compensación de ganancia progresiva ($+1.5\text{ dB} \dots +9.0\text{ dB}$) para que los agudos se muevan con la misma expresividad visual que los bombos.
5. **Control Automático de Ganancia (AGC)**:
   - Normaliza pistas con volumen bajo o canciones con masterización de alto rango dinámico.
6. **Balística de 2 Constantes de Tiempo (Attack & Release)**:
   - **Attack ($24\text{ ms}$)**: Sube instantáneamente con el impacto de un tambor.
   - **Release ($190\text{ ms}$)**: Cae suavemente con inercia musical, evitando jitter.
   - **Filtro IIR de 1 Polo**: Coeficiente $\alpha = 1.0 - e^{-\Delta t / 0.055} \approx 0.26$, eliminando fluctuaciones nerviosas cuadro a cuadro.

### 5.3 Métricas de Barras del Visualizador (`PlayerMetrics.swift`)
Calibradas para asemejarse exactamente al Dynamic Island de Apple:
- `visualizerBarWidth = 2.0 pt`
- `visualizerBarSpacing = 1.8 pt`
- `visualizerMinHeight = 2.4 pt` (punto circular en silencio)
- `visualizerMaxHeight = 13.0 pt` (altura máxima equilibrada con el título)
- `visualizerPausedDotSize = 2.4 pt`
- Ancho total de las 6 barras: $21.0\text{ pt}$ (centrado verticalmente con la carátula).

---

## 6. Sistema de Actividades en Vivo y Satélites (ActivityCenter)

Ubicación: `Sources/DynamicNotch/Activities/`

### 6.1 `LiveActivity`
Modelo de datos que define cualquier evento dinámico en la isla:
- `id: String` (único, ej. `agent_progress_hud`, `notification_whatsapp_123`).
- `priority: Int`: Rango de 1 a 100.
  - Prioridad 95: Notificación interactiva / Llamada entrante.
  - Prioridad 80: Temporizador / Cronómetro.
  - Prioridad 70: Monitoreo de agente de IA (Antigravity).
  - Prioridad 50: Reproductor musical / Estado de batería.
- `style: ActivityStyle`:
  - `.pill`: Ocupa las alas del notch.
  - `.card`: Reemplaza el notch temporalmente con una tarjeta modal.
  - `.satellite`: Se desprende hacia la derecha o izquierda como una bolita flotante independiente.

### 6.2 Las Bolitas Satélite (`NotchBolitaView.swift`)
- Burbuja circular independiente separada del notch por un espacio elástico (`bolitaGap = 10 pt`, `bolitaDiameter = 28 pt`).
- Permite que el usuario escuche música en el centro mientras observa el progreso de un agente o un temporizador a la derecha.
- **Interacción**: Al hacer tap sobre la bolita satélite del agente, se despliega el HUD bilateral de progreso en tiempo real (`AgentLiveProgressView`).

---

## 7. Integración con WhatsApp y Notificaciones

Ubicación: `Sources/DynamicNotch/Services/WhatsAppWebObserverService.swift` y `NotificationActivityProvider.swift`.

### 7.1 Detección
- Monitorea navegadores (Safari, Google Chrome, Brave) y la aplicación nativa de WhatsApp.
- Emplea la API de accesibilidad de macOS (`AXUIElementCopyAttributeValue`) y AppleScript para detectar títulos de ventanas y notificaciones web con el patrón `"(n) Nombre de Contacto"`.
- Genera avatares monograma instantáneos en memoria (`ContactLookupService.shared.generateMonogramAvatar`) para jamás trabar el hilo principal de la interfaz de usuario.

### 7.2 Modo Quick Reply
- Al realizar swipe down o pulsar la notificación, la isla se estira a $420 \times 128\text{ pt}$.
- `NotchWindowManager.shared.setAllowsKeyInput(true)` habilita que el panel acepte foco del teclado.
- El usuario puede escribir su mensaje directamente en el notch y presionar `Enter` para enviarlo a WhatsApp Web vía inyección DOM o AppleScript.

---

## 8. IPC Local y Monitoreo del Agente Antigravity

Ubicación: `Sources/DynamicNotch/Services/AgentIPCService.swift` y `scripts/antigravity_hook.py`.

```
┌────────────────────────┐                    ┌────────────────────────┐
│     Antigravity AI     │                    │  Dynamic Notch (App)   │
│  (Extension / CLI /    ├──── POST /progress ───►  AgentIPCService    │
│   antigravity_hook.py) │                    │   (Port 127.0.0.1:     │
│                        │◄─── POST /authorize ──┤        48123)       │
└────────────────────────┘                    └────────────────────────┘
```

### 8.1 Endpoints del Servidor HTTP
- **`POST /progress`**: Actualiza el estado del agente, archivo editado, métricas de diffs (`+agregadas -eliminadas`), estado textual y progreso general.
- **`POST /authorize`**: Flujo de autorización de comandos de terminal (Human-in-the-Loop). Cuando Antigravity va a ejecutar un comando sensible, consulta al usuario desde el Notch con botones de "Permitir" o "Rechazar".
- **`POST /tokens`**: Registra consumo de tokens de entrada y salida, sincronizándolo con el monitor de cuotas de `AICreditsService`.

### 8.2 Motor de Progreso Monotónico y Tiempo Estimado
- **Problema previo resuelto**: Las herramientas individuales provocaban que la barra morada se reiniciara a 0 tras cada acción.
- **Nuevo Algoritmo**:
  - `antigravity_hook.py` mantiene una sesión acumulativa en `/tmp/antigravity_task_session.json`.
  - El progreso nunca retrocede: $P_{\text{nuevo}} = \max(P_{\text{anterior}} + 0.04, P_{\text{fase}})$.
  - Cálculo de tiempo restante aproximado ($\sim 45\text{s} \dots \sim 5\text{s} \dots \text{Listo}$).
  - `AgentIPCService.swift` aplica la regla monótona: `persistentProgress = max(persistentProgress, rawProgress)`.

---

## 9. Compilación, Empaquetado y Depuración

### 9.1 Script de Construcción
```bash
./scripts/build_app.sh
```
El script realiza:
1. Compilación mediante Swift Package Manager (`swift build -c release`).
2. Empaquetado de la estructura `.app`:
   - `DynamicNotch.app/Contents/MacOS/DynamicNotch`
   - `DynamicNotch.app/Contents/Info.plist`
   - `DynamicNotch.app/Contents/Resources/`
3. Firma de código ad-hoc con derechos de accesibilidad y audio (`codesign --force --deep --sign -`).

### 9.2 Logs del Sistema
Todas las capas escriben mediante `DNDLogger.log(...)`. Para monitorear en vivo:
```bash
tail -f /tmp/dynamic_notch.log
```
O ejecutando el binario directamente desde la terminal:
```bash
./DynamicNotch.app/Contents/MacOS/DynamicNotch
```

---

## 10. Mapa de Archivos del Proyecto

```
Dynamic Notch/
├── Package.swift                                # Configuración SPM
├── ARCHITECTURE.md                              # Especificación técnica base
├── DYNAMIC_NOTCH_MASTER_GUIDE.md                # Esta guía maestra
├── scripts/
│   ├── build_app.sh                             # Compilador y empaquetador .app
│   └── antigravity_hook.py                      # Bridge de hooks para Antigravity AI
└── Sources/DynamicNotch/
    ├── main.swift                               # Punto de entrada de la app
    ├── Core/
    │   ├── AppState.swift                       # Estado reactivo global
    │   ├── PlayerMetrics.swift                  # Métricas de diseño y visualizador
    │   ├── OverscrollMetrics.swift              # Constantes de física y estiramiento
    │   └── DNDLogger.swift                      # Logging
    ├── Window/
    │   ├── NotchPanel.swift                     # NSPanel transparente e interactivo
    │   └── NotchWindowManager.swift             # Monitores de pantalla y gestos
    ├── Services/
    │   ├── AudioSpectrumEngine.swift            # Captura CATapDescription y FFT
    │   ├── SpectrumMetrics.swift                # Balística de ataque/caída
    │   ├── ProceduralMotionEngine.swift         # Generador armónico procedural
    │   ├── NowPlayingService.swift              # Integración con Spotify / Apple Music
    │   ├── WhatsAppWebObserverService.swift     # Observador de WhatsApp
    │   ├── AgentIPCService.swift                # Servidor HTTP local (puerto 48123)
    │   └── AICreditsService.swift               # Contador de cuotas y tokens
    ├── Activities/
    │   ├── ActivityCenter.swift                 # Cola de prioridades de Live Activities
    │   ├── LiveActivity.swift                   # Protocolo y modelos
    │   ├── Providers/
    │   │   ├── NotificationActivityProvider.swift # Notificaciones WhatsApp
    │   │   ├── CallActivityProvider.swift         # Llamadas entrantes
    │   │   └── AgentActivityProvider.swift        # Actividad del Agente IA
    │   └── Templates/
    │       ├── QuickReplyNotificationView.swift   # Vista de respuesta rápida
    │       └── AgentLiveProgressView.swift        # HUD bilateral de IA
    └── Views/
        ├── NotchContainerView.swift             # Contenedor raíz y morphing
        ├── ElasticPillShape.swift               # Forma Bézier fluida con animación
        ├── NotchPlayerView.swift                # Reproductor musical expandido
        ├── NotchCompactView.swift               # Modo compacto de 2 alas
        ├── NotchBolitaView.swift                # Burbujas satélite flotantes
        └── AudioVisualizer.swift                # Barras reactivas al sonido
```
