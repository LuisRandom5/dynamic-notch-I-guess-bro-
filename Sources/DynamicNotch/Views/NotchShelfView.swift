import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct NotchShelfView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var musicService: MusicService
    
    public init() {}
    
    private var isTargeted: Bool {
        appState.isShelfDragTargeted
    }
    
    private var stretch: CGFloat {
        appState.overscrollOffset
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Contenido interno con márgenes de seguridad exactos y simetría perfecta
            VStack(spacing: 10) {
                // MARK: - Barra Superior (Pestañas: Música ○  ● Bandeja con indicador interactivo centrado)
                ZStack {
                    // Centro Absoluto: Indicador de Pestañas (Home ○  ● Bandeja)
                    HStack(spacing: 6) {
                        Button(action: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                                appState.activeTab = .music
                                appState.mode = .expanded
                            }
                            if appState.enableShelfHaptics {
                                appState.hapticService.triggerSnap()
                            }
                        }) {
                            Circle()
                                .fill(Color.white.opacity(0.40))
                                .frame(width: 6, height: 6)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Cambiar a la pestaña de Música")
                        
                        Capsule()
                            .fill(DesignTokens.blue)
                            .frame(
                                width: 15 + (stretch < 0 ? (min(abs(stretch), OverscrollMetrics.maxStretch) / OverscrollMetrics.maxStretch) * OverscrollMetrics.pageIndicatorStretch : 0),
                                height: 5.5
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Extremos: Título a la izquierda, estado/contador a la derecha
                    HStack {
                        // Título y símbolo
                        HStack(spacing: 5) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(DesignTokens.blue)
                            Text("BANDEJA TEMPORAL")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.70))
                        }
                        
                        Spacer()
                        
                        // Acciones de cabecera
                        HStack(spacing: 6) {
                            if !appState.shelfItems.isEmpty {
                                Text("\(appState.shelfItems.count) arch.")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.white.opacity(0.48))
                            }
                            
                            // Botón seleccionar y añadir archivos
                            Button(action: {
                                ShelfStorageService.shared.selectAndAddFiles()
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(Color.white.opacity(0.75))
                                    .padding(4)
                                    .background(Circle().fill(Color.white.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                            .help("Añadir archivos desde el explorador...")
                            
                            if !appState.shelfItems.isEmpty {
                                // Devolver todos los archivos a su origen
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                                        appState.restoreAllShelfItemsToOrigin()
                                    }
                                    if appState.enableShelfHaptics {
                                        appState.hapticService.triggerSnap()
                                    }
                                }) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundColor(Color.white.opacity(0.75))
                                        .padding(4)
                                        .background(Circle().fill(Color.white.opacity(0.10)))
                                }
                                .buttonStyle(.plain)
                                .help("Devolver todos los archivos a su origen en el escritorio")
                                
                                // Enviar a papelera
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                                        appState.emptyShelfToTrash()
                                    }
                                    if appState.enableShelfHaptics {
                                        appState.hapticService.triggerSnap()
                                    }
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundColor(Color.white.opacity(0.60))
                                        .padding(4)
                                        .background(Circle().fill(Color.white.opacity(0.10)))
                                }
                                .buttonStyle(.plain)
                                .help("Mover archivos a la Papelera de macOS")
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                
                // MARK: - Contenido Principal de la Bandeja (Zona de Recepción Vacía)
                if appState.shelfItems.isEmpty {
                    VStack(spacing: 5) {
                        Spacer(minLength: 2)
                        
                        // Icono circular con halo y elevación suave
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            DesignTokens.blue.opacity(isTargeted ? 0.30 : 0.15),
                                            DesignTokens.blue.opacity(isTargeted ? 0.14 : 0.05)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Circle()
                                        .stroke(DesignTokens.blue.opacity(isTargeted ? 0.65 : 0.25), lineWidth: 0.8)
                                )
                            
                            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(isTargeted ? .white : DesignTokens.blue)
                                .scaleEffect(isTargeted ? 1.12 : 1.0)
                        }
                        
                        Text(isTargeted ? "¡Suelta para añadir a la repisa!" : "Sostén tus archivos aquí")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Arrastra fotos o archivos desde el Finder o el escritorio")
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.50))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                        
                        // Botón selector nativo con diseño de cápsula de cristal macOS
                        Button(action: {
                            ShelfStorageService.shared.selectAndAddFiles()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Seleccionar archivos...")
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(DesignTokens.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4.5)
                            .background(Capsule().fill(DesignTokens.blue.opacity(isTargeted ? 0.22 : 0.10)))
                            .overlay(Capsule().stroke(DesignTokens.blue.opacity(isTargeted ? 0.50 : 0.25), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        
                        Spacer(minLength: 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isTargeted ? 0.08 : 0.035),
                                        Color.white.opacity(isTargeted ? 0.04 : 0.015)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        isTargeted ? DesignTokens.blue.opacity(0.85) : Color.white.opacity(0.12),
                                        isTargeted ? DesignTokens.blue.opacity(0.40) : Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isTargeted ? 1.5 : 0.8
                            )
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isTargeted)
                } else {
                    // Zona con archivos sostenidos
                    VStack(spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(appState.shelfItems) { item in
                                    ShelfItemCardView(item: item, onRemove: {
                                        removeItem(item)
                                    })
                                }
                                
                                // Tarjeta interactiva para invitar o pulsar y añadir más archivos
                                Button(action: {
                                    ShelfStorageService.shared.selectAndAddFiles()
                                }) {
                                    VStack(spacing: 5) {
                                        Image(systemName: "plus.circle.dashed")
                                            .font(.system(size: 22, weight: .medium))
                                            .foregroundColor(DesignTokens.blue.opacity(isTargeted ? 1.0 : 0.70))
                                            .scaleEffect(isTargeted ? 1.15 : 1.0)
                                        Text("Añadir más")
                                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                            .foregroundColor(Color.white.opacity(0.55))
                                    }
                                    .frame(width: 74, height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(DesignTokens.blue.opacity(isTargeted ? 0.16 : 0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(
                                                DesignTokens.blue.opacity(isTargeted ? 0.95 : 0.38),
                                                style: StrokeStyle(lineWidth: 1.0, dash: [4, 3])
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Pulsar para añadir archivos desde Finder")
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }
                        .frame(height: 88)
                        
                        // Indicador inferior instructivo
                        HStack(spacing: 6) {
                            Image(systemName: "hand.draw.fill")
                                .font(.system(size: 9.5))
                                .foregroundColor(Color.white.opacity(0.42))
                            Text("Arrastra hacia afuera para mover • Doble clic para abrir • Clic derecho para opciones")
                                .font(.system(size: 9.8, weight: .regular, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.45))
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 16)
            .offset(x: appState.contentOverscrollOffset * 0.45, y: appState.contentVerticalOverscrollOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    // Si el usuario desliza hacia la derecha desde cualquier parte de la bandeja: regresar a Música
                    let tx = value.translation.width
                    let ty = value.translation.height
                    if tx > 24 && abs(tx) > (abs(ty) * 0.7) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            appState.activeTab = .music
                            appState.mode = .expanded
                            appState.overscrollOffset = 0
                            appState.contentOverscrollOffset = 0
                        }
                        if appState.enableShelfHaptics {
                            appState.hapticService.triggerSnap()
                        }
                    }
                }
        )
        .onDrop(of: [.fileURL, .item], isTargeted: Binding(
            get: { appState.isShelfDragTargeted },
            set: { appState.isShelfDragTargeted = $0 }
        )) { providers in
            handleDropProviders(providers)
        }
    }
    
    private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
        // 1. Extraer directamente las rutas reales del escritorio/Finder desde los pasteboards
        var realUrls: [URL] = []
        let pasteboards = [NSPasteboard(name: .drag), NSPasteboard.general]
        
        for pb in pasteboards {
            if let paths = pb.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] {
                for p in paths {
                    let u = URL(fileURLWithPath: p).standardizedFileURL
                    if FileManager.default.fileExists(atPath: u.path) && !realUrls.contains(u) {
                        realUrls.append(u)
                    }
                }
            }
            
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                for u in urls {
                    let canonical = ((u as NSURL).filePathURL ?? u).standardizedFileURL
                    if FileManager.default.fileExists(atPath: canonical.path) && !realUrls.contains(canonical) {
                        realUrls.append(canonical)
                    }
                }
            }
        }
        
        if !realUrls.isEmpty {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                    self.appState.addShelfFiles(urls: realUrls)
                }
            }
            return true
        }
        
        // 2. Fallback asíncrono con NSItemProvider si es texto o elemento no mapeado
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        let canonical = ((url as NSURL).filePathURL ?? url).standardizedFileURL
                        urls.append(canonical)
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let url = item as? URL {
                        let canonical = ((url as NSURL).filePathURL ?? url).standardizedFileURL
                        urls.append(canonical)
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        let canonical = ((url as NSURL).filePathURL ?? url).standardizedFileURL
                        urls.append(canonical)
                    }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                    self.appState.addShelfFiles(urls: urls)
                }
            }
        }
        return true
    }
    
    private func removeItem(_ item: ShelfItem) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
            appState.removeShelfItem(item)
        }
        if appState.enableShelfHaptics {
            appState.hapticService.triggerSnap()
        }
    }
}

// MARK: - Tarjeta de Archivo Individual en la Bandeja
private struct ShelfItemCardView: View {
    let item: ShelfItem
    let onRemove: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if item.isImage {
                        Image(nsImage: item.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(nsImage: item.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(isHovered ? 0.12 : 0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
                
                // Botón devolver al origen si fue movido
                if item.originalURL != nil {
                    Button(action: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                            AppState.shared.restoreShelfItemToOrigin(item)
                        }
                    }) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 13.5))
                            .foregroundColor(DesignTokens.blue)
                            .background(Circle().fill(Color.black.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .offset(x: -4, y: -4)
                    .opacity(isHovered ? 1.0 : 0.0)
                    .help("Devolver a la ubicación original")
                }
                
                // Botón mover a la papelera
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13.5))
                        .foregroundColor(Color.white.opacity(0.88))
                        .background(Circle().fill(Color.black.opacity(0.75)))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .opacity(isHovered ? 1.0 : 0.65)
                .help("Mover a la Papelera")
            }
            
            Text(item.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 68)
            
            if !item.sizeString.isEmpty {
                Text(item.sizeString)
                    .font(.system(size: 8.5, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.48))
                    .frame(width: 68)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.09 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isHovered ? DesignTokens.blue.opacity(0.70) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovered)
        .onHover { isHovered = $0 }
        .onDrag {
            if AppState.shared.enableShelfHaptics {
                AppState.shared.hapticService.triggerSnap()
            }
            AppState.shared.activeDragOutItem = item
            DNDLogger.log("ShelfItemCardView: onDrag iniciado para \(item.name)")
            let provider = NSItemProvider(item: item.url as NSURL, typeIdentifier: UTType.fileURL.identifier)
            provider.suggestedName = item.name
            provider.trackDragOut(item: item) {
                // Callback ejecutado al soltarse exitosamente fuera del notch
                DNDLogger.log("ShelfItemCardView: Drag-out exitoso para \(item.name)! Removiendo de la repisa...")
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    AppState.shared.removeShelfItem(item, moveToTrash: false)
                }
                if AppState.shared.enableShelfHaptics {
                    AppState.shared.hapticService.triggerSnap()
                }
                
                // Si la repisa quedó vacía tras el drag-out, colapsar limpiamente el notch ("clean y bonito")
                if AppState.shared.shelfItems.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                            if MusicService.shared.hasActiveMusic {
                                AppState.shared.mode = .compact
                            } else {
                                AppState.shared.mode = .idle
                            }
                        }
                    }
                }
                
                // Limpieza en segundo plano del archivo temporal stasheado con margen de gracia para que Finder termine la copia
                if item.isStashed {
                    let stashedURL = item.url
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
                        if FileManager.default.fileExists(atPath: stashedURL.path) {
                            try? FileManager.default.removeItem(at: stashedURL)
                            DNDLogger.log("ShelfItemCardView: Archivo stasheado temporal eliminado de disco: \(stashedURL.path)")
                        }
                    }
                }
            }
            return provider
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(item.url)
        }
        .contextMenu {
            Button("Abrir con aplicación predeterminada") {
                NSWorkspace.shared.open(item.url)
            }
            Button("Mostrar en Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Copiar archivo") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([item.url as NSURL])
            }
            Button("Copiar ruta del archivo") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(item.url.path, forType: .string)
            }
            if item.originalURL != nil {
                Divider()
                Button("Devolver a ubicación original") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                        AppState.shared.restoreShelfItemToOrigin(item)
                    }
                }
            }
            Divider()
            Button("Mover a la Papelera", role: .destructive) {
                onRemove()
            }
        }
    }
}
