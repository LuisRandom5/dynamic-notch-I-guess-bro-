// macOS Desktop Wrapper for Dynamic Notch
// Run with: npx electron electron-main.cjs
const { app, BrowserWindow, screen } = require('electron');
const path = require('path');

function createNotchWindow() {
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width } = primaryDisplay.workAreaSize;

  // Notch window positioned at top center
  const notchWidth = 520;
  const notchHeight = 280;

  const win = new BrowserWindow({
    width: notchWidth,
    height: notchHeight,
    x: Math.round((width - notchWidth) / 2),
    y: 0,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    hasShadow: false,
    resizable: false,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
    },
  });

  // Makes it float over full-screen apps on macOS
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.setAlwaysOnTop(true, 'screen-saver');

  // Load local dev server or dist build
  const devUrl = 'http://localhost:3000';
  win.loadURL(devUrl).catch(() => {
    win.loadFile(path.join(__dirname, 'dist', 'index.html'));
  });
}

app.whenReady().then(createNotchWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
