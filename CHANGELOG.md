# Dynamic Notch — Historial de cambios

## 2.1 — en preparación

### Isla Dinámica sin notch (Fase B)
- Isla flotante en Macs y monitores sin notch, con su margen superior como en el iPhone; se elige pantalla y forma (isla o notch) desde el menú.
- La bolita de una app se oculta mientras ves esa app (p. ej. la ventana de Claude en el otro monitor).

### Reproductor como Apple Music
- Botones que reaccionan al presionar, salto con triángulos animados y play/pausa más rápido.
- La carátula cambia volteándose como una página.

### Avisos al estilo iPhone
- Mensajes de WhatsApp como la notificación del iPhone: foto del contacto con el icono de la app, nombre, "ahora" y el mensaje en dos líneas, sin botones ni textos de ayuda (la X aparece al pasar el puntero).
- WhatsApp muestra el mensaje real aunque la pestaña esté en segundo plano y dice cuando es una foto, video, sticker, GIF, mensaje de voz, documento, ubicación, contacto o encuesta. Requiere activar en Safari "Permitir JavaScript desde Apple Events" (Ajustes lo indica).
- Carga y batería baja como en el iPhone: la isla se abre a lo ancho con "Cargando" o "Batería baja" y la batería con su porcentaje.

### Rendimiento
- Con música, el uso de CPU baja de ~22 % a ~13 %.
- Fuga de memoria: el interceptor de volumen y brillo retenía cada tecla pulsada (miles de eventos por hora que nunca se liberaban).
- El monitor de "app a la vista" acumulaba observadores cada vez que se reactivaba.
- Cachés de letras y carátulas con límite.
- WhatsApp: el contenido de Chrome se pide por accesibilidad una sola vez y sin `AXEnhancedUserInterface` (volvía lentas las animaciones de las ventanas del navegador); a Safari ya no se le pide.

- En reposo la CPU baja de ~8.6 % a ~2 %:
  - Los avisos del Centro de notificaciones se detectan por evento (macOS avisa cuando aparece uno) en vez de revisar 8 veces por segundo; además se reemplazan más rápido (~20 ms).
  - El detector de llamadas sólo revisa el Centro de notificaciones mientras hay un aviso, y busca entre las apps de llamadas en vez de entre todas las apps abiertas.
  - WhatsApp lee 8 chats en vez de 15 y baja el ritmo cuando la lista no cambia.
  - Pantalla completa se revisa cada 1.5 s (los cambios de escritorio avisan al instante) y el fondo sólo se analiza con cristal adaptable.

### Diseño
- En la isla flotante (sin cámara) las tarjetas de mensaje quedan parejas arriba y abajo, como en el iPhone.
- El color del avatar de un contacto ya no cambia en cada arranque.

### Estabilidad
- El canal local de Claude y los agentes (puerto 48123) reintenta abrirse si al arrancar sigue ocupado por la instancia anterior; antes quedaba muerto hasta reiniciar la app.

### Privacidad
- El log de diagnóstico (/tmp/notch_dnd.log) ya no guarda el texto de los mensajes, sólo es legible por tu usuario y rota a los 5 MB.

### Convivencia con macOS
- La isla se queda fija durante Mission Control.

## 2.0 — 19 de octubre de 2026

La "Fase A" del plan: el notch se comporta como la Isla Dinámica del iPhone (estudiada en las guías de Apple de Live Activities y Liquid Glass) y queda listo para llevarse a Macs sin notch.

### Varias actividades, como la Isla Dinámica
- Hasta 3 a la vista: una en el notch y una bolita a cada lado; el resto espera en cola.
- Cada bolita recuerda su lado: ya no brincan cuando otra llega o se va.
- Deslizar a lo ancho sobre la isla recorre las actividades (bolitas y cola).
- Clic en una bolita configurable: abrir su app, traerla al notch o expandirla; mantener presionado siempre la expande.
- La bolita de Claude abre su tarjeta en el escritorio donde estás (ya no te lleva al escritorio de la app).
- Una sola escala de relevancia (0–1000): lo urgente y los avisos del sistema primero; el temporizador sube en su último minuto y lo que pide atención sube.
- "Mínima pegada" opcional (sólo la carátula junto a la cámara), apagada por defecto para conservar las barras.

### Bolitas líquidas
- Vuelven a brotar y reabsorberse en vivo: en macOS 27 la transición de SwiftUI no les pasaba su valor y aparecían de golpe.
- La gota sale de debajo de la isla, sin tapar la carátula ni el contenido del notch.
- La isla reacciona: retrocede y rebota casi imperceptible al soltar la gota, y se empuja al recibirla.
- Cuando el notch se abre, la bolita que se va se desvanece; la de la repisa espera a que el notch termine de cerrarse.
- Duración: salida 1.66 s y regreso 1.40 s.

### Alertas y ciclo de vida
- Alertas por actualización: la actividad se asoma unos segundos, con sonido opcional. Nunca más de una cada 30 s por actividad, nunca si estás usando el notch y nunca si ya tienes la app a la vista.
- Resumen al terminar (15 s, configurable) antes de reabsorberse (Claude, agentes, descargas).
- Límite de 8 h por actividad, y las que dejan de actualizarse se ven atenuadas.

### Tarjetas expandidas
- Plantilla de Apple con regiones alrededor de la cámara, márgenes concéntricos y alto según el contenido (84–160 pt).
- Las actividades sin tarjeta propia usan una tarjeta estándar: icono, dato vivo, título, progreso y "Abrir".

### Integraciones nuevas
- Bloq Mayús: aviso breve que se comporta como el HUD de volumen (notch limpio y la música regresa tras la pausa).
- Sin internet / conectado y VPN activada o desactivada.
- Bolita verde (cámara) o naranja (micrófono) mientras alguna app los usa. Sólo se consulta si están en uso: Dynamic Notch nunca los abre.
- Descargas en curso (Safari y apps que publican su progreso) en una sola bolita con anillo.

### Arreglos
- Pantalla completa: el notch se esconde con video, música o navegador a pantalla completa (antes no detectaba la pantalla completa en MacBook con notch). Al salir aparece limpio y abre sus alas a los 3 s.
- Repisa: la invitación aparece y se pone verde en toda la tarjeta, también llegando de lado.
- AirPods: sin animación al relanzar la app; tras su animación el notch se recoge y la música vuelve con la suya.
- El clic en las bolitas responde siempre (antes se perdía el clic corto).
- "Dynamic Notch Tap" ya no aparece en Salida de audio.
- Liquid Glass: al cerrar, el vidrio se disuelve o se encoge hasta las alas, sin cortes, y sin el contorno que se veía sobre el centro negro.
- Rendimiento: sin trabajo periódico en el hilo principal (pantalla completa, brillo, WhatsApp); 0 cuadros lentos en reposo.
- El logo de Claude ya no gira.

### Para desarrolladores
- `SurfaceGeometry` (notch físico, notch virtual o isla flotante) y `PresentationEngine` (política pura): base para la isla en Macs sin notch.
- 45 pruebas unitarias (`./scripts/test.sh`).
- Diagnóstico: `/debug/cycle`, `/debug/expand`, `/debug/sample-activity`, `/debug/appearance`, `/debug/fullscreen`; `/debug/activities` y `/debug/hit` muestran más estado.
- Plan completo en `PLAN_ISLA_DINAMICA.md`.

## 1.9 — 18 de octubre de 2026

Versión estable que reúne el trabajo de los días 17 y 18 de octubre: los 7 desafíos del hand-off, Liquid Glass según la guía de Apple, física líquida de las bolitas calcada de la Isla Dinámica, reproductor de pantalla bloqueada rediseñado, AirDrop propio y mucho pulido de animaciones.

### Bolitas de actividades en vivo
- Diseño estilo iPhone: del alto de la cápsula, círculo con margen, anillo grueso con pista tenue e icono centrado.
- Nacimiento calcado de la Isla Dinámica: la gota nace dentro del extremo del notch, asoma comprimida, se vuelve un "cacahuate" unido por una cintura gruesa, la cintura se adelgaza hasta un hilo y se separa con un pequeño rebote. Guardarse es lo mismo a la inversa.
- El extremo del notch se ensancha para dejarla salir y se abulta al recibirla.
- Cuello líquido también en los modos de cristal (bolita y cuello como una sola forma de vidrio).
- Al pasar el cursor sobre el notch sólo crece el notch; la bolita se queda en su lugar y se encoge un poco. Sobre la bolita, crece para invitar a tocarla.
- Un clic en una bolita (o para cerrar su tarjeta) ya no abre también el reproductor.
- Siguen al notch cuando cambia de ancho (HUD de volumen/brillo, hover) sin quedar tapadas.

### Claude en el notch
- Bolita de Claude con su logo y anillo de progreso, alimentada por hooks de Claude Code.
- Tarjeta con lo que está haciendo, uso restante de la suscripción y permisos que se autorizan desde el notch.

### Gestos y animaciones
- Desenfoque de transformación estándar (`morphBlur`): el contenido se desenfoca mientras el notch cambia de forma.
- Cierre interactivo: al deslizar hacia arriba, el reproductor/repisa/tarjeta se recoge siguiendo los dedos; al soltar se cierra o regresa. El desenfoque se mantiene hasta levantar los dedos.
- Sin desenfoque en el estiramiento de resorte ni al cambiar entre reproductor y repisa.
- Cierre sin "espasmo" y un poco más pausado; ya no se congela al final.
- Máquina de estados única para los gestos del trackpad; zona sensible ajustada a la tarjeta visible.
- Tras el volumen o el brillo, el notch se recoge por completo y vuelve a abrir sus alas a los 3 s.

### Liquid Glass
- Aplicado según "Adopting Liquid Glass" de Apple: Glass.clear con velo tipo Centro de Control, transición materialize y vibrancia en textos secundarios.
- Alas de cristal en el notch cerrado con actividad; el centro sigue negro detrás de la cámara.
- Cristal Claro = "Transparente" de iOS (nunca se adapta); Cristal Oscuro = "Con tinte" (vidrio regular sobre fondos claros).
- Reducir transparencia / Aumentar contraste se aplican al instante.

### Música y audio
- Barras con audio real capturado sólo mientras algo suena (sin indicador morado el resto del tiempo; el micrófono nunca se usa).
- Barras fieles a la canción: compensación espectral, AGC por banda, graves con más golpe y retraso de AirPods compensado.
- HUD de volumen/brillo siempre visible, por encima de lo que haya en el notch.
- Selector de salida de audio con todas las opciones a la vista.

### Pantalla bloqueada
- Reproductor compacto estilo iPhone, colocado justo arriba de la foto de perfil.
- La misma carátula crece hasta la pantalla completa y regresa (transformación continua).
- Pantalla completa estilo Apple Music: letras sincronizadas, botones animados, SF Pro, disposición estilo iOS; fondo con los colores de la carátula en todos los modos.
- Rendimiento a la frecuencia de la pantalla (antes ≤ 30 fps) y letra sincronizada con lo que se oye.

### AirDrop
- Animación propia de envío y recepción (detectada en tiempo real), palomita verde al enviar y tarjeta que abre la ubicación real del archivo.
- Intenta cerrar el aviso nativo y la ventana de Descargas que abre macOS.

### Repisa (drag & drop)
- Ya no pide Touch ID al mover archivos (sin automatizar Finder).
- Se muestra como bolita azul en lugar de ensanchar el notch.
- Se puede soltar en toda la tarjeta de "suelta aquí".

### Otros
- Temporizador como bolita en vivo (sólo icono) mientras suena música.
- WhatsApp sin notificaciones viejas ni "responder" en resúmenes.
- QuickReply devuelve el foco a la app anterior.
- Cursor de flecha sobre el notch; la ventana de ajustes ya no se abre sola.
- Herramientas de diagnóstico: `/debug/audio`, `/debug/activities`, `/debug/render-bubble`.
