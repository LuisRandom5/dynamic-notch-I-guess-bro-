import AppKit
import Contacts
import CoreBluetooth
import EventKit
import SwiftUI

// MARK: - Bienvenida y permisos
// Una sola ventana con todos los permisos que usa la app: cada uno dice para qué sirve, si ya está concedido y tiene
// su botón. Sale la primera vez que se abre cada versión beta (y siempre que falte Accesibilidad, como antes); se
// vuelve a abrir desde el menú de la barra → "Permisos…".
public struct WelcomeView: View {
    @ObservedObject private var interceptor = VolumeInterceptorService.shared
    public var onClose: () -> Void

    @State private var accessibility = false
    @State private var calendar = false
    @State private var contacts = false
    @State private var bluetooth = false
    @State private var timer: Timer?

    public init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "capsule.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 6)
                Text(L("Bienvenido a Dynamic Notch"))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(L("Para que la isla muestre todo, macOS necesita tu permiso. Sólo Accesibilidad es necesaria; lo demás es opcional y puedes darlo después."))
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                PermissionRow(icon: "slider.horizontal.3", title: L("Accesibilidad"), badge: L("Necesario"),
                              detail: L("Volumen, brillo y teclas multimedia en la isla, y avisos de otras apps."),
                              granted: accessibility, actionTitle: L("Abrir Ajustes")) {
                    interceptor.requestAccessibilityPermission()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                PermissionRow(icon: "calendar", title: L("Calendario"), badge: L("Opcional"),
                              detail: L("Tu próxima reunión con la cuenta regresiva y el botón para unirte. Sólo se lee."),
                              granted: calendar, actionTitle: L("Permitir")) {
                    AppState.shared.calendarActivityEnabled = true
                }
                PermissionRow(icon: "person.crop.circle", title: L("Contactos"), badge: L("Opcional"),
                              detail: L("La foto y el nombre de quien te llama o te escribe."),
                              granted: contacts, actionTitle: L("Permitir")) {
                    ContactLookupService.shared.requestAccess { _ in }
                }
                PermissionRow(icon: "airpods", title: L("Bluetooth"), badge: L("Opcional"),
                              detail: L("La animación y la batería de tus AirPods al conectarlos."),
                              granted: bluetooth, actionTitle: L("Permitir")) {
                    AirPodsBLEMonitor.shared.scan(for: 2)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(L("Música, Safari y WhatsApp Web: la primera vez macOS te preguntará si Dynamic Notch puede controlarlas. Acepta para ver canciones y mensajes."),
                      systemImage: "music.note")
                Label(L("Barras de la música: macOS pedirá escuchar el audio del sistema mientras algo suena. No se graba ni se guarda nada."),
                      systemImage: "waveform")
            }
            .font(.system(size: 11.5))
            .foregroundColor(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            if BuildFlavor.isBeta {
                Text(L("Es una beta: si algo falla o se ve raro, usa \"Enviar comentarios…\" en el menú de la barra."))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.yellow.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onClose) {
                Text(accessibility ? L("Listo") : L("Más tarde"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(accessibility ? Color.blue : Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(22)
        .frame(width: 460)
        .background(Color(red: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x1A / 255.0))
        .environment(\.colorScheme, .dark)
        .onAppear {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                DispatchQueue.main.async { refresh() }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func refresh() {
        let trusted = interceptor.checkPermission() || interceptor.isIntercepting
        if trusted && !accessibility { interceptor.startInterception() }
        accessibility = trusted
        calendar = CalendarActivityProvider.isAuthorized
        contacts = CNContactStore.authorizationStatus(for: .contacts) == .authorized
        bluetooth = CBManager.authorization == .allowedAlways
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let badge: String
    let detail: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.10)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(DesignTokens.green)
            } else {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Ventana
public final class WelcomeWindowController: NSWindowController {
    public static let shared = WelcomeWindowController()
    private static let shownVersionKey = "welcomeShownForVersion"

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L("Bienvenida y permisos")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        // Mismo fondo que la vista: sin él, la barra de título transparente quedaba como una franja blanca
        window.backgroundColor = NSColor(red: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x1A / 255.0, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        super.init(window: window)
        window.contentView = NSHostingView(rootView: WelcomeView(onClose: { [weak self] in self?.close() }))
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Al arrancar: la beta la muestra una vez por versión; además, si falta Accesibilidad y no se pospuso
    public static func showIfNeeded() {
        let firstRunOfBeta = BuildFlavor.isBeta && UserDefaults.standard.string(forKey: shownVersionKey) != currentVersion
        let missingAccessibility = !VolumeInterceptorService.shared.checkPermission()
            && !UserDefaults.standard.bool(forKey: "hasDismissedAccessibilityPrompt")
        guard firstRunOfBeta || missingAccessibility else { return }
        UserDefaults.standard.set(currentVersion, forKey: shownVersionKey)
        showAlways()
    }

    public static func showAlways() {
        shared.window?.center()
        shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Diagnóstico (/debug/render-welcome): abre la ventana y guarda una imagen de lo que muestra
    public static func snapshot(to path: String) {
        showAlways()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let view = shared.window?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }

    public override func close() {
        UserDefaults.standard.set(true, forKey: "hasDismissedAccessibilityPrompt")
        super.close()
    }
}
