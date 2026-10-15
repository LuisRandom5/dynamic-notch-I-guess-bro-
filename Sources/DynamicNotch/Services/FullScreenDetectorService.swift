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
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkFullScreenState()
        }
    }
    
    public func checkFullScreenState() {
        guard let screen = ScreenService.shared.targetScreen ?? NSScreen.main else { return }
        let screenFrame = screen.frame
        let myPID = ProcessInfo.processInfo.processIdentifier
        
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }
        
        var isFS = false
        for win in windowList {
            guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = win[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
                  let boundsDict = win[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            
            // Si la ventana de otra aplicación ocupa esencialmente toda la pantalla (con tolerancia de 4pt)
            if rect.width >= (screenFrame.width - 4) && rect.height >= (screenFrame.height - 4) {
                isFS = true
                break
            }
        }
        
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
