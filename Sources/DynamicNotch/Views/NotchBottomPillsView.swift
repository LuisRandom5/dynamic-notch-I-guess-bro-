import SwiftUI

public enum BottomTab: String, CaseIterable, Identifiable {
    case home = "home"
    case music = "music"
    case grid = "grid"
    case shelf = "shelf"
    case clipboard = "clipboard"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .music: return "music.note"
        case .grid: return "square.grid.2x2.fill"
        case .shelf: return "folder.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        }
    }
}

public struct NotchBottomPillsView: View {
    @Binding var selectedTab: BottomTab
    @Namespace private var tabNamespace
    @EnvironmentObject var appState: AppState
    
    private let leftGroup: [BottomTab] = [.home, .music, .grid]
    private let rightGroup: [BottomTab] = [.shelf, .clipboard]
    
    public var body: some View {
        HStack(spacing: 12) {
            // Píldora Izquierda (Casa, Música, Cuadrícula)
            HStack(spacing: 4) {
                ForEach(leftGroup) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(Color.black)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
            
            // Píldora Derecha (Bandeja/Archivo, Portapapeles)
            HStack(spacing: 4) {
                ForEach(rightGroup) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(Color.black)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
        }
    }
    
    @ViewBuilder
    private func tabButton(for tab: BottomTab) -> some View {
        Button(action: {
            appState.hapticService.triggerSnap()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selectedTab = tab
            }
        }) {
            ZStack {
                if selectedTab == tab {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .matchedGeometryEffect(id: "activeTabBadge", in: tabNamespace)
                        .frame(width: 32, height: 26)
                }
                
                Image(systemName: tab.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(selectedTab == tab ? .white : Color.white.opacity(0.45))
                    .frame(width: 32, height: 26)
            }
        }
        .buttonStyle(BouncyButtonStyle(scaleAmount: 0.88))
    }
}
