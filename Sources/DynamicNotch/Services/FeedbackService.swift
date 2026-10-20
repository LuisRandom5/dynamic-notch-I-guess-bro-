import AppKit
import Contacts
import CoreBluetooth
import Foundation

/// "Enviar comentarios…": junta en un .zip del escritorio el registro de la app y datos básicos del Mac (versión,
/// modelo, pantalla, permisos) para mandárselo a quien hizo la beta. No incluye el texto de los mensajes (el registro
/// ya lo guarda sólo como "‹n car.›"), pero sí puede traer nombres de contactos o de canciones: se avisa antes.
public enum FeedbackService {
    public static func exportDiagnostics() {
        let alert = NSAlert()
        alert.messageText = L("Enviar comentarios")
        alert.informativeText = L("Se guardará en tu escritorio un .zip con el registro de la app y datos de tu Mac (versión de macOS, modelo, pantalla y permisos). No incluye el texto de tus mensajes, pero puede traer nombres de contactos y canciones.\n\nMándaselo a quien te invitó a la beta y cuéntale qué pasó y a qué hora.")
        alert.addButton(withTitle: L("Guardar en el escritorio"))
        alert.addButton(withTitle: L("Cancelar"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let zip = try writeArchive()
            NSWorkspace.shared.activateFileViewerSelecting([zip])
        } catch {
            let failure = NSAlert()
            failure.messageText = L("No se pudo guardar el diagnóstico")
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    /// Guarda el .zip en `directory` (por defecto el escritorio) y devuelve su ubicación
    static func writeArchive(in directory: URL? = nil) throws -> URL {
        let fm = FileManager.default
        let stamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH.mm"
            return f.string(from: Date())
        }()
        let name = "Dynamic Notch - diagnóstico \(stamp)"
        let work = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = work.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        try systemReport().write(to: folder.appendingPathComponent("info.txt"), atomically: true, encoding: .utf8)
        for log in ["/tmp/notch_dnd.log.1", "/tmp/notch_dnd.log"] where fm.fileExists(atPath: log) {
            try? fm.copyItem(atPath: log, toPath: folder.appendingPathComponent((log as NSString).lastPathComponent).path)
        }

        let destination = directory ?? fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
        let zip = destination.appendingPathComponent("\(name).zip")
        try? fm.removeItem(at: zip)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", folder.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw NSError(domain: "DynamicNotch", code: Int(ditto.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: L("No se pudo crear el .zip")])
        }
        return zip
    }

    private static func systemReport() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let geometry = ScreenService.shared.currentGeometry
        var model = [CChar](repeating: 0, count: 64)
        var size = model.count
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let lines = [
            "Dynamic Notch \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))\(BuildFlavor.isBeta ? " beta" : "")",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Mac: \(String(cString: model))",
            "Pantalla: \(geometry.kind) \(Int(geometry.width))×\(Int(geometry.height)) pt",
            "Apariencia: \(AppState.shared.appearanceMode.rawValue)",
            "Idioma: \(Locale.preferredLanguages.first ?? "?")",
            "",
            "Permisos:",
            "  Accesibilidad: \(VolumeInterceptorService.shared.checkPermission() ? "sí" : "no")",
            "  Calendario: \(CalendarActivityProvider.isAuthorized ? "sí" : "no")",
            "  Contactos: \(CNContactStore.authorizationStatus(for: .contacts) == .authorized ? "sí" : "no")",
            "  Bluetooth: \(CBManager.authorization == .allowedAlways ? "sí" : "no")",
            "",
            "Memoria de la app: \(residentMegabytes()) MB",
            "Generado: \(Date())"
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func residentMegabytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : -1
    }
}
