import SwiftUI
import UniformTypeIdentifiers
import AppKit

public struct NotchShelfView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var musicService: MusicService
    @State private var isTargeted: Bool = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 10) {
            if appState.shelfItems.isEmpty {
                // MARK: - Estado Vacío: Zona de recepción al arrastrar
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 28))
                        .foregroundColor(isTargeted ? DesignTokens.blue : Color.white.opacity(0.45))
                        .scaleEffect(isTargeted ? 1.12 : 1.0)
                        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isTargeted)
                    
                    Text(isTargeted ? "¡Suelta para guardar en el Notch!" : "Arrastra un archivo aquí")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Guarda archivos temporalmente para moverlos con facilidad")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isTargeted ? DesignTokens.blue : Color.white.opacity(0.14),
                            style: StrokeStyle(lineWidth: isTargeted ? 2.0 : 1.2, dash: [6, 4])
                        )
                )
            } else {
                // MARK: - Estado con Archivos Guardados
                VStack(spacing: 8) {
                    // Cabecera minimalista
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(DesignTokens.blue)
                            Text("BANDEJA TEMPORAL")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.60))
                        }
                        
                        Spacer()
                        
                        Text("\(appState.shelfItems.count) archivo\(appState.shelfItems.count == 1 ? "" : "s")")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.45))
                    }
                    .padding(.horizontal, 4)
                    
                    // Carrusel horizontal de archivos interactivos
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(appState.shelfItems) { item in
                                VStack(spacing: 5) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(nsImage: item.icon)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 42, height: 42)
                                            .padding(6)
                                            .background(Color.white.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        
                                        // Botón eliminar para descartar
                                        Button(action: {
                                            removeItem(item)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(Color.white.opacity(0.70))
                                                .background(Circle().fill(Color.black.opacity(0.6)))
                                        }
                                        .buttonStyle(.plain)
                                        .offset(x: 5, y: -5)
                                    }
                                    
                                    Text(item.name)
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .frame(width: 64)
                                }
                                .padding(6)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                                .onDrag {
                                    appState.hapticService.triggerExpand()
                                    return NSItemProvider(object: item.url as NSURL)
                                }
                                .onTapGesture {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(height: 74)
                    
                    // Indicador inferior
                    Text("Arrastra los archivos hacia afuera para moverlos")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.38))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 34) // Despeja la cámara del notch físico
        .padding(.bottom, 12)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }
    
    private func removeItem(_ item: ShelfItem) {
        appState.removeShelfItem(item)
        appState.hapticService.triggerSnap()
        
        // Si ya no quedan archivos, el menú se cierra automáticamente y deja de ser accesible
        if appState.shelfItems.isEmpty {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                if musicService.hasActiveMusic && appState.showCompactWhenPlaying {
                    appState.mode = .compact
                } else {
                    appState.mode = .idle
                }
            }
        }
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let fileUrl = url {
                    DispatchQueue.main.async {
                        self.appState.addShelfFile(url: fileUrl)
                    }
                }
            }
        }
        return true
    }
}
