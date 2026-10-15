import SwiftUI
import AppKit

// MARK: - Ala Izquierda: Miniatura Flotante de Archivo Activo en Repisa
public struct ActiveFilePreviewWing: View {
    @EnvironmentObject var appState: AppState
    @State private var isFloating: Bool = false
    @State private var isHovered: Bool = false
    
    private let wingWidth: CGFloat = 52
    
    public init() {}
    
    private var firstItem: ShelfItem? {
        appState.shelfItems.first
    }
    
    public var body: some View {
        ZStack {
            if let item = firstItem {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if item.isImage {
                            Image(nsImage: item.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 19, height: 19)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        } else {
                            Image(nsImage: item.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 15, height: 15)
                                .frame(width: 19, height: 19)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(DesignTokens.blue.opacity(0.18))
                                )
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.35 : 0.20),
                                        Color.white.opacity(isHovered ? 0.15 : 0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.6
                            )
                    )
                    // Halo de custodia activo
                    .shadow(
                        color: DesignTokens.blue.opacity(isHovered ? 0.45 : 0.25),
                        radius: isHovered ? 5 : 3,
                        x: 0,
                        y: 1
                    )
                    
                    // Indicador si hay más de 1 archivo (+1, +2, etc.)
                    if appState.shelfItems.count > 1 {
                        Text("+\(appState.shelfItems.count - 1)")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 2.5)
                            .padding(.vertical, 0.5)
                            .background(Capsule().fill(DesignTokens.blue))
                            .offset(x: 4, y: 3)
                    }
                }
                .offset(y: isFloating ? -1.2 : 1.2)
                .scaleEffect(isHovered ? 1.08 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                    value: isFloating
                )
                .onAppear {
                    isFloating = true
                }
                .onHover { isHovered = $0 }
                .onTapGesture {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        appState.mode = .shelf
                        appState.activeTab = .shelf
                    }
                    if appState.enableShelfHaptics {
                        appState.hapticService.triggerSnap()
                    }
                }
                .help("Archivo custodiado: \(item.name) • Clic para ver bandeja")
            }
        }
        .frame(width: wingWidth, height: 32)
        .contentShape(Rectangle())
    }
}

// MARK: - Ala Derecha: Indicador Activo de Custodia con Ondas Dinámicas y Badge
public struct ActiveFileCustodyWing: View {
    @EnvironmentObject var appState: AppState
    @State private var isHovered: Bool = false
    
    private let wingWidth: CGFloat = 52
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 5) {
            // Ondas vivas de custodia (análogas al visualizador de audio pero para archivos en espera)
            ActiveCustodyWavesView()
            
            // Píldora de bandeja interactiva con pulso de radar
            ActiveFileBadgeView()
        }
        .frame(width: wingWidth + 8, height: 32)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                appState.mode = .shelf
                appState.activeTab = .shelf
            }
            if appState.enableShelfHaptics {
                appState.hapticService.triggerSnap()
            }
        }
    }
}

// MARK: - Ondas Dinámicas de Custodia (Alive Custody Wave)
public struct ActiveCustodyWavesView: View {
    @State private var wavePhase: Bool = false
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 1.8) {
            // Barra 1
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(DesignTokens.blue.opacity(0.85))
                .frame(width: 2.2, height: wavePhase ? 9 : 3.5)
                .animation(
                    Animation.easeInOut(duration: 0.95).repeatForever(autoreverses: true),
                    value: wavePhase
                )
            
            // Barra 2 (central más alta)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DesignTokens.blue, Color(red: 0.20, green: 0.65, blue: 1.00)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2.2, height: wavePhase ? 12 : 5)
                .animation(
                    Animation.easeInOut(duration: 1.15).repeatForever(autoreverses: true).delay(0.15),
                    value: wavePhase
                )
            
            // Barra 3
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(DesignTokens.blue.opacity(0.85))
                .frame(width: 2.2, height: wavePhase ? 7.5 : 3)
                .animation(
                    Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true).delay(0.3),
                    value: wavePhase
                )
        }
        .frame(height: 14)
        .onAppear {
            wavePhase = true
        }
    }
}

// MARK: - Insignia con Pulso de Radar / Respiración (Beacon Pulse)
public struct ActiveFileBadgeView: View {
    @EnvironmentObject var appState: AppState
    @State private var isPulsing: Bool = false
    @State private var isHovered: Bool = false
    
    public init() {}
    
    public var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                appState.mode = .shelf
                appState.activeTab = .shelf
            }
            if appState.enableShelfHaptics {
                appState.hapticService.triggerSnap()
            }
        }) {
            ZStack {
                // Anillo de pulso radar sutil expansivo
                Capsule()
                    .stroke(DesignTokens.blue.opacity(isPulsing ? 0.0 : 0.65), lineWidth: 1.0)
                    .scaleEffect(isPulsing ? 1.30 : 0.98)
                    .opacity(isPulsing ? 0.0 : 0.8)
                    .animation(
                        Animation.easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
                
                // Contenedor principal de la insignia
                HStack(spacing: 3) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(DesignTokens.blue)
                        .scaleEffect(isHovered ? 1.12 : 1.0)
                    
                    Text("\(appState.shelfItems.count)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isHovered ? 0.22 : 0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            DesignTokens.blue.opacity(isHovered ? 0.70 : 0.40),
                            lineWidth: 0.7
                        )
                )
                // Resplandor reactivo
                .shadow(
                    color: DesignTokens.blue.opacity(isPulsing ? 0.45 : 0.15),
                    radius: isPulsing ? 4 : 2,
                    x: 0,
                    y: 0
                )
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.06 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            isPulsing = true
        }
        .help("\(appState.shelfItems.count) archivo(s) en la bandeja • Clic para ver")
    }
}
