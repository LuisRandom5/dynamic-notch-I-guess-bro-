# 🏝️ Mac Dynamic Notch

> **Isla Dinámica para el Notch de las MacBook**, creada con React, Tailwind CSS y Motion. Transforma el notch de la Mac en una superficie interactiva fluida con reproductor de música, notificaciones del sistema y animaciones estilo Apple.

---

## ✨ Características

- 🍏 **Diseño idéntico a Apple & Notch físico:** Módulo de cámara FaceTime HD, sensor de luz y LED verde/ámbar de privacidad.
- ⚡ **Animaciones de Resorte (Spring Physics):** Transiciones orgánicas entre modo *Idle*, *Flancos Compactos* (ecualizador + arte del álbum) y *Expandido*.
- 🎵 **Controlador de Música Completo:**
  - Sintetizador Web Audio API incorporado con reproducción en tiempo real.
  - Ecualizador de ondas reactivo en vivo.
  - Barra de búsqueda (*scrubber*), volumen, cambio de pistas y selector de listas de reproducción.
  - Conmutador de salida de audio (AirPods Pro con Audio Espacial / Altavoces).
- 🔔 **Notificaciones de Sistema Interactivas:**
  - **AirDrop:** Recepción de archivos con barra de descarga interactiva.
  - **MagSafe:** Animación de carga rápida con porcentaje de batería.
  - **Temporizador:** Cuenta regresiva Pomodoro en vivo con pausa y ajuste de tiempo.
  - **Batería Baja:** Alerta de aviso del 12%.
  - **Cámara & Micrófono:** Alerta de privacidad que enciende el LED verde en el notch.
  - **FaceTime Audio:** Llamada entrante con botones para contestar o rechazar.
  - **Portapapeles & Notch Shelf:** Bandeja para soltar y guardar archivos, notas y enlaces rápidos.
- 💻 **Doble Modo:**
  - **Modo Simulación de Escritorio:** Con fondos oficiales de macOS, barra de menús y dock interactivo.
  - **Modo Notch Real (Overlay):** Diseñado para correr en pantalla completa o como app de escritorio flotante sobre tu propio notch.

---

## 🚀 Cómo ejecutarlo en local

1. Clona el repositorio:
   ```bash
   git clone https://github.com/LuisRandom5/dynamic-notch-I-guess-bro-.git
   cd dynamic-notch-I-guess-bro-
   ```

2. Instala las dependencias:
   ```bash
   npm install
   ```

3. Inicia el servidor de desarrollo:
   ```bash
   npm run dev
   ```

4. Abre `http://localhost:3000` en tu navegador.

---

## 🖥️ ¿Cómo convertirlo en una App real para Mac?

¡Es 100% posible usar este mismo código como app de escritorio que flote encima de tu notch en macOS!

### Opción 1: Con Electron (La forma más rápida)
En este repositorio ya viene incluido el archivo `electron-main.cjs`.

1. Instala Electron:
   ```bash
   npm install --save-dev electron
   ```

2. Corre la app como ventana flotante transparente:
   ```bash
   npx electron electron-main.cjs
   ```
*(La ventana se posiciona automáticamente centrada en `y: 0` y flotando por encima de todas las apps de macOS).*

### Opción 2: Con Tauri (Ultra ligera, menor consumo de RAM)
Puedes envolver este frontend de Vite en **Tauri v2**:
```bash
npm install --save-dev @tauri-apps/cli
npx tauri init
```
Configurando la ventana en `tauri.conf.json` con:
- `"decorations": false`
- `"transparent": true`
- `"alwaysOnTop": true`

---

## 🛠️ Tecnologías

- **React 19**
- **TypeScript**
- **Motion** (`motion/react`) para físicas y animaciones líquidas
- **Tailwind CSS v4**
- **Web Audio API** (Sintetizador de sonido y ecualizador en tiempo real)
- **Lucide Icons**
