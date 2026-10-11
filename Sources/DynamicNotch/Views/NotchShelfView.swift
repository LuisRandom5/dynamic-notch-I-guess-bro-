import SwiftUI
import UniformTypeIdentifiers

public struct NotchShelfView: View {
    @EnvironmentObject var appState: AppState
    @State private var isTargeted: Bool = false
    
    public var body: some View {
        VStack(spacing: 12) {
            if appState.shelfItems.isEmpty {
                // Empty drop target
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 26))
                        .foregroundColor(isTargeted ? .blue : .white.opacity(0.4))
                    
                    Text("Arrastra archivos aquí")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Guarda capturas o documentos temporalmente en el notch")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.blue : Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                )
            } else {
                // Shelf items horizontal grid
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(appState.shelfItems) { item in
                            VStack(spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: item.icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 44, height: 44)
                                    
                                    Button(action: {
                                        appState.removeShelfItem(item)
                                        appState.hapticService.triggerSnap()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 4, y: -4)
                                }
                                
                                Text(item.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .frame(width: 60)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .frame(height: 80)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let fileUrl = url {
                        DispatchQueue.main.async {
                            appState.addShelfFile(url: fileUrl)
                        }
                    }
                }
            }
            return true
        }
    }
}
