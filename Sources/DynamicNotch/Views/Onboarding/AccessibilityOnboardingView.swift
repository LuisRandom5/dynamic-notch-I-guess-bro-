import SwiftUI
import AppKit

// MARK: - AccessibilityOnboardingView (Pantalla de Onboarding para Permiso de Accesibilidad)
public struct AccessibilityOnboardingView: View {
    @ObservedObject var interceptor = VolumeInterceptorService.shared
    public var onClose: () -> Void
    
    @State private var isTrusted: Bool = false
    @State private var timer: Timer? = nil
    
    public init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Icono de cabecera estilo Apple
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.85), Color.purple.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.blue.opacity(0.35), radius: 10, x: 0, y: 5)
                
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, 10)
            
            // Título y descripción
            VStack(spacing: 8) {
                Text("Permiso de Accesibilidad")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Para reemplazar el HUD de volumen y brillo de macOS y mostrar el control exclusivo en la Isla Dinámica, Dynamic Notch necesita acceso de Accesibilidad para capturar las teclas multimedia.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
            }
            
            // Guía de 2 pasos visuales
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Text("1")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        )
                    Text("Haz clic en **Abrir Ajustes del Sistema** abajo.")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color.white.opacity(0.85))
                }
                
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Text("2")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        )
                    Text("En **Privacidad y Seguridad → Accesibilidad**, activa **Dynamic Notch**.")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color.white.opacity(0.85))
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            
            // Aviso sobre actualización y re-activación del interruptor en macOS
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 14))
                
                Text("**¿Ya aparece activado en la lista?** Al actualizar la app, macOS requiere que apagues el interruptor y lo vuelvas a encender (o borres con «-» y vuelvas a agregar Dynamic Notch) para que el sistema reconozca la nueva versión.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineSpacing(2)
            }
            .padding(12)
            .background(Color.yellow.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.yellow.opacity(0.30), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
            
            // Estado en tiempo real
            HStack(spacing: 8) {
                if isTrusted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignTokens.green)
                    Text("¡Permiso otorgado! Captura activa")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(DesignTokens.green)
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.orange)
                    Text("Esperando autorización en Ajustes del Sistema...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.60))
                }
            }
            
            // Botones de acción
            HStack(spacing: 14) {
                Button(action: {
                    UserDefaults.standard.set(true, forKey: "hasDismissedAccessibilityPrompt")
                    onClose()
                }) {
                    Text("Más tarde")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.70))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    openAccessibilitySettings()
                }) {
                    Text("Abrir Ajustes del Sistema")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 420)
        .padding(16)
        .background(Color(red: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x1A / 255.0))
        .onAppear {
            checkPermissionLoop()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func checkPermissionLoop() {
        self.isTrusted = interceptor.checkPermission()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            DispatchQueue.main.async {
                let trusted = interceptor.checkPermission()
                self.isTrusted = trusted
                if trusted {
                    interceptor.startInterception()
                    // Auto-cerrar después de 1 segundo de haber concedido el permiso
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        onClose()
                    }
                }
            }
        }
    }
    
    private func openAccessibilitySettings() {
        interceptor.requestAccessibilityPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Controller de la Ventana de Onboarding
public final class AccessibilityOnboardingWindowController: NSWindowController {
    public static let shared = AccessibilityOnboardingWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Permisos de Dynamic Notch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        
        super.init(window: window)
        
        let view = AccessibilityOnboardingView(onClose: { [weak self] in
            self?.close()
        })
        window.contentView = NSHostingView(rootView: view)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public static func showIfNeeded() {
        let hasDismissed = UserDefaults.standard.bool(forKey: "hasDismissedAccessibilityPrompt")
        if !hasDismissed && !VolumeInterceptorService.shared.checkPermission() {
            shared.window?.center()
            shared.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    public static func showAlways() {
        shared.window?.center()
        shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
