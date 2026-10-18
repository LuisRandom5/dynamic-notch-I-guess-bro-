import AppKit
import SwiftUI
import Combine

/// Ventana personalizada para el Canvas Dinámico de Música
public final class AmbientCanvasWindow: NSWindow {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    
    public override func keyDown(with event: NSEvent) {
        // Presionar Escape para cerrar el Canvas inmediatamente
        if event.keyCode == 53 {
            AmbientCanvasWindowManager.shared.hideCanvas()
            return
        }
        super.keyDown(with: event)
    }
}

/// Gestor de Ventana de Escritorio para el Canvas Dinámico Ambiental con Letras
public final class AmbientCanvasWindowManager: ObservableObject {
    public static let shared = AmbientCanvasWindowManager()
    
    @Published public private(set) var isOpen: Bool = false
    private var canvasWindow: AmbientCanvasWindow?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        AppState.shared.$isAmbientCanvasOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldBeOpen in
                guard let self = self else { return }
                if shouldBeOpen && !self.isOpen {
                    self.showCanvas()
                } else if !shouldBeOpen && self.isOpen {
                    self.hideCanvas()
                }
            }
            .store(in: &cancellables)
    }
    
    public func toggleCanvas() {
        if isOpen {
            hideCanvas()
        } else {
            showCanvas()
        }
    }
    
    public func showCanvas() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showCanvas()
            }
            return
        }
        
        let targetScreen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
        let screenRect = targetScreen.frame
        
        if canvasWindow == nil {
            let window = AmbientCanvasWindow(
                contentRect: screenRect,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovableByWindowBackground = false
            window.acceptsMouseMovedEvents = true
            
            let canvasView = AmbientMusicCanvasView { [weak self] in
                self?.hideCanvas()
            }
            .environmentObject(MusicService.shared)
            .environmentObject(LyricsService.shared)
            .environmentObject(AudioDeviceService.shared)
            .environmentObject(AppState.shared)
            
            window.contentView = NSHostingView(rootView: canvasView)
            self.canvasWindow = window
        } else {
            canvasWindow?.setFrame(screenRect, display: true)
        }
        
        guard let window = canvasWindow else { return }
        window.alphaValue = 0.0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        } completionHandler: {
            self.isOpen = true
            AppState.shared.isAmbientCanvasOpen = true
        }
    }
    
    public func hideCanvas() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.hideCanvas()
            }
            return
        }
        
        guard let window = canvasWindow, isOpen else { return }
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
        } completionHandler: {
            window.orderOut(nil)
            self.isOpen = false
            AppState.shared.isAmbientCanvasOpen = false
        }
    }
}
