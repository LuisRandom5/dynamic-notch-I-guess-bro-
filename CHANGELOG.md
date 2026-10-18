# Dynamic Notch — Historial de cambios

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
