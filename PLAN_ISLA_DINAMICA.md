# Plan: del Dynamic Notch estable a la Isla Dinámica en Macs sin notch

19 de octubre de 2026 · versión de partida: 1.9 (+ fixes del 19 de octubre)

Orden acordado:
1. **Fase A — Dynamic Notch estable y 100 % funcional.**
2. **Fase B — Isla Dinámica real en pantallas sin notch** (monitor secundario y Macs sin notch), configurable.

Fase B no empieza hasta que Fase A pase su lista de aceptación (sección 6).

---

## 1. Lo que aprendí (fuentes oficiales de Apple)

Leído directamente de Apple Developer (HIG *Live Activities*, *Materials*, ActivityKit *Displaying live data*, SwiftUI *Applying Liquid Glass to custom views*, AppKit `NSGlassEffectView` / `NSGlassEffectContainerView`) y del Manual del iPhone (iOS 27, *View Live Activities in the Dynamic Island*).

### 1.1 Isla Dinámica: cómo se comporta

**Presentaciones.** Toda actividad tiene cuatro: **compacta**, **mínima**, **expandida** y **pantalla bloqueada**. Es la misma actividad: sólo cambia cuánto espacio ocupa.

**Compacta** (una sola actividad):
- Son dos elementos, uno a cada lado de la cámara, que deben leerse como **una sola pieza de información** (mismo color y misma tipografía).
- Va pegada a la cámara, sin relleno entre el contenido y la cámara. El lado izquierdo y el derecho tienen tamaños parecidos.
- Al tocar cualquiera de los dos lados se abre la misma pantalla de la app.

**Mínima** (dos o más actividades):
- Caben **hasta 3**: una **pegada** a la isla y las demás **separadas, a uno o a ambos lados**.
- La separada es **circular u ovalada según su contenido**. Debe mostrar datos vivos, no sólo un logo; por ejemplo, el temporizador muestra el tiempo que queda.
- **Ancho limitado:** con 2 o más actividades (iPhone 18 Pro), o en horizontal, la compacta y la mínima deben caber en un **círculo de 28 pt**. Si el lado derecho no cabe, se oculta.

**Expandida:**
- Se abre al **mantener presionada** la compacta o la mínima.
- Es la versión **agrandada** de la compacta: los elementos conservan su posición relativa y el contenido abraza la cámara.
- Su alto cambia según la información: entre **84 y 160 pt**.

**Medidas en iOS** (pt):
- Compacta: 52.33–62.33 × 36.67 por lado.
- Mínima: 36.67–45 × 36.67.
- Expandida: 371–408 de ancho × 84–160 de alto.
- Ancho limitado: 28 × 28.
- macOS usa las mismas medidas que iOS.

**Márgenes:**
- Concéntricos y parejos: el contenido nunca toca el borde de la isla.
- Las esquinas internas usan `ContainerRelativeShape`.
- En la pantalla bloqueada el margen estándar es de **14 pt**.

**Color:**
- En la isla el fondo es **negro opaco** y no se personaliza.
- Se recomiendan colores audaces de la marca.
- En modo oscuro aparece una **keyline** alrededor de la isla, teñida con el color del contenido.

**Animación:**
- Las animaciones del sistema y las propias duran **2 s como máximo**. No se animan en Always-On con brillo reducido.
- En cambios de layout se mueven los elementos existentes a su nueva posición en vez de quitarlos y volver a meterlos.
- Hay que evitar que los elementos se encimen: es mejor que uno salga y vuelva a entrar.
- Se usan transiciones de contenido (`numericText`, reemplazo, escala, opacidad).

**Gestos (iPhone, iOS 27):**
- Tocar abre la app; en la mínima, **tocar la actividad también cambia a ella**.
- Mantener presionado expande.
- Deslizar hacia arriba sobre la expandida la recoge.
- En iPhone 18 Pro, **deslizar a lo ancho recorre** las hasta 3 actividades.

**Prioridad:**
- Gana la `relevanceScore` más alta. Si empatan, gana la **primera que se inició**.
- La puntuación es relativa (por ejemplo 100 contra 50) y puede cambiar con cada actualización.

**Alertas:**
- Sólo para actualizaciones esenciales: encienden la pantalla, suenan y **muestran la expandida en la isla**. En equipos sin isla aparecen como banner.
- No se duplican con notificaciones push.

**Ciclo de vida:**
- Una actividad dura **8 h como máximo** en la isla. Al terminar desaparece de la isla de inmediato.
- En la pantalla bloqueada y en la **barra de menús del Mac** permanece hasta **4 h más**; se recomienda un cierre propio de 15 a 30 min.
- Existe el estado **"obsoleto"** (`staleDate` / `isStale`).

**Buenas prácticas:**
- Nada de publicidad.
- Nada sensible a la vista: mostrar un resumen inocuo y el detalle al tocar.
- Logo sin contenedor (nunca el icono completo de la app).
- Texto de peso medio o más.
- Una sola actividad que rota eventos es mejor que varias actividades.

**macOS:** las Live Activities del iPhone ya aparecen en la **barra de menús del Mac** emparejado (compacta, mínima y expandida); al hacer clic se abre la Duplicación del iPhone. No hay API pública para leerlas desde otra app.

### 1.2 Liquid Glass

**Qué es y dónde va:**
- Es una **capa funcional** para controles y navegación que flota sobre el contenido. **No va en la capa de contenido.**
- Se usa con moderación, sólo en los elementos funcionales más importantes.

**Las dos variantes:**
- **`regular`** desenfoca y ajusta la luminosidad para que se lea. Es la variante por defecto; úsala cuando hay mucho texto o el fondo es problemático.
- **`clear`** es muy translúcida y es **sólo para fondos visualmente ricos** (fotos, video). Si el fondo es claro, se agrega una **capa oscura del 35 %**; si es oscuro, no hace falta.

**API de SwiftUI:**
- `glassEffect(_:in:)`: por defecto `regular` dentro de una `Capsule`. Se aplica **después** de los demás modificadores de apariencia.
- `.tint()` sugiere prominencia y `.interactive()` reacciona al tacto y al puntero.

**`GlassEffectContainer(spacing:)`:**
- Agrupa el vidrio para que rinda mejor y para que las formas **se fundan y transformen** entre sí.
- A mayor `spacing`, antes se funden. Si el spacing del contenedor es mayor que el del `HStack`, las formas quedan **fundidas incluso en reposo**.
- Herramientas relacionadas:
  - `glassEffectUnion(id:namespace:)` une varias vistas en una sola cápsula.
  - `glassEffectID(_:in:)` con `@Namespace` hace la transformación entre vistas.
  - `glassEffectTransition`: `.matchedGeometry` (por defecto, dentro del spacing) o `.materialize` (más lejos).

**AppKit:**
- `NSGlassEffectView`: `contentView`, `cornerRadius`, `tintColor`, `style`, `effectIsInteractive`.
- `NSGlassEffectContainerView`: `contentView` y `spacing`; funde las vistas de vidrio que estén cerca.

**Rendimiento y accesibilidad:**
- Demasiados contenedores o efectos sueltos degradan el rendimiento.
- La apariencia cambia con *Reducir transparencia*, *Aumentar contraste* y la preferencia de "look" del sistema.

### 1.3 Qué significa para nosotros

- **El modo canónico de la Isla es negro opaco.** El cristal es una opción nuestra y debe obedecer las reglas: regular o clear con capa oscura del 35 % según el fondo, nunca vidrio sobre vidrio.
- Nuestro "morfeo líquido" (SDF y marching squares) va **más allá** de lo que da `GlassEffectContainer`. Se queda, pero debe durar ≤ 2 s por fase; hoy son 1.84 s y 1.55 s, así que estamos dentro.
- La lógica que más nos falta no es visual: es la **política de presentación** con varias actividades: mínima pegada, hasta 2 separadas, ancho limitado, recorrer con swipe y alertas.

---

## 2. Inventario: lo que Dynamic Notch tiene hoy

Código: 124 archivos Swift, unas 38 000 líneas.

### Núcleo y ventana
- `NSPanel` no activante sobre el notch, con hit-test dinámico: pasa los clics fuera de la forma y tiene zonas propias por bolita (`notchHitRegion`).
- Modos `idle`, `compact`, `expanded` y `shelf`, con histéresis.
- Detección del notch físico (`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`).
- **Sin notch:** sólo un *fallback* fijo de 180×32 en la pantalla principal, que no es una isla de verdad.
- Se oculta en pantalla completa con video o música.
- Cursor de flecha forzado.

### Gestos
- Máquina de estados del trackpad (`TrackpadGestureRecognizer`) y `NotchGestureDispatcher`.
- Swipe abajo para abrir y arriba para cerrar.
- Cierre interactivo que sigue los dedos; cambio horizontal entre reproductor y repisa; swipe lateral para esconder la música.
- Hover que crece y expandir al acercar el cursor.
- Clic abre la app de la bolita (o expande si la app ya está al frente); mantener presionado expande.

### Live Activities propias (`ActivityCenter`)
- **Prioridad:** prioridad, luego `createdAt` (gana la primera), histéresis de 3 s y urgentes.
- **Varias actividades:**
  - Una principal en el notch y bolitas satélite, a la derecha o a ambos lados (`satelliteLocation`).
  - Máximo configurable (`maxSatelliteBolitas`) y cola de desborde.
- **Transiciones y alertas:**
  - Intercambio notch ⇄ bolita con etapas (`RoleHandoff`).
  - El HUD del sistema (volumen, brillo, AirPods) tiene preferencia y luego retiene la principal (`hudHoldUntil`).
  - Alertas tipo Isla: `presentAlert`, con duración configurable.
- **Plantillas:** `pill`, `sliderPill`, `airpodsPill`, `card`, `bolitaVariant` (color o anillo de progreso) y vista expandida propia.
- **Estados de ciclo de vida:** `starting`, `active`, `updated`, `paused`, `attention`, `finished`, `dismissed`.
- **Proveedores:**

  | Proveedor | Qué muestra |
  |---|---|
  | Música / video | Alas con carátula y barras; reproductor expandido |
  | Temporizador | Mini-app; cede el notch a la música |
  | Llamadas | FaceTime, celular, WhatsApp, Discord; contestar/rechazar, onda y mute |
  | AirPods | 3D, batería L/R/estuche |
  | AirDrop | Envío y recepción propios |
  | Carga | Batería |
  | Notificaciones | iMessage/SMS con respuesta rápida; WhatsApp Web |
  | Claude Code | Hooks, tarea, uso y permisos |
  | Agente IA | Antigravity, progreso |
  | Repisa | Bolita |
  | HUD | Volumen y brillo |

### Animación y materiales
- Física del notch: `ElasticPillShape`, impulsos y `morphBlur`.
- Morfeo líquido real de las bolitas: SDF, smooth-min y contorno, en negro y en cristal, con nacimiento, cuello y corte, y su inverso.
- Liquid Glass:
  - Modos negro, Cristal Claro y Cristal Oscuro.
  - Alas de cristal con el centro negro.
  - Velo mínimo y adaptación a fondo claro (`BackdropBrightnessMonitor`).
  - Keyline en modo oscuro; Reducir transparencia / Aumentar contraste.
- Animation Studio (Debug): línea de tiempo, parámetros en vivo y geometría.

### Multimedia
- MediaRemote y servicios de música.
- Captura del audio del sistema sólo mientras suena; FFT por banda con AGC y compensación de latencia Bluetooth.
- Respaldo de tempo para audio con DRM.
- Letras sincronizadas.
- Selector de salida de audio.

### Pantalla bloqueada
- Reproductor compacto estilo iPhone que se transforma en pantalla completa con fondo de la carátula y letras.

### Repisa / Drag & Drop
- Invitación al acercar un archivo, soltar en toda la tarjeta y almacenamiento sin Finder.

### Ajustes y diagnóstico
- 7 pestañas: Apariencia, Gestos, Actividades, Drag & Drop, Multimedia, Mini-Apps, Sistema.
- Rutas `/debug/*`: hit, actividades, audio, hitches, render-bubble, studio y snapshot de ajustes.
- Monitor de tirones (`FrameHitchMonitor`).

---

## 3. Lo que le falta (brechas contra la Isla Dinámica real)

Prioridad: **P0** = bloquea "estable", **P1** = lo que hace que se sienta Isla de verdad, **P2** = mercado y extras.

### 3.1 Política de presentación con varias actividades (P0/P1)

| # | Falta | Cómo lo hace iOS | Prioridad |
|---|---|---|---|
| A1 | **Mínima pegada** | Con 2 o más actividades, la del notch pasa de compacta a **mínima**: sólo el lado izquierdo, pegado a la cámara, y la isla se angosta. Hoy la principal mantiene sus dos alas completas y además salen bolitas. | P1 |
| A2 | **Hasta 3 a la vista, con reglas fijas** | 1 pegada + hasta 2 separadas (izquierda y derecha); el resto en cola. Hoy depende de `maxSatelliteBolitas` y `satelliteLocation` sin una regla única, y puede haber choques. | P0 |
| A3 | **Posiciones estables** | Una actividad no salta de lado mientras vive; el orden sólo cambia por relevancia, con histéresis. | P0 |
| A4 | **Ancho limitado de 28 pt** | Con 3 actividades, la compacta y la mínima se reducen a un círculo de 28 pt. Las plantillas necesitan su variante "limitada". | P1 |
| A5 | **Recorrer con swipe a lo ancho** | Swipe horizontal sobre la isla = siguiente o anterior actividad, como en el iPhone 18 Pro. Hoy el swipe lateral sólo esconde la música o cambia de página. | P1 |
| A6 | **Tocar la separada para cambiar a ella** | iOS cambia de actividad. Ajuste: "clic = abrir app" (hoy) o "clic = traer al notch". | P1 |
| A7 | **Bolitas ovaladas por contenido** | La separada puede ser óvalo si muestra texto corto (por ejemplo "4:32"). Hoy son sólo círculos. | P2 |
| A8 | **Relevancia dinámica** | La relevancia se actualiza con cada cambio de estado; por ejemplo, el temporizador sube en el último minuto. Hoy la prioridad es fija por tipo (`defaultPriority`). | P1 |
| A9 | **Una actividad que rota eventos** | Notificaciones en ráfaga (WhatsApp, iMessage) en una sola actividad que rota, no muchas. | P2 |

### 3.2 Ciclo de vida y alertas (P0/P1)

| # | Falta | Prioridad |
|---|---|---|
| L1 | Duración máxima (8 h) y estado **obsoleto** (`staleDate`, vista "sin actualizar"). | P1 |
| L2 | Cierre con resumen breve configurable cuando la actividad termina; hoy algunas desaparecen sin resumen. | P1 |
| L3 | **Configuración de alerta por actualización:** expandir unos segundos, sonido opcional y sin duplicar notificación. Hay que generalizar `presentAlert` a todos los proveedores con una sola regla. | P0 |
| L4 | Reglas de privacidad: modo "ocultar contenido sensible" (mensajes) en pantalla compartida o grabación. | P2 |

### 3.3 Plantillas y diseño (P1)

| # | Falta | Prioridad |
|---|---|---|
| D1 | **Plantilla expandida estándar** con regiones leading / trailing / center / bottom (como `DynamicIslandExpandedRegion`), márgenes concéntricos y `ContainerRelativeShape`. Hoy cada tarjeta es un diseño suelto. | P1 |
| D2 | **Alto dinámico** de la expandida (84–160 pt) según contenido, con animación de layout que conserve elementos. | P1 |
| D3 | Medidas de referencia de Apple como tokens (`DesignTokens`): compacta, mínima, 28 pt, márgenes y radios. | P1 |
| D4 | Keyline teñida **por actividad** (hoy es una por el contenido mostrado). | P2 |
| D5 | Auditoría de animaciones ≤ 2 s y transiciones de contenido (`numericText`) en temporizador, carga y progreso. | P1 |
| D6 | Revisar el **margen extra** que notaste alrededor del notch (cápsula y bolitas). Por ahora está bien; queda anotado. | P2 |

### 3.4 Más integraciones Mac (equivalentes a lo que hace el iPhone) (P1/P2)

Factibilidad: ✅ API pública sin permisos raros · ⚠️ requiere permiso o heurística · ❌ no hay forma pública.

| Evento del iPhone | Equivalente Mac | Factible |
|---|---|---|
| Cámara/micro en uso (puntos verde y naranja) | Indicador de **cámara en uso** y **micro en uso** (CoreMediaIO / CoreAudio `IsRunningSomewhere`, sin usar el micro) | ✅ |
| Grabación de pantalla | Detectar grabación activa (ventana o indicador del sistema) | ⚠️ |
| Notas de Voz grabando | Micro en uso + app Notas de Voz al frente o activa | ✅ |
| Modo silencio / Acción | **Bloq Mayús**, modo **Concentración** (Focus) activado o desactivado | ✅ / ⚠️ (Focus necesita Acceso total al disco o una heurística) |
| Batería baja / carga | Ya hay carga; falta **batería baja (20 % y 10 %)** y "carga completa" | ✅ |
| Descargas | **Progreso de descargas** de Safari y Finder (`NSProgress` sobre `~/Downloads`) | ✅ |
| Hotspot / conexión | Conexión a **Wi-Fi o VPN** (el tipo `vpn` ya existe sin proveedor) | ✅ |
| Calendario | **Próxima reunión** en 5 min, con botón para unirse (EventKit, con permiso) | ⚠️ |
| Cronómetro | Cronómetro como actividad (hoy sólo temporizador) | ✅ |
| Face ID / Apple Pay | Touch ID o Apple Pay en Mac | ❌ (no hay evento público) |
| Mapas, Encontrar, SharePlay | — | ❌ |
| Live Activities del iPhone | Ya salen en la barra de menús del Mac, pero sin API para leerlas | ❌ |

### 3.5 Plataforma para otras apps (P2, clave para "abarcar mercado")

| # | Falta |
|---|---|
| X1 | **API pública de Live Activities** de Dynamic Notch: formalizar el servidor IPC (`/claude`, `/progress`, `/timer`) como un contrato estable al estilo `ActivityAttributes` / `ContentState`. JSON ≤ 4 KB con plantillas compacta, mínima y expandida; iniciar, actualizar y terminar; `relevance`, `staleDate` y `alert`. |
| X2 | CLI (`dynamicnotch activity start …`), esquema de URL y Atajos (App Intents) para iniciar actividades desde scripts y Atajos. |
| X3 | Documentación para desarrolladores y ejemplos (GitHub Actions, builds de Xcode, renders, descargas). |

### 3.6 Estabilidad, rendimiento y deuda técnica (P0)

| # | Falta |
|---|---|
| S1 | **Matriz de pruebas manuales** (sección 6) recorrida completa en cada versión. |
| S2 | 1 cuadro lento (40–60 ms) al abrir el reproductor por primera vez: precalentar la vista. |
| S3 | Verificación **visual** de la gota en modo cristal (hoy sólo geométrica). |
| S4 | Pruebas automáticas de la lógica pura: arbitraje de `ActivityCenter`, `LiquidDropProfile` y gestos. Hoy no hay carpeta `Tests`. |
| S5 | **Separar responsabilidades** (como recomienda Apple y como necesita la Fase B). `NotchContainerView` tiene 1 558 líneas, `AppState` 1 022 y `ActivityCenter` 739, y mezclan datos, política, geometría y dibujo. Ver sección 4. |
| S6 | Limpieza de documentos viejos en la raíz (`PLAN_GEMINI_*`, `REPORTE_*`, etc.) y actualizar `ARCHITECTURE.md`. |
| S7 | Ya corregido hoy: animación de AirPods al relanzar la app (gracia de 6 s), clic muerto en bolitas y `frontmostApplication` desactualizado. |

---

## 4. Arquitectura objetivo (prepara la Fase B)

La isla sin notch debe usar **el mismo código** que el notch. Sólo cambia la geometría de la superficie.

```
Proveedores ──▶ ActivityStore (modelo: identidad, datos, relevancia, ciclo de vida, stale, alertas)
                     │
                     ▼
              PresentationEngine (política pura y probable con tests):
                 una → compacta · 2-3 → mínima pegada + separadas · ancho limitado · alertas · swipe/cola
                     │  produce IslandLayout (qué actividad, qué presentación, en qué slot)
                     ▼
              ShapeEngine (ElasticPill + contorno líquido + resortes) ◀── SurfaceGeometry
                     │                                                  (notch físico | isla flotante)
                     ▼
              Renderer (SwiftUI: negro / cristal, contenido, keyline)
```

- **`SurfaceGeometry`** reemplaza los usos directos de `NotchGeometry`. Campos:
  - `centerX` y `topInset`: 0 si cuelga del borde; ≈ 6–8 pt si flota.
  - `restSize` y `cornerStyle`: "cuelga del borde" (notch) o "cápsula flotante" (isla).
  - `cameraCutout`: el ancho que debe quedar vacío en el centro; 0 sin cámara.
  - `screen`.
- **`PresentationEngine`** saca de `ActivityCenter` la lógica de roles y bolitas. Recibe la lista de actividades y devuelve el layout, sin SwiftUI, así que se puede probar.
- **`NotchContainerView`** se parte en `IslandSurfaceView` (forma y material), `CompactRegionView`, `MinimalSlotView` y `ExpandedRegionView`.

---

## 5. Fases y orden de trabajo

### Fase A — Dynamic Notch estable (en este orden)

| Paso | Contenido | Ítems |
|---|---|---|
| A-1 ✅ | **Refactor de base, sin cambios visibles:** `SurfaceGeometry` y `PresentationEngine` con tests de arbitraje (22 tests, `./scripts/test.sh`). | S5, S4 |
| A-2 ✅ | **Política de varias actividades:** 1 pegada + hasta 2 separadas (derecha, luego izquierda), posiciones estables, sin choques; mínima pegada de la música; ancho limitado. Pendiente: mínima pegada para actividades tipo píldora (llamada, temporizador sin música). | A2, A3, A1, A4 |
| A-3 ✅ | **Interacción:** swipe a lo ancho recorre el carrusel de bolitas y cola (sólo si el gesto empieza sobre la isla); clic en una bolita con ajuste (abrir app / traer al notch / expandir); relevancia dinámica con **escala única** (`ActivityRelevance`), +100 al pedir atención y temporizador en su último minuto. De paso: las bolitas vuelven a **brotar y reabsorberse** en vivo (la transición de SwiftUI no les pasaba su valor en macOS 27) y la gota sale de debajo de la isla sin tapar su contenido. Pendiente: que el carrusel incluya la actividad del notch (música). | A5, A6, A8 |
| A-4 ✅ | **Alertas y ciclo de vida unificados:** `ActivityAlertConfiguration` por actualización (expande en bolita o en el notch, sonido opcional, máx. una cada 30 s por actividad salvo urgentes, nunca si el usuario está usando el notch); límite de 8 h; `staleDate` → bolita atenuada (Claude a los 10 min sin reportar, agentes a los 30 s); `ActivityCenter.end` muestra el resumen (ajuste "Resumen al terminar", 15 s) y se reabsorbe. Reglas puras en `ActivityLifecycle` con tests. | L3, L1, L2 |
| A-5 ✅ | **Plantillas:** `IslandExpandedTemplate` con regiones (lados de la cámara, centro, abajo), márgenes de 14 pt y `ContainerRelativeShape` concéntrico; alto dinámico 84–160 pt según el contenido (`reportExpandedContentHeight`); `DefaultActivityExpandedView` para las actividades sin tarjeta propia (antes un botón "Cerrar"); `IslandMetrics` con las medidas de la HIG; auditoría ≤ 2 s (las únicas > 2 s son de la pantalla bloqueada y la salida/regreso de las bolitas, que Apple trata aparte). | D1, D2, D3, D5 |
| A-6 ✅ | **Integraciones:** `SystemStatusActivityProvider` (Bloq Mayús, sin internet/conectado, VPN de túnel completo, cámara y micrófono en uso consultando `IsRunningSomewhere` sin abrirlos) y `DownloadsActivityProvider` (progreso de archivos publicado en Descargas, una sola actividad, resumen al terminar). Batería baja (20/10/5 %) y cronómetro ya existían. Las de indicador usan `prefersBubble` para no quitarle el notch a la música. Ajustes > Actividades > Integraciones del sistema. Sin probar en vivo: pérdida de red y VPN. | 3.4 (✅) |
| A-7 ✅ | **Pulido y rendimiento:** fuera del hilo principal la detección de pantalla completa (CGWindowList cada 0.8 s), el sondeo de brillo (cada 0.15 s) y la lista de apps de WhatsApp; 0 cuadros lentos en reposo. La apertura del reproductor queda en 1 cuadro lento (crear su vista; dejarla montada subiría el CPU). Cristal verificado a ojo (alas, gota con cuello, tarjeta, reproductor) y corregido un contorno que se veía sobre el centro negro. Ver resultado de la matriz en §6. | S2, S3, S1 |
| A-8 | **Release 2.0** "notch estable": changelog y `ARCHITECTURE.md` actualizado. | S6 |

### Fase B — Isla Dinámica para Macs sin notch

| Paso | Contenido |
|---|---|
| B-1 | **Pantallas.** Descubrir todas las pantallas; perfil por pantalla: notch físico → notch; sin notch → isla. Reacciona a conectar o desconectar monitores, cambios de resolución y Spaces. |
| B-2 | **Geometría de la isla.** Cápsula flotante, sin cámara; tamaño en reposo de referencia como el iPhone (≈ 126 × 37 pt, escalado a la barra de menús). Dos estilos configurables:<br>• **Flotante (iPhone):** cápsula completa centrada arriba, separada del borde unos pt; puede encimarse a la zona central de la barra de menús, que suele estar vacía.<br>• **Colgante (notch virtual):** pegada al borde superior, con la misma forma que el notch. |
| B-3 | **Ventanas.** Un panel por pantalla, o un panel que viaja con animación. Ajuste: "mostrar en: pantalla del notch / pantalla activa (donde está el cursor o la ventana con foco) / todas". |
| B-4 | **Reposo.** Ajuste "en reposo: cápsula visible (como iPhone) / ocultar hasta que haya actividad". Sin cámara, el centro **podría** usarse para contenido, pero por defecto se respeta el hueco central para que se vea idéntica al iPhone; se puede desactivar. |
| B-5 | **Material.** Negro opaco por defecto, con keyline en modo oscuro. En cristal, como no hay cámara, **toda** la cápsula puede ser vidrio (regular sobre fondos claros o clear + 35 % según el fondo). |
| B-6 | **Convivencia con macOS:** barra de menús que se oculta sola, pantalla completa, Mission Control, otra app en la parte superior, pantalla bloqueada en el monitor externo y clics que pasan a la barra de menús. |
| B-7 | **Ajustes:** pestaña o sección "Pantallas e Isla": activar en pantallas sin notch, estilo, tamaño, desplazamiento vertical, pantallas donde aparece y comportamiento en reposo. |
| B-8 | **Pruebas en tu monitor secundario.** Primero el reposo y la compacta con música, luego varias actividades, gestos, cristal y pantalla completa. |
| B-9 | **Release 2.1** "Isla Dinámica para cualquier Mac". |

---

## 6. Lista de aceptación para "Notch estable y 100 % funcional"

Se recorre completa antes de pasar a la Fase B, en modo negro y en los dos cristales:

1. **Reposo:** sin actividad el notch no se ve; sin tirones en 10 min (`/debug/hitches` = 0).
2. **Música:**
   - Alas, barras que siguen la canción, cambio de pista y pausa → reposo en 30 s.
   - Abrir y cerrar con clic, swipe y cierre interactivo, sin congelarse.
3. **HUD:** volumen, brillo y AirPods. Se recoge todo, regresa tras la pausa, sin fantasmas y **sin animación al relanzar la app**.
4. **Varias actividades:**
   - Música + temporizador + Claude + repisa a la vez: nunca se enciman, cada una en su lugar.
   - Swipe recorre, clic abre o cambia, mantener expande.
5. **Alertas:** Claude terminado o con permiso, llamada, AirDrop y mensaje. Cada una expande unos segundos y regresa a su lugar.
6. **Repisa:** soltar en toda la tarjeta, sin Touch ID, y devolver archivos.
7. **Pantalla bloqueada:** compacta ⇄ completa, letras sincronizadas y sin quedar pegado.
8. **Pantalla completa:** el notch se esconde con video o música y vuelve al salir.
9. **Accesibilidad:** Reducir movimiento, Reducir transparencia y Aumentar contraste.
10. **Rendimiento:** ≤ 1 cuadro lento por apertura del reproductor; CPU en reposo < 1 %.
11. **Ajustes:** todo lo nuevo es configurable y se guarda.

### Resultado de la matriz (A-7, 19 de octubre de 2026)

| # | Punto | Estado |
|---|---|---|
| 1 | Reposo sin tirones | ✅ 0 cuadros lentos en 60 s (3604 cuadros) con música en las alas |
| 2 | Música: alas, abrir y cerrar | ✅ abrir/cerrar sin congelarse · ⏳ swipe y cambio de canción, en tus manos |
| 3 | HUD de volumen / AirPods | ✅ volumen: aparece, se va y regresa lo anterior · ✅ sin animación de AirPods al relanzar |
| 4 | Varias actividades | ✅ música + Claude + temporizador + agente: sin encimarse, lugares estables, recorrido con swipe (simulado) |
| 5 | Alertas | ✅ resumen al terminar (agente) · ⏳ Claude terminó / llamada / AirDrop / mensaje en vivo |
| 6 | Repisa | ⏳ soltar archivos reales |
| 7 | Pantalla bloqueada | ⏳ (no se puede bloquear desde aquí) |
| 8 | Pantalla completa | ⏳ |
| 9 | Accesibilidad | ⏳ (son ajustes del sistema) |
| 10 | Rendimiento | ✅ 1 cuadro lento por apertura del reproductor · ⚠️ CPU con música 17 % (captura de audio y barras); sin música, por medir |
| 11 | Ajustes | ✅ todo lo nuevo en Ajustes > Actividades, guardado en UserDefaults |

⏳ = lo tienes que probar tú (necesita manos, el sistema o bloquear la Mac).

### Pendientes antes del release 2.0 — resueltos el 19 de octubre de 2026

| # | Pendiente | Arreglo |
|---|---|---|
| 1 | La bolita de Claude cambiaba de escritorio | El clic abre la app sólo si tiene una ventana visible en el escritorio actual (o no está abierta); si no, abre la tarjeta ahí mismo (`ActivitySourceApp`). |
| 2 | Alerta con Claude a la vista | No se alerta si la app de la actividad tiene una ventana visible en pantalla (urgentes sí). |
| 3 | Barras ocultas con bolitas | "Mínima pegada" apagada por defecto (llave nueva); se puede encender en Ajustes. |
| 4 | Pantalla completa no escondía el notch | En una MacBook con notch la ventana "Menubar" nunca se va; señal nueva: `AXFullScreen` de la ventana enfocada. Se esconde si algo suena o si la app es de video o un navegador. `/debug/fullscreen`. |
| 5 | Zona para soltar del ancho del notch | La invitación también se abre al entrar al rectángulo de la tarjeta (antes sólo por distancia al centro). Probado con un arrastre sintético entrando por los lados. |
| 6 | Cuadros raros de la bolita de la repisa | Las bolitas recuerdan su lado (`assignSides`): ya no brincan de lado cuando se va otra. Con el notch abriéndose, la que se va se desvanece en vez de reabsorberse en una tarjeta que crece. Al cerrar la repisa, su bolita espera a que el notch termine de recogerse. |
| 7 | Sacudida de la isla | Retroceso de 1.4 pt y estirón mínimo con rebote al soltar la gota; empujón de 1.2 pt al recibirla (`islandRecoil`/`islandJiggle`). |
| 8 | "Dynamic Notch Tap" en las salidas | Filtrado del selector (el dispositivo ya era privado para macOS). |
| 9 | Animaciones de Liquid Glass | Al cerrar sin música el vidrio se disuelve durante el encogimiento; con música, la forma se encoge hasta las alas de vidrio sin cortes. |
| 10 | Bloq Mayús | Texto "Minúsculas" (cabe en el ala); se comporta como el HUD de volumen: notch limpio y la música regresa tras la pausa (`isSystemNotice`). |

---

## 7. Límites honestos

- No podemos leer las Live Activities reales del iPhone ni eventos privados del sistema (Face ID, Apple Pay, Mapas).
- Lo que sí podemos es ofrecer **nuestra propia API de actividades** (X1–X3) para que otras apps, scripts y agentes se integren. Eso es lo que abre mercado.
- Las medidas y tiempos internos de las animaciones de Apple no son públicos. Las nuestras se calibran a ojo con el Animation Studio, dentro del límite de 2 s.
