import Foundation
import AppKit

public final class ShelfStorageService: ObservableObject {
    public static let shared = ShelfStorageService()
    
    private let fileManager = FileManager.default
    
    /// Carpeta segura de la bandeja temporal
    public var stashDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("DynamicNotch/Shelf", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    /// Historial del último lote soltado para permitir Deshacer (Cmd+Z)
    public private(set) var lastStashedBatch: [ShelfItem] = []
    
    private init() {
        // Asegurar que el directorio de la repisa exista al iniciar
        _ = stashDirectory
    }
    
    /// Carga los archivos que ya se encuentren en la bandeja temporal en disco
    public func loadExistingStashedItems() -> [ShelfItem] {
        guard let files = try? fileManager.contentsOfDirectory(at: stashDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return files.compactMap { url in
            let canonical = url.standardizedFileURL
            guard fileManager.fileExists(atPath: canonical.path) else { return nil }
            return ShelfItem(
                url: canonical,
                originalURL: nil,
                isStashed: true,
                isReadOnlySource: false,
                name: canonical.lastPathComponent
            )
        }
    }
    
    /// Procesa y guarda un archivo en la bandeja del Notch.
    /// Si `shouldMove` es true y el archivo está en una ubicación movible (Escritorio, Descargas, etc.),
    /// se mueve físicamente a la repisa y desaparece del escritorio/origen de inmediato.
    public func stashFile(from sourceURL: URL, shouldMove: Bool = true) -> ShelfItem {
        let name = sourceURL.lastPathComponent
        let canonicalSource = sourceURL.standardizedFileURL
        
        // Comprobar si es un archivo de sistema protegido que no debe eliminarse de su origen
        let isProtected = isProtectedPath(canonicalSource)
        
        guard shouldMove && !isProtected else {
            // Modo copia / referencia sin borrar el origen
            let destURL = uniqueDestinationURL(in: stashDirectory, filename: name)
            if (try? fileManager.copyItem(at: canonicalSource, to: destURL)) != nil {
                return ShelfItem(
                    url: destURL,
                    originalURL: canonicalSource,
                    isStashed: true,
                    isReadOnlySource: true,
                    name: name
                )
            } else {
                return ShelfItem(
                    url: canonicalSource,
                    originalURL: nil,
                    isStashed: false,
                    isReadOnlySource: isProtected,
                    name: name
                )
            }
        }
        
        // Movimiento real hacia la repisa: desaparece del escritorio/origen de inmediato
        let destURL = uniqueDestinationURL(in: stashDirectory, filename: name)
        DNDLogger.log("ShelfStorageService.stashFile moving from \(canonicalSource.path) to \(destURL.path)")
        
        // Prueba 1: Inspección de permisos de archivo antes del movimiento
        let isWritable = fileManager.isWritableFile(atPath: canonicalSource.path)
        let isDeletable = fileManager.isDeletableFile(atPath: canonicalSource.path)
        let isDestWritable = fileManager.isWritableFile(atPath: stashDirectory.path)
        DNDLogger.log("ShelfStorageService.stashFile inspect: isWritable=\(isWritable), isDeletable=\(isDeletable), isDestDirWritable=\(isDestWritable)")
        
        // Sin automatizar Finder (AppleScript): macOS pedía autorización (Touch ID) en cada movimiento y
        // bloqueaba ~10 s. FileManager mueve el archivo directo y Finder lo refleja solo (FSEvents).
        
        // Fallback a FileManager.moveItem con reporte detallado de errores (Prueba 1)
        do {
            try fileManager.moveItem(at: canonicalSource, to: destURL)
            DNDLogger.log("ShelfStorageService.stashFile moveItem SUCCEEDED!")
            notifyFinderChanged(for: canonicalSource)
            notifyFinderChanged(for: destURL)
            return ShelfItem(
                url: destURL,
                originalURL: canonicalSource,
                isStashed: true,
                isReadOnlySource: false,
                name: name
            )
        } catch {
            let nsErr = error as NSError
            DNDLogger.log("ShelfStorageService.stashFile moveItem FAILED: [Domain: \(nsErr.domain)] [Code: \(nsErr.code)] [Desc: \(nsErr.localizedDescription)] [UserInfo: \(nsErr.userInfo)]")
            if nsErr.domain == NSCocoaErrorDomain {
                switch nsErr.code {
                case NSFileWriteNoPermissionError:
                    DNDLogger.log("ShelfStorageService: Diagnostic -> NSFileWriteNoPermissionError (Código 513). Sin permisos de escritura.")
                case NSFileNoSuchFileError:
                    DNDLogger.log("ShelfStorageService: Diagnostic -> NSFileNoSuchFileError (Código 4). Archivo origen no encontrado.")
                case NSFileWriteFileExistsError:
                    DNDLogger.log("ShelfStorageService: Diagnostic -> NSFileWriteFileExistsError (Código 516). Ya existe en destino.")
                default:
                    break
                }
            }
            
            DNDLogger.log("ShelfStorageService.stashFile trying copy + delete fallback...")
            do {
                try fileManager.copyItem(at: canonicalSource, to: destURL)
                DNDLogger.log("ShelfStorageService.stashFile copy fallback SUCCEEDED. Removing original...")
                
                // Intentar removeItem reportando error explícito
                do {
                    try fileManager.removeItem(at: canonicalSource)
                    DNDLogger.log("ShelfStorageService.stashFile removeItem SUCCEEDED!")
                } catch let removeErr as NSError {
                    DNDLogger.log("ShelfStorageService.stashFile removeItem FAILED: [Code: \(removeErr.code)] [Desc: \(removeErr.localizedDescription)]")
                    if fileManager.fileExists(atPath: canonicalSource.path) {
                        DNDLogger.log("ShelfStorageService attempting NSWorkspace.recycle fallback...")
                        NSWorkspace.shared.recycle([canonicalSource]) { recycledURLs, recError in
                            if let recError = recError {
                                DNDLogger.log("ShelfStorageService recycle error: \(recError)")
                            } else {
                                DNDLogger.log("ShelfStorageService recycle SUCCEEDED: \(recycledURLs)")
                            }
                        }
                    }
                }
                
                // Reintentar remoción con breve retardo en caso de bloqueo transitorio de Finder por arrastre
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if self.fileManager.fileExists(atPath: canonicalSource.path) {
                        do {
                            try self.fileManager.removeItem(at: canonicalSource)
                            DNDLogger.log("ShelfStorageService delayed removeItem SUCCEEDED!")
                            self.notifyFinderChanged(for: canonicalSource)
                        } catch {
                            DNDLogger.log("ShelfStorageService delayed removeItem error: \(error)")
                        }
                    }
                }
                
                notifyFinderChanged(for: canonicalSource)
                notifyFinderChanged(for: destURL)
                return ShelfItem(
                    url: destURL,
                    originalURL: canonicalSource,
                    isStashed: true,
                    isReadOnlySource: false,
                    name: name
                )
            } catch let copyErr as NSError {
                DNDLogger.log("ShelfStorageService.stashFile copy fallback FAILED: [Domain: \(copyErr.domain)] [Code: \(copyErr.code)] [Desc: \(copyErr.localizedDescription)]")
                return ShelfItem(
                    url: canonicalSource,
                    originalURL: nil,
                    isStashed: false,
                    isReadOnlySource: true,
                    name: name
                )
            }
        }
    }
    
    /// Notifica a Finder y al sistema de archivos para refrescar el Escritorio al instante
    private func notifyFinderChanged(for url: URL) {
        let parent = url.deletingLastPathComponent().path
        NSWorkspace.shared.noteFileSystemChanged(parent)
        NSWorkspace.shared.noteFileSystemChanged(url.path)
        
        // Basta con avisar al sistema de archivos: pedirle a Finder un "update" por AppleScript disparaba
        // la autorización con Touch ID
    }
    
    /// Mueve el archivo stasheado de vuelta a su ubicación original (Escritorio, Descargas, etc.)
    public func restoreToOrigin(item: ShelfItem) -> Bool {
        guard item.isStashed, let origURL = item.originalURL else {
            return false
        }
        
        let parentDir = origURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parentDir.path) else {
            return false
        }
        
        // Directo con FileManager (sin automatizar Finder: pedía Touch ID)
        let targetURL = uniqueDestinationURL(in: parentDir, filename: origURL.lastPathComponent)
        do {
            try fileManager.moveItem(at: item.url, to: targetURL)
            notifyFinderChanged(for: targetURL)
            notifyFinderChanged(for: item.url)
            return true
        } catch {
            let nsErr = error as NSError
            DNDLogger.log("ShelfStorageService.restoreToOrigin moveItem FAILED: [Code: \(nsErr.code)] [Desc: \(nsErr.localizedDescription)]")
            return false
        }
    }
    
    /// Envía el archivo de la bandeja a la Papelera de macOS (reversible por el usuario)
    public func moveToTrash(item: ShelfItem) {
        guard item.isStashed else { return }
        var trashURL: NSURL?
        _ = try? fileManager.trashItem(at: item.url, resultingItemURL: &trashURL)
    }
    
    /// Registra el lote reciente para soporte de Deshacer
    public func recordBatch(_ items: [ShelfItem]) {
        self.lastStashedBatch = items
    }
    
    /// Deshace el último lote soltado, devolviendo todos los archivos a su origen
    public func undoLastBatch(from currentItems: inout [ShelfItem]) -> [ShelfItem] {
        var restored: [ShelfItem] = []
        for item in lastStashedBatch {
            if restoreToOrigin(item: item) {
                currentItems.removeAll(where: { $0.id == item.id })
                restored.append(item)
            }
        }
        lastStashedBatch.removeAll()
        return restored
    }
    
    // MARK: - Rutas protegidas del sistema
    private func isProtectedPath(_ url: URL) -> Bool {
        let path = url.path
        if path.hasPrefix("/System") ||
           path.hasPrefix("/Library") ||
           path.hasPrefix("/bin") ||
           path.hasPrefix("/usr") ||
           path.hasPrefix("/sbin") ||
           path.hasPrefix("/Applications") {
            return true
        }
        return false
    }
    
    // MARK: - Resolución de colisión de nombres
    private func uniqueDestinationURL(in directory: URL, filename: String) -> URL {
        var target = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: target.path) else {
            return target
        }
        
        let ext = target.pathExtension
        let baseName = target.deletingPathExtension().lastPathComponent
        var counter = 2
        
        while fileManager.fileExists(atPath: target.path) {
            let newName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            target = directory.appendingPathComponent(newName)
            counter += 1
        }
        
        return target
    }
    
    // MARK: - Utilidades de Almacenamiento & Acciones de Usuario
    /// Calcula el tamaño total en disco de los archivos custodiados en la repisa
    public func totalStashedSizeString() -> String {
        guard let files = try? fileManager.contentsOfDirectory(at: stashDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 KB"
        }
        var totalBytes: Int64 = 0
        for file in files {
            if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? Int64 {
                totalBytes += size
            }
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: totalBytes)
    }
    
    /// Abre la carpeta de custodia física en Finder
    public func openStashFolderInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: stashDirectory.path)
    }
    
    /// Presenta el selector nativo de macOS para añadir archivos manualmente a la repisa
    public func selectAndAddFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Añadir a la Repisa"
        panel.message = "Selecciona archivos para custodiarlos en el Notch"
        
        // Elevar panel por encima de paneles flotantes si es necesario
        panel.level = .floating
        if panel.runModal() == .OK {
            let selectedURLs = panel.urls
            if !selectedURLs.isEmpty {
                DispatchQueue.main.async {
                    AppState.shared.addShelfFiles(urls: selectedURLs)
                }
            }
        }
    }
}

