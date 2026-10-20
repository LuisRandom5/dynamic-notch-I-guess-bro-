# Dynamic Notch — beta

¡Gracias por probarla! Es la Isla Dinámica del iPhone en tu Mac: música, AirPods, carga, volumen, mensajes de WhatsApp Web, AirDrop, temporizador y más, todo en el notch (o en una isla flotante si tu Mac no tiene notch).

## Qué necesitas

- Un Mac con chip de Apple (M1 o más nuevo).
- macOS 14 Sonoma o posterior.

## Instalar

1. Descomprime el `.zip` y arrastra **DynamicNotch.app** a tu carpeta **Aplicaciones**.
2. Ábrela con doble clic. Como la beta todavía no está firmada por Apple, macOS dirá que no puede verificarla y no la abrirá. Es normal.
3. Ve a **Ajustes del Sistema → Privacidad y seguridad**, baja hasta el final y haz clic en **Abrir de todos modos** junto a "DynamicNotch". Confirma con tu contraseña o Touch ID.
4. Se abre la ventana de **Bienvenida y permisos**. Sólo **Accesibilidad** es necesaria: haz clic en "Abrir Ajustes" y activa **Dynamic Notch** en la lista. Lo demás (Calendario, Contactos, Bluetooth) es opcional.

La app no tiene ícono en el Dock: vive en el notch y en el menú de la barra superior (el ícono de Dynamic Notch). Desde ese menú están **Ajustes**, **Permisos…**, **Enviar comentarios…** y **Salir**.

La primera vez que pongas música en Safari o Spotify, o que llegue un mensaje de WhatsApp Web, macOS te preguntará si Dynamic Notch puede controlar esa app: acepta para ver canciones y mensajes.

## Si algo falla

Menú de la barra → **Enviar comentarios…** Se guarda en tu escritorio un `.zip` con el registro de la app y datos de tu Mac. Mándamelo y cuéntame qué hacías y a qué hora pasó. No incluye el texto de tus mensajes, pero sí puede traer nombres de contactos o de canciones.

## Actualizar a una beta nueva

Sal de la app (menú → Salir), borra la versión anterior de Aplicaciones y pon la nueva. Si el volumen o el brillo dejan de salir en la isla, ve a **Privacidad y seguridad → Accesibilidad**, apaga y vuelve a encender **Dynamic Notch** (macOS lo pide con cada versión nueva de una app sin firmar).

## Privacidad

Todo se queda en tu Mac. La app sólo se conecta a internet para:

- bajar de Apple la animación oficial de tus AirPods (la primera vez),
- buscar la letra de la canción (lrclib.net) y carátulas que falten (iTunes de Apple).

No se graba audio ni se usa el micrófono: las barras de la música escuchan el audio del sistema sólo mientras algo suena.

## Desinstalar

Menú → Salir, y borra **DynamicNotch.app** de Aplicaciones. Si quieres borrar también sus datos: en Finder, menú Ir → Ir a la carpeta… y borra `~/Library/Application Support/com.luisrandom.DynamicNotch` y `~/Library/Caches/com.luisrandom.DynamicNotch`.
