import AppKit
import Combine
import SwiftUI

// MARK: - DragDetectionProbe (Sonda de Detección de Arrastre Universal y Robusta)
/// Detecta arrastres activos en macOS (Finder, escritorio, Safari, Fotos, etc.)
/// Combinando un bucle de comprobación ligero a 20 Hz (coste prácticamente 0 en reposo)
/// con monitores de eventos pasivos de AppKit sin requerir permisos especiales de accesibilidad.
public final class DragDetectionProbe: ObservableObject {
    public static let shared = DragDetectionProbe()
    
    // MARK: - Estado Publicado en Tiempo Real
    @Published public private(set) var isDragging: Bool = false
    @Published public private(set) var itemCount: Int = 0
    @Published public private(set) var detectedTypes: [String] = []
    @Published public private(set) var previewItems: [String] = []
    @Published public private(set) var cursorLocation: CGPoint = .zero
    @Published public private(set) var distanceToNotch: CGFloat = 999.0
    @Published public private(set) var verticalDistanceToNotch: CGFloat = 999.0
    @Published public private(set) var proximity: CGFloat = 0.0
    @Published public private(set) var isMouseDown: Bool = false
    @Published public private(set) var lastChangeCount: Int = 0
    @Published public private(set) var statusMessage: String = "En reposo"
    
    // MARK: - Temporizadores y Monitores
    private var heartbeatTimer: Timer?
    private var downGlobalMonitor: Any?
    private var downLocalMonitor: Any?
    private var upGlobalMonitor: Any?
    private var upLocalMonitor: Any?
    
    private var baseChangeCount: Int = 0
    private var isProbeActive: Bool = false
    private var initialMouseDownLocation: CGPoint?
    
    private init() {}
    
    // MARK: - Ciclo de Vida
    public func startProbe() {
        guard !isProbeActive else { return }
        isProbeActive = true
        
        let dragPb = NSPasteboard(name: .drag)
        baseChangeCount = dragPb.changeCount
        lastChangeCount = dragPb.changeCount
        statusMessage = "Sonda activa (0% CPU en reposo)"
        
        // Monitores pasivos de eventos: despiertan el sondeo a 20 Hz ÚNICAMENTE mientras el ratón/trackpad está presionado
        installEventMonitors()
    }
    
    public func stopProbe() {
        isProbeActive = false
        stopActiveMousePolling()
        uninstallEventMonitors()
        isDragging = false
        isMouseDown = false
        proximity = 0.0
        statusMessage = "Sonda detenida"
    }
    
    private func startActiveMousePolling() {
        guard isProbeActive, AppState.shared.enableDragDropShelf else { return }
        if heartbeatTimer == nil {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.pollDragState()
            }
            RunLoop.main.add(timer, forMode: .common)
            heartbeatTimer = timer
        }
        pollDragState()
    }
    
    private func stopActiveMousePolling() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    // MARK: - Bucle de Sondeo Inteligente (Cero coste cuando el ratón no está presionado)
    private func pollDragState() {
        let isButtonDown = CGEventSource.buttonState(.combinedSessionState, button: .left) || ((NSEvent.pressedMouseButtons & 1) != 0)
        let dragPb = NSPasteboard(name: .drag)
        let currentChangeCount = dragPb.changeCount
        
        if !isButtonDown {
            // El ratón NO está presionado: mantener sincronizado el changeCount base de reposo
            self.baseChangeCount = currentChangeCount
            self.lastChangeCount = currentChangeCount
            self.initialMouseDownLocation = nil
            
            // Detección inmediata e infalible de Drag-Out al soltar el botón del ratón:
            if let draggedItem = AppState.shared.activeDragOutItem {
                AppState.shared.activeDragOutItem = nil
                let mouseLoc = NSEvent.mouseLocation
                let visibleRect = NotchWindowManager.shared.visibleNotchScreenFrame
                let isOutsideNotch = !visibleRect.contains(mouseLoc)
                DNDLogger.log("DragDetectionProbe: Ratón soltado con archivo de repisa! item=\(draggedItem.name), mouse=\(mouseLoc), isOutside=\(isOutsideNotch), visibleRect=\(visibleRect)")
                
                if isOutsideNotch {
                    DispatchQueue.main.async {
                        DNDLogger.log("DragDetectionProbe: Removiendo \(draggedItem.name) de la repisa por soltado exterior exitoso")
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            AppState.shared.removeShelfItem(draggedItem, moveToTrash: false)
                        }
                        AppState.shared.hapticService.triggerSnap()
                        
                        if AppState.shared.shelfItems.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                AppState.shared.collapse()
                            }
                        }
                    }
                    
                    // Limpieza del archivo temporal stasheado tras breve retardo para que Finder termine la copia
                    if draggedItem.isStashed {
                        let stashedURL = draggedItem.url
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.8) {
                            if FileManager.default.fileExists(atPath: stashedURL.path) {
                                try? FileManager.default.removeItem(at: stashedURL)
                                DNDLogger.log("DragDetectionProbe: Archivo stasheado temporal eliminado: \(stashedURL.path)")
                            }
                        }
                    }
                }
            }
            
            if isDragging || isMouseDown {
                let wasInvitation = AppState.shared.isDropInvitationActive
                self.isMouseDown = false
                
                // Proporcionar 0.35s de gracia para que AppKit complete performDragOperation antes de resetear
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self = self else { return }
                    if !self.isMouseDown && !AppState.shared.isDropSuccessAnimating {
                        self.isDragging = false
                        self.itemCount = 0
                        self.detectedTypes = []
                        self.previewItems = []
                        self.proximity = 0.0
                        self.statusMessage = "En reposo (0% CPU)"
                        
                        if wasInvitation && AppState.shared.isDropInvitationActive {
                            withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                                AppState.shared.isDropInvitationActive = false
                            }
                        }
                    }
                }
            }
            stopActiveMousePolling()
            return
        }
        
        // El botón del ratón está físicamente presionado a nivel de sistema
        let wasButtonDownBefore = self.isMouseDown
        self.isMouseDown = true
        self.lastChangeCount = currentChangeCount
        
        let mouseLoc = NSEvent.mouseLocation
        if !wasButtonDownBefore || self.initialMouseDownLocation == nil {
            self.initialMouseDownLocation = mouseLoc
            // En el momento de presionar el ratón, aún no ha iniciado ninguna sesión de arrastre.
            // Sincronizamos la base para detectar incrementos reales producidos por beginDraggingSession en macOS.
            self.baseChangeCount = currentChangeCount
        }
        
        let startLoc = self.initialMouseDownLocation ?? mouseLoc
        let distanceMoved = hypot(mouseLoc.x - startLoc.x, mouseLoc.y - startLoc.y)
        
        // Un arrastre real en macOS REQUIERE:
        // 1. Que Finder u otra app haya llamado a beginDraggingSession (incrementando dragPb.changeCount respecto a baseChangeCount)
        // 2. Que el pasteboard contenga archivos válidos y verificables
        // 3. Que el cursor haya superado el umbral físico de desplazamiento (>= 6 pt)
        let hasNewDragSession = currentChangeCount != self.baseChangeCount
        let hasRealFiles = self.checkIfPasteboardHasFiles(dragPb)
        let isRealDragActive = (hasNewDragSession && hasRealFiles && distanceMoved >= 6.0) || (self.isDragging && hasRealFiles)
        
        if isRealDragActive {
            self.cursorLocation = mouseLoc
            
            if !self.isDragging {
                self.isDragging = true
                self.inspectPasteboard(dragPb)
                DNDLogger.log("DragDetectionProbe: Arrastre real detectado! itemCount=\(self.itemCount), types=\(self.detectedTypes)")
            }
            self.updateDistances(for: mouseLoc)
            self.statusMessage = "🟢 Arrastre ACTIVO (\(self.itemCount) elementos)"
        } else {
            if self.isDragging {
                DNDLogger.log("DragDetectionProbe: Arrastre finalizado/reseteado")
                self.isDragging = false
                self.itemCount = 0
                self.detectedTypes = []
                self.previewItems = []
                self.proximity = 0.0
                self.statusMessage = "En reposo"
                
                if AppState.shared.isDropInvitationActive {
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                        AppState.shared.isDropInvitationActive = false
                    }
                }
            }
        }
    }
    
    // MARK: - Comprobación de Compatibilidad de Archivos
    public func checkIfPasteboardHasFiles(_ pb: NSPasteboard) -> Bool {
        guard let types = pb.types else { return false }
        for t in types {
            if t == .fileURL ||
               t.rawValue == "NSFilenamesPboardType" ||
               t.rawValue == "public.file-url" ||
               t.rawValue == "com.apple.finder.node" ||
               t.rawValue.contains("file-url") ||
               t.rawValue.contains("file-promise") {
                return true
            }
        }
        return false
    }
    
    // MARK: - Cálculo de Distancias y Activación de la Isla
    private func updateDistances(for location: CGPoint) {
        let screens = NSScreen.screens
        guard let targetScreen = screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main else {
            return
        }
        
        let screenFrame = targetScreen.frame
        let notchCenterX = screenFrame.midX
        let notchBottomY = screenFrame.maxY - 34.0
        
        let dx = location.x - notchCenterX
        let dy = max(0.0, notchBottomY - location.y)
        let euclidean = sqrt((dx * dx) + (dy * dy))
        
        self.distanceToNotch = euclidean
        self.verticalDistanceToNotch = dy
        
        let maxRadius: CGFloat = 240.0
        let clamped = max(0.0, min(maxRadius, euclidean))
        self.proximity = 1.0 - (clamped / maxRadius)
        
        // Activación magnética por proximidad
        if self.isDragging && self.itemCount > 0 && AppState.shared.enableDropInvitation {
            guard ActivityCenter.shared.currentActivity == nil else { return }
            let triggerDist = AppState.shared.dropInvitationDistance
            let exitDist = triggerDist + 35.0
            
            if euclidean <= triggerDist && !AppState.shared.isDropInvitationActive && AppState.shared.mode != .shelf {
                withAnimation(.spring(response: ExitAnimationMetrics.cardOpenResponse, dampingFraction: ExitAnimationMetrics.cardOpenDamping)) {
                    AppState.shared.isDropInvitationActive = true
                }
                if AppState.shared.enableShelfHaptics {
                    AppState.shared.hapticService.triggerSnap()
                }
            } else if euclidean > exitDist && AppState.shared.isDropInvitationActive && !AppState.shared.isDropSuccessAnimating {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                    AppState.shared.isDropInvitationActive = false
                }
            }
        }
    }
    
    // MARK: - Inspección del Pasteboard
    private func inspectPasteboard(_ pb: NSPasteboard) {
        var types: [String] = []
        var items: [String] = []
        
        // 1. URLs de archivo
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            types.append("Archivo (\(urls.count))")
            for url in urls.prefix(5) {
                items.append(url.lastPathComponent)
            }
            if urls.count > 5 {
                items.append("+ \(urls.count - 5) más...")
            }
            self.itemCount = urls.count
        } else if let filenames = pb.propertyList(forType: .init("NSFilenamesPboardType")) as? [String], !filenames.isEmpty {
            types.append("Archivo (\(filenames.count))")
            for p in filenames.prefix(5) {
                items.append(URL(fileURLWithPath: p).lastPathComponent)
            }
            self.itemCount = filenames.count
        }
        
        if types.isEmpty {
            self.itemCount = 0
        }
        
        self.detectedTypes = types
        self.previewItems = items
    }
    
    // MARK: - Monitores de Eventos de Respaldo
    private func installEventMonitors() {
        uninstallEventMonitors()
        
        downGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] _ in
            self?.startActiveMousePolling()
        }
        downLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] event in
            self?.startActiveMousePolling()
            return event
        }
        upGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.pollDragState()
        }
        upLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.pollDragState()
            return event
        }
    }
    
    private func uninstallEventMonitors() {
        if let m = downGlobalMonitor { NSEvent.removeMonitor(m); downGlobalMonitor = nil }
        if let m = downLocalMonitor { NSEvent.removeMonitor(m); downLocalMonitor = nil }
        if let m = upGlobalMonitor { NSEvent.removeMonitor(m); upGlobalMonitor = nil }
        if let m = upLocalMonitor { NSEvent.removeMonitor(m); upLocalMonitor = nil }
    }
    
    public func resetDragState() {
        self.isDragging = false
        self.isMouseDown = false
        self.itemCount = 0
        self.detectedTypes = []
        self.previewItems = []
        self.proximity = 0.0
        self.statusMessage = "En reposo"
        self.initialMouseDownLocation = nil
        let dragPb = NSPasteboard(name: .drag)
        self.baseChangeCount = dragPb.changeCount
        self.lastChangeCount = dragPb.changeCount
        DNDLogger.log("DragDetectionProbe: resetDragState completado (changeCount base: \(baseChangeCount))")
    }
    
    deinit {
        stopProbe()
    }
}
