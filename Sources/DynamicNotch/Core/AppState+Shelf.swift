import AppKit
import SwiftUI
import Combine

// Repisa: agregar, quitar, restaurar y deshacer archivos
extension AppState {
    public func addShelfFile(url: URL) {
        guard !shelfItems.contains(where: { $0.url.path == url.path || $0.originalURL?.path == url.path }) else {
            mode = .shelf
            activeTab = .shelf
            return
        }
        let item = ShelfStorageService.shared.stashFile(from: url, shouldMove: moveFilesToShelf)
        shelfItems.append(item)
        mode = .shelf
        activeTab = .shelf
        hapticService.triggerDrop()
    }
    
    public func triggerDropError(message: String) {
        isDropErrorAnimating = true
        dropErrorMessage = message
        hapticService.triggerSnap()
        onDropError?(message)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
            guard let self = self else { return }
            withAnimation(.spring(response: ExitAnimationMetrics.cardDismissResponse, dampingFraction: ExitAnimationMetrics.cardDismissDamping)) {
                self.isDropInvitationActive = false
                self.isDropErrorAnimating = false
            }
        }
    }
    
    public func triggerDropSuccess(urls: [URL]) {
        DNDLogger.log("AppState.triggerDropSuccess called with \(urls.count) urls")
        isDropSuccessAnimating = true
        isDropErrorAnimating = false
        var addedAny = false
        var newBatch: [ShelfItem] = []
        
        for url in urls {
            let canonical = ((url as NSURL).filePathURL ?? url).standardizedFileURL
            // Limpiar registros antiguos cuyo archivo ya no exista en la repisa
            shelfItems.removeAll { item in
                if item.url.path == canonical.path || item.originalURL?.path == canonical.path {
                    return !FileManager.default.fileExists(atPath: item.url.path)
                }
                return false
            }
            guard !shelfItems.contains(where: { $0.url.path == canonical.path || $0.originalURL?.path == canonical.path }) else {
                DNDLogger.log("File already exists in shelf: \(canonical.lastPathComponent)")
                continue
            }
            let item = ShelfStorageService.shared.stashFile(from: canonical, shouldMove: moveFilesToShelf)
            shelfItems.append(item)
            newBatch.append(item)
            addedAny = true
            DNDLogger.log("Stashed item: \(item.name), destination: \(item.url.path), isStashed: \(item.isStashed)")
        }
        
        self.lastDroppedCount = newBatch.isEmpty ? urls.count : newBatch.count
        
        if !newBatch.isEmpty {
            ShelfStorageService.shared.recordBatch(newBatch)
        }
        
        if addedAny && enableShelfHaptics {
            hapticService.triggerDrop()
        }
        onDropSuccess?()
        
        // Retención de confirmación de 0.65 s para disfrutar la animación de éxito antes de retraerse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            guard let self = self else { return }
            let needsHold = self.mode == .compact && self.musicService.hasActiveMusic
            if needsHold {
                self.isHoldingBareNotch = true
            }
            withAnimation(.spring(response: ExitAnimationMetrics.cardDismissResponse, dampingFraction: ExitAnimationMetrics.cardDismissDamping)) {
                self.isDropInvitationActive = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.isDropSuccessAnimating = false
                if addedAny || self.autoOpenShelfOnDrop || !self.shelfItems.isEmpty {
                    withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) {
                        self.mode = .shelf
                        self.activeTab = .shelf
                    }
                    if self.enableShelfHaptics {
                        self.hapticService.triggerSnap()
                    }
                } else if needsHold {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        guard !self.isDropInvitationActive && ActivityCenter.shared.currentActivity == nil else {
                            self.isHoldingBareNotch = false
                            return
                        }
                        withAnimation(AnimationSpeedManager.shared.spring(response: 0.44, dampingFraction: 0.82)) {
                            self.isHoldingBareNotch = false
                        }
                    }
                }
            }
        }
    }
    
    public func addShelfFiles(urls: [URL]) {
        DNDLogger.log("AppState.addShelfFiles called with \(urls.count) urls")
        var addedAny = false
        var newBatch: [ShelfItem] = []
        for url in urls {
            let canonical = ((url as NSURL).filePathURL ?? url).standardizedFileURL
            // Limpiar registros antiguos cuyo archivo ya no exista en la repisa
            shelfItems.removeAll { item in
                if item.url.path == canonical.path || item.originalURL?.path == canonical.path {
                    return !FileManager.default.fileExists(atPath: item.url.path)
                }
                return false
            }
            guard !shelfItems.contains(where: { $0.url.path == canonical.path || $0.originalURL?.path == canonical.path }) else {
                DNDLogger.log("addShelfFiles: file already in shelf: \(canonical.lastPathComponent)")
                continue
            }
            let item = ShelfStorageService.shared.stashFile(from: canonical, shouldMove: moveFilesToShelf)
            shelfItems.append(item)
            newBatch.append(item)
            addedAny = true
            DNDLogger.log("addShelfFiles stashed: \(item.name) at \(item.url.path)")
        }
        if !newBatch.isEmpty {
            ShelfStorageService.shared.recordBatch(newBatch)
        }
        if addedAny {
            if enableShelfHaptics {
                hapticService.triggerDrop()
            }
            if mode != .shelf {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                    mode = .shelf
                    activeTab = .shelf
                }
            }
        } else if !shelfItems.isEmpty && mode != .shelf {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                mode = .shelf
                activeTab = .shelf
            }
        }
    }
    
    public func removeShelfItem(_ item: ShelfItem, moveToTrash: Bool = true) {
        if moveToTrash && item.isStashed {
            ShelfStorageService.shared.moveToTrash(item: item)
        }
        shelfItems.removeAll(where: { $0.id == item.id || $0.url.path == item.url.path })
    }
    
    public func restoreShelfItemToOrigin(_ item: ShelfItem) {
        if ShelfStorageService.shared.restoreToOrigin(item: item) {
            shelfItems.removeAll(where: { $0.id == item.id })
            hapticService.triggerSnap()
        }
    }
    
    public func restoreAllShelfItemsToOrigin() {
        var toRemove: [UUID] = []
        for item in shelfItems {
            if ShelfStorageService.shared.restoreToOrigin(item: item) {
                toRemove.append(item.id)
            }
        }
        shelfItems.removeAll(where: { toRemove.contains($0.id) })
        hapticService.triggerSnap()
    }
    
    public func emptyShelfToTrash() {
        for item in shelfItems {
            if item.isStashed {
                ShelfStorageService.shared.moveToTrash(item: item)
            }
        }
        shelfItems.removeAll()
        hapticService.triggerSnap()
    }
    
    public func undoLastDrop() {
        let restored = ShelfStorageService.shared.undoLastBatch(from: &shelfItems)
        if !restored.isEmpty {
            hapticService.triggerSnap()
        }
    }
}
