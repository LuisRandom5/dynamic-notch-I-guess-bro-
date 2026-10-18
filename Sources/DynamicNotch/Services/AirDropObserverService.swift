import Foundation
import AppKit

/// Servicio observador en tiempo real de transferencias entrantes de AirDrop en macOS.
/// Detecta automáticamente cuando se recibe un archivo por AirDrop mediante:
/// 1. Monitor de cambios en el directorio ~/Downloads (DispatchSourceFileSystemObject).
/// 2. Inspección del atributo extendido POSIX `com.apple.quarantine` para identificar el agente "sharingd".
/// 3. Monitor de la base de datos de eventos de cuarentena de LaunchServices.
///
/// Al detectar la llegada de un AirDrop:
/// - Muestra una animación breve de alas compactas (AirDrop en progreso).
/// - Expande orgánicamente a la tarjeta de éxito con el nombre real del archivo, su peso formateado y checkmark.
/// - Al tocar la tarjeta, revela el archivo directamente en el Finder.
public final class AirDropObserverService {
    public static let shared = AirDropObserverService()
    
    private var downloadsSource: DispatchSourceFileSystemObject?
    private var downloadsFolderFD: Int32 = -1
    private var quarantineSource: DispatchSourceFileSystemObject?
    private var quarantineFD: Int32 = -1
    
    private var processedFilePaths = Set<String>()
    private var lastTriggerTime: Date = Date.distantPast
    private let queue = DispatchQueue(label: "com.luisrandom.DynamicNotch.AirDropObserver", qos: .userInitiated)
    
    private init() {}
    
    public func startObserving() {
        stopObserving()
        
        setupDownloadsMonitor()
        setupQuarantineMonitor()
        
        print("📡 [AirDropObserverService] Monitor de AirDrop activo en ~/Downloads y LaunchServices.")
    }
    
    public func stopObserving() {
        downloadsSource?.cancel()
        downloadsSource = nil
        if downloadsFolderFD >= 0 {
            close(downloadsFolderFD)
            downloadsFolderFD = -1
        }
        
        quarantineSource?.cancel()
        quarantineSource = nil
        if quarantineFD >= 0 {
            close(quarantineFD)
            quarantineFD = -1
        }
    }
    
    // MARK: - Monitor de ~/Downloads
    private func setupDownloadsMonitor() {
        let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? (NSHomeDirectory() + "/Downloads")
        let fd = open(downloadsPath, O_EVTONLY)
        guard fd >= 0 else {
            print("⚠️ [AirDropObserverService] No se pudo abrir ~/Downloads para observación.")
            return
        }
        
        self.downloadsFolderFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib],
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            self?.checkForRecentAirDropFiles()
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        source.resume()
        self.downloadsSource = source
    }
    
    // MARK: - Monitor de LaunchServices Quarantine
    private func setupQuarantineMonitor() {
        let quarantinePath = NSHomeDirectory() + "/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"
        guard FileManager.default.fileExists(atPath: quarantinePath) else { return }
        
        let fd = open(quarantinePath, O_EVTONLY)
        guard fd >= 0 else { return }
        
        self.quarantineFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            // Un evento de cuarentena nuevo indica que sharingd escribió un archivo
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                self?.checkForRecentAirDropFiles()
            }
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        source.resume()
        self.quarantineSource = source
    }
    
    // MARK: - Escaneo de Archivos Recientes de AirDrop
    private func checkForRecentAirDropFiles() {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else { return }
        
        let now = Date()
        
        // Buscar archivos modificados en los últimos 20 segundos
        let recentFiles = contents.compactMap { url -> (URL, Date, Int64)? in
            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                  let modDate = values.contentModificationDate,
                  now.timeIntervalSince(modDate) < 20.0 else {
                return nil
            }
            let isDir = values.isDirectory ?? false
            if isDir { return nil }
            let size = Int64(values.fileSize ?? 0)
            return (url, modDate, size)
        }
        .sorted { $0.1 > $1.1 }
        
        for (url, _, size) in recentFiles {
            let path = url.path
            guard !processedFilePaths.contains(path) else { continue }
            
            // Comprobar si el archivo proviene de sharingd (AirDrop)
            if isAirDropFile(path: path) {
                processedFilePaths.insert(path)
                if processedFilePaths.count > 100 {
                    processedFilePaths.removeAll()
                }
                
                triggerAirDropNotification(for: url, size: size)
                break
            }
        }
    }
    
    private func isAirDropFile(path: String) -> Bool {
        guard let quarantine = getQuarantineAttribute(for: path) else { return false }
        // Los archivos de AirDrop siempre llevan "sharingd" como agente en com.apple.quarantine
        return quarantine.contains("sharingd")
    }
    
    private func getQuarantineAttribute(for path: String) -> String? {
        let length = getxattr(path, "com.apple.quarantine", nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes { ptr in
            getxattr(path, "com.apple.quarantine", ptr.baseAddress, length, 0, 0)
        }
        guard result > 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Disparador de Notificación
    private func triggerAirDropNotification(for url: URL, size: Int64) {
        guard Date().timeIntervalSince(lastTriggerTime) > 2.0 else { return }
        lastTriggerTime = Date()
        
        let fileName = url.lastPathComponent
        let formattedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        
        DispatchQueue.main.async {
            print("📦 [AirDropObserverService] Archivo de AirDrop detectado: \(fileName) (\(formattedSize))")
            AppState.shared.hapticService.triggerExpand()
            // Las alas de progreso ya las mostró AirDropTransferMonitor al empezar la recepción;
            // aquí sólo se pasa a la tarjeta con el archivo (al tocarla abre su ubicación en Finder)
            AirDropActivityProvider.shared.publishCompletedCard(
                fileName: fileName,
                sender: "AirDrop",
                fileSize: formattedSize,
                fileURL: url
            )
        }
    }
}
