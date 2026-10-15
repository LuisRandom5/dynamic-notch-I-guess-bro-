import Foundation
import AppKit
import UniformTypeIdentifiers
import ObjectiveC

/// Rastreador de ciclo de vida para arrastre hacia el exterior (Drag-Out)
/// Se vincula a un NSItemProvider estándar mediante asociación Obj-C para evitar errores de inicialización y subclase.
public final class DragOutTracker {
    public let item: ShelfItem
    private let onDragOutCompleted: () -> Void
    private var isCancelledByEscape: Bool = false
    private var localKeyMonitor: Any?
    
    public init(item: ShelfItem, onDragOutCompleted: @escaping () -> Void) {
        self.item = item
        self.onDragOutCompleted = onDragOutCompleted
        
        // Monitor local de la tecla Escape (53): si el usuario aborta el arrastre, no se quita el archivo
        self.localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.isCancelledByEscape = true
                DNDLogger.log("DragOutTracker: Arrastre cancelado con tecla Escape")
            }
            return event
        }
        
        DNDLogger.log("DragOutTracker: inicializado para \(item.name)")
    }
    
    deinit {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        
        let cancelled = self.isCancelledByEscape
        let itemToRemove = self.item
        let completion = self.onDragOutCompleted
        let mouseLocation = NSEvent.mouseLocation
        
        DNDLogger.log("DragOutTracker: deinit para \(itemToRemove.name) en mouse: \(mouseLocation), cancelled=\(cancelled)")
        
        DispatchQueue.main.async {
            let notchRect = NotchWindowManager.shared.panel?.frame ?? .zero
            let isOutsideNotch = !notchRect.contains(mouseLocation)
            
            DNDLogger.log("DragOutTracker: verificación final -> isOutsideNotch=\(isOutsideNotch), cancelled=\(cancelled)")
            
            if !cancelled && isOutsideNotch {
                DNDLogger.log("DragOutTracker: ¡Archivo soltado exitosamente fuera del notch! Ejecutando remoción.")
                completion()
            }
        }
    }
}

private var dragOutTrackerAssociationKey: UInt8 = 0

extension NSItemProvider {
    /// Vincula un rastreador de drag-out al NSItemProvider nativo sin requerir subclases frágiles
    public func trackDragOut(item: ShelfItem, onDragOutCompleted: @escaping () -> Void) {
        let tracker = DragOutTracker(item: item, onDragOutCompleted: onDragOutCompleted)
        objc_setAssociatedObject(self, &dragOutTrackerAssociationKey, tracker, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
