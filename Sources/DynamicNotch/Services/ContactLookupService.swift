import Contacts
import AppKit

public struct ContactInfo {
    public let name: String
    public let avatar: NSImage?
    public let initials: String
    
    public init(name: String, avatar: NSImage?, initials: String) {
        self.name = name
        self.avatar = avatar
        self.initials = initials
    }
}

public final class ContactLookupService: ObservableObject {
    public static let shared = ContactLookupService()
    
    @Published public private(set) var isAuthorized: Bool = false
    private let contactStore = CNContactStore()
    
    private let keysToFetch: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactImageDataKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor
    ]
    
    private init() {
        checkCurrentStatus()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkCurrentStatus()
        }
    }
    
    public func checkCurrentStatus() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        DispatchQueue.main.async {
            self.isAuthorized = (status == .authorized)
        }
    }
    
    /// Solicita explícitamente acceso a los contactos con el diálogo nativo de macOS
    public func requestAccess(completion: @escaping (Bool) -> Void) {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
            completion(true)
        case .notDetermined:
            contactStore.requestAccess(for: .contacts) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    completion(granted)
                }
            }
        default:
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                NSWorkspace.shared.open(url)
            }
            completion(false)
        }
    }
    
    /// Busca un contacto por identificador único, nombre o número de teléfono / correo
    public func lookupContact(
        identifier: String? = nil,
        name: String? = nil,
        handle: String? = nil
    ) -> ContactInfo? {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        DNDLogger.log("ContactLookupService.lookupContact: status=\(status.rawValue)")
        guard status == .authorized else {
            // Si no hay acceso, generar monograma elegante para no dejar la UI vacía
            let fallbackName = name ?? handle ?? "Contacto"
            let initials = extractInitials(from: fallbackName)
            let monogram = generateMonogramAvatar(for: fallbackName, initials: initials)
            return ContactInfo(name: fallbackName, avatar: monogram, initials: initials)
        }
        
        // 1. Búsqueda por Identificador único si existe
        if let id = identifier, !id.isEmpty {
            if let contact = try? contactStore.unifiedContact(withIdentifier: id, keysToFetch: keysToFetch) {
                return formatContact(contact, fallbackQuery: name ?? handle ?? id)
            }
        }
        
        // 2. Búsqueda por Handle (Teléfono o Email)
        if let h = handle, !h.isEmpty {
            if h.contains("@") {
                let predicate = CNContact.predicateForContacts(matchingEmailAddress: h)
                if let contacts = try? contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch),
                   let first = contacts.first {
                    return formatContact(first, fallbackQuery: h)
                }
            } else {
                let cleanNumber = h.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if !cleanNumber.isEmpty {
                    let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: h))
                    if let contacts = try? contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch),
                       let first = contacts.first {
                        return formatContact(first, fallbackQuery: h)
                    }
                }
            }
        }
        
        // 3. Búsqueda por Nombre o Query
        let queryName = name ?? handle ?? ""
        if !queryName.isEmpty {
            let predicate = CNContact.predicateForContacts(matchingName: queryName)
            if let contacts = try? contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch),
               let first = contacts.first {
                return formatContact(first, fallbackQuery: queryName)
            }
        }
        
        // 4. Fallback de escaneo por coincidencia parcial si la búsqueda exacta no encontró nada
        if !queryName.isEmpty {
            let req = CNContactFetchRequest(keysToFetch: keysToFetch)
            var matchedContact: CNContact?
            let lower = queryName.lowercased()
            
            try? contactStore.enumerateContacts(with: req) { contact, stop in
                let full = "\(contact.givenName) \(contact.familyName)".lowercased()
                let nick = contact.nickname.lowercased()
                let org = contact.organizationName.lowercased()
                
                if full.contains(lower) || nick.contains(lower) || org.contains(lower) {
                    matchedContact = contact
                    stop.pointee = true
                }
            }
            
            if let found = matchedContact {
                return formatContact(found, fallbackQuery: queryName)
            }
        }
        
        // 5. Fallback con monograma si no se encontró contacto registrado
        let fallback = queryName.isEmpty ? "Llamada" : queryName
        let initials = extractInitials(from: fallback)
        let monogram = generateMonogramAvatar(for: fallback, initials: initials)
        return ContactInfo(name: fallback, avatar: monogram, initials: initials)
    }
    
    /// Compatibilidad previa
    public func lookupContact(matching query: String) -> (name: String, avatar: NSImage?)? {
        if let info = lookupContact(name: query, handle: query) {
            return (info.name, info.avatar)
        }
        return nil
    }
    
    /// Obtiene el primer contacto que tenga foto real en la libreta (para pruebas inmediatas)
    public func fetchFirstContactWithPhoto() -> ContactInfo? {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
        let req = CNContactFetchRequest(keysToFetch: keysToFetch)
        var result: ContactInfo? = nil
        try? contactStore.enumerateContacts(with: req) { contact, stop in
            if contact.imageDataAvailable, (contact.thumbnailImageData != nil || contact.imageData != nil) {
                result = self.formatContact(contact, fallbackQuery: contact.givenName)
                stop.pointee = true
            }
        }
        return result
    }
    
    // MARK: - Auxiliares de Formato y Monogramas
    
    private func formatContact(_ contact: CNContact, fallbackQuery: String) -> ContactInfo {
        var fullName = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if fullName.isEmpty {
            fullName = contact.nickname.isEmpty ? (contact.organizationName.isEmpty ? fallbackQuery : contact.organizationName) : contact.nickname
        }
        
        let initials = extractInitials(from: fullName)
        var avatarImage: NSImage? = nil
        
        if contact.imageDataAvailable {
            if let data = contact.thumbnailImageData ?? contact.imageData {
                avatarImage = NSImage.decodedImage(from: data)
            }
        }
        
        // Si no tiene foto cargada en macOS, generamos su avatar monograma personalizado
        if avatarImage == nil {
            avatarImage = generateMonogramAvatar(for: fullName, initials: initials)
        }
        
        return ContactInfo(name: fullName, avatar: avatarImage, initials: initials)
    }
    
    public func extractInitials(from name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let f = parts[0].prefix(1)
            let s = parts[1].prefix(1)
            return "\(f)\(s)".uppercased()
        } else if let first = parts.first {
            return String(first.prefix(1)).uppercased()
        }
        return "C"
    }
    
    /// Genera un monograma visualmente idéntico a los de iOS/macOS con gradientes armónicos y tipografía SF Pro
    public func generateMonogramAvatar(for name: String, initials: String, size: CGSize = CGSize(width: 88, height: 88)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(ovalIn: rect)
        
        // Paletas de gradientes armoniosos estilo Apple
        let hash = abs(name.hashValue)
        let palettes: [(NSColor, NSColor)] = [
            (NSColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1.0), NSColor(red: 0.55, green: 0.25, blue: 0.85, alpha: 1.0)), // Azul/Púrpura
            (NSColor(red: 0.15, green: 0.75, blue: 0.60, alpha: 1.0), NSColor(red: 0.05, green: 0.55, blue: 0.70, alpha: 1.0)), // Teal/Cian
            (NSColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1.0), NSColor(red: 0.85, green: 0.15, blue: 0.35, alpha: 1.0)), // Rosa/Coral
            (NSColor(red: 0.95, green: 0.60, blue: 0.15, alpha: 1.0), NSColor(red: 0.90, green: 0.35, blue: 0.10, alpha: 1.0)), // Naranja/Ámbar
            (NSColor(red: 0.30, green: 0.80, blue: 0.45, alpha: 1.0), NSColor(red: 0.15, green: 0.65, blue: 0.35, alpha: 1.0))  // Verde Esmeralda
        ]
        let palette = palettes[hash % palettes.count]
        
        let gradient = NSGradient(starting: palette.0, ending: palette.1)
        gradient?.draw(in: path, angle: -45)
        
        // Dibujar borde sutil interior
        NSColor(white: 1.0, alpha: 0.20).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        
        // Dibujar iniciales
        let font = NSFont.systemFont(ofSize: size.width * 0.42, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        let str = NSAttributedString(string: initials, attributes: attrs)
        let strSize = str.size()
        let textRect = NSRect(
            x: (size.width - strSize.width) / 2,
            y: (size.height - strSize.height) / 2 - 1,
            width: strSize.width,
            height: strSize.height
        )
        str.draw(in: textRect)
        
        image.unlockFocus()
        return image
    }
}
