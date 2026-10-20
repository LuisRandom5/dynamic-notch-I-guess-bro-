# Pruebas antes de la 2.1

Marca cada punto con ✅ o anota qué falló. Si algo se ve raro, una captura ayuda mucho.

Las demos están en el ícono de la barra de menús, submenú **Demostraciones de prueba**.

## A. Monitor sin notch (B-8)

Conecta el ASUS. En **Isla Dinámica › Dónde se ve** elige su pantalla, y en **Forma en pantallas sin notch** elige **Flotante**.

1. **Reposo:** la cápsula está centrada arriba, separada del borde y del alto de la barra de menús; no tapa menús ni íconos.
2. **Colgante:** cambia la forma a Colgante y luego regrésala a Flotante.
3. **Reconectar:** desconecta y conecta el monitor; la isla regresa sola.
4. **Música:**
   - La carátula va a la izquierda y las barras a la derecha.
   - Clic para abrir el reproductor: botones de Apple Music, y al cambiar de canción la carátula se voltea como página.
5. **Mensajes en la isla:** usa **WhatsApp: foto**. La tarjeta queda pareja arriba y abajo, sin hueco de cámara.
6. **Mission Control** (F3 o tres dedos hacia arriba): la isla se queda fija arriba.
7. **Pantalla completa:** con un video de YouTube a pantalla completa la isla se esconde, y vuelve al salir.
8. **Barra que se oculta:**
   - Ajustes del Sistema › Centro de control › Ocultar automáticamente la barra de menús › Siempre.
   - La isla debe seguir bien colocada.
   - Luego déjalo como estaba.
9. **Bloqueo:** bloquea la pantalla (Ctrl+Cmd+Q) y revisa cómo se ve el monitor.

## B. Novedades de la 2.1

10. **Carrusel con la música:**
    - Con música sonando, usa **Actividad de la API** para que salga una bolita.
    - Desliza a lo ancho sobre la isla: "Compilando" pasa al notch y la música se vuelve bolita rosa.
    - Desliza otra vez, o toca la bolita rosa: la música regresa.
11. **Mensajes seguidos:** usa **WhatsApp: dos mensajes seguidos**. Carlos se queda unos 2.5 s y luego sale Ana; ninguno tapa al otro de golpe.
12. **Mismo contacto:** usa **Notificación Dinámica** y enseguida **WhatsApp: foto**. La misma tarjeta cambia a "📷 Foto".
13. **Carga completa:** usa la demo, o espera a que llegue al 100 % con el cargador.
14. **Concentración:**
    - La demo debe mostrar la luna.
    - Luego activa No molestar de verdad desde el Centro de control y dime si sale el aviso. Si no sale, macOS 27 ya no avisa de ese cambio.
15. **Próxima reunión:**
    - La demo debe mostrar la bolita con cuenta regresiva y la tarjeta "Unirse con Meet".
    - Para probarla de verdad: Ajustes › Actividades › Integraciones › **Próxima reunión** (pide permiso de Calendario) y crea un evento dentro de 5 min.
16. **Notas de Voz:** graba algo en Notas de Voz; debe salir la onda roja con el tiempo.
17. **Ocultar mensajes al grabar:**
    - Abre Cmd+Shift+5 y graba la pantalla.
    - Usa **Notificación Dinámica**: debe decir "Mensaje nuevo".
18. **API desde la Terminal:**
    ```bash
    ./scripts/dynamicnotch run tests --title "Prueba" -- sleep 5
    ```
    Debe salir la bolita y al final la ✓ verde.
19. **Claude:** mientras trabajo, la bolita de Claude respira igual que antes, pero ya no calienta la Mac (ahora gasta ~2 % de CPU en vez de ~9 %).

20. **Atajos:** abre la app Atajos, crea un atajo nuevo y busca "Dynamic Notch". Deben salir "Mostrar actividad en la isla" y "Terminar actividad de la isla". Pruébalas con un título y un ícono, como `hammer.fill`. Si no salen, abre la app una vez desde Finder y reinicia Atajos.
21. **Inglés:** en Ajustes del Sistema › General › Idioma y región, en "Aplicaciones", agrega Dynamic Notch en English. Al reabrirla, Ajustes, menú y avisos deben verse en inglés. Luego quítalo.
22. **Bordes de color en las bolitas:** con la Mac en modo oscuro y la apariencia OLED, cada bolita tiene un borde fino de su color.

## C. Pendientes que dependen de ti

23. **WhatsApp con la pestaña de fondo:**
    - En Safari ve a Ajustes › Avanzado y marca "Mostrar funciones para desarrolladores web".
    - Luego en Ajustes › Desarrollador marca "Permitir JavaScript desde Apple Events" (pide tu contraseña) y reinicia Safari.
    - Con WhatsApp en una pestaña de fondo, los avisos deben mostrar el mensaje real (y "📷 Foto", "Sticker", etc.).
24. **Rendimiento después de unas horas:** en el Monitor de Actividad, la memoria de Dynamic Notch no debería crecer sin parar (antes llegaba a 253 MB) y la CPU debería quedar muy por debajo del 21 % de antes.

Cuando todo esté ✅, se publica la **2.1**: tag `v2.1` y la página del release con el CHANGELOG.
