import AppKit
import Combine
import SwiftUI

/// Servicio de detección de aplicaciones en pantalla completa (videos de YouTube, reproductores, juegos, etc.)
/// Cierra automáticamente el reproductor o la bandeja expandida para no obstruir la experiencia de video.
public final class FullScreenDetectorService: ObservableObject {
    public static let shared = FullScreenDetectorService()
    
    @Published public private(set) var isFullScreenActive: Bool = false
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        startMonitoring()
    }
    
    public func startMonitoring() {
        // 1. Escuchar cambio de Space activo (cuando macOS cambia a un espacio de pantalla completa)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.checkFullScreenState()
            }
            .store(in: &cancellables)
        
        // 2. Escuchar cambios de pantallas
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.checkFullScreenState()
            }
            .store(in: &cancellables)
        
        // 3. Temporizador ligero para detectar cuando una ventana entra o sale de fullscreen
        // (cada 1.5 s: entrar o salir de pantalla completa cambia el Space y eso ya avisa al instante)
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkFullScreenState()
        }
        timer?.tolerance = 0.3
    }
    
    /// La lista de ventanas del sistema cuesta decenas de ms: se consulta fuera del hilo principal (antes, cada
    /// 0.8 s, robaba cuadros a las animaciones del notch)
    private let queue = DispatchQueue(label: "com.luisrandom.DynamicNotch.FullScreenDetector", qos: .utility)
    private var isChecking = false

    public func checkFullScreenState() {
        guard !isChecking, let screen = ScreenService.shared.targetScreen ?? NSScreen.main else { return }
        isChecking = true
        let screenFrame = screen.frame
        let myPID = ProcessInfo.processInfo.processIdentifier
        queue.async { [weak self] in
            let isFS = Self.anotherAppCoversScreen(screenFrame: screenFrame, myPID: myPID)
            DispatchQueue.main.async {
                self?.isChecking = false
                self?.apply(isFS: isFS)
            }
        }
    }

    private static func anotherAppCoversScreen(screenFrame: CGRect, myPID: pid_t) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for win in windowList {
            guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = win[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
                  let boundsDict = win[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            // Si la ventana de otra aplicación ocupa esencialmente toda la pantalla (con tolerancia de 4pt)
            if rect.width >= (screenFrame.width - 4) && rect.height >= (screenFrame.height - 4) {
                return true
            }
        }
        return false
    }

    private func apply(isFS: Bool) {
        if self.isFullScreenActive != isFS {
            DispatchQueue.main.async {
                self.isFullScreenActive = isFS
                if isFS {
                    // Si el minirreproductor o bandeja está abierto, cerrarlo inmediatamente
                    let appState = AppState.shared
                    if appState.mode == .expanded || appState.mode == .shelf {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            appState.mode = .idle
                            appState.isPlayerDetailExpanded = false
                        }
                    }
                } else {
                    let appState = AppState.shared
                    if appState.shouldShowCompact && appState.mode == .idle {
                        withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                            appState.mode = .compact
                        }
                    }
                }
            }
        }
    }
}
