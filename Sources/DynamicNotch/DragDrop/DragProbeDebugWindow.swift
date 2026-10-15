import AppKit
import SwiftUI

// MARK: - DragProbeDebugWindow (Ventana de Depuración de Arrastre - Paso 0)
public final class DragProbeDebugWindowController: NSWindowController {
    public static let shared = DragProbeDebugWindowController()
    
    private init() {
        let window = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 380, height: 420),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "Sonda Drag & Drop (Paso 0)"
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: DragProbeDebugView())
        window.isReleasedWhenClosed = false
        window.center()
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func toggleWindow() {
        guard let win = window else { return }
        if win.isVisible {
            win.orderOut(nil)
        } else {
            DragDetectionProbe.shared.startProbe()
            win.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - DragProbeDebugView (UI de Monitoreo en Tiempo Real)
public struct DragProbeDebugView: View {
    @ObservedObject var probe = DragDetectionProbe.shared
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Cabecera con estado de actividad
            HStack {
                Circle()
                    .fill(probe.isDragging ? Color.green : (probe.isMouseDown ? Color.orange : Color.gray.opacity(0.5)))
                    .frame(width: 12, height: 12)
                    .shadow(color: (probe.isDragging ? Color.green : Color.clear).opacity(0.6), radius: 4)
                
                Text(probe.isDragging ? "ARRASTRE EN CURSO" : (probe.isMouseDown ? "BOTÓN PRESIONADO" : "EN ESPERA"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("changeCount: \(probe.lastChangeCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.bottom, 2)
            
            Divider()
                .background(Color.white.opacity(0.15))
            
            // Sección: Distancia al Notch y Proximidad
            VStack(alignment: .leading, spacing: 6) {
                Text("DISTANCIA AL NOTCH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.50))
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(probe.distanceToNotch)) pt")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(probe.distanceToNotch <= 240 ? Color.green : .white)
                        Text("Euclidiana")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(probe.verticalDistanceToNotch)) pt")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                        Text("Vertical (Y)")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                
                // Barra de Proximidad 0 a 1 (240 pt a 0 pt)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Proximidad (0.0 → 1.0):")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(String(format: "%.2f", probe.proximity))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(probe.proximity > 0 ? Color.green : .white.opacity(0.5))
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 7)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.green],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * probe.proximity), height: 7)
                                .animation(.spring(response: 0.20, dampingFraction: 0.82), value: probe.proximity)
                        }
                    }
                    .frame(height: 7)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            
            // Sección: Elementos y Tipos Detectados
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ELEMENTOS EN EL PASTEBOARD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.50))
                    Spacer()
                    Text("\(probe.itemCount) item(s)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(probe.itemCount > 0 ? Color.blue : .white.opacity(0.4))
                }
                
                // Tipos
                if probe.detectedTypes.isEmpty {
                    Text("Sin tipos activos (arrastra un archivo desde Finder para probar)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.vertical, 4)
                } else {
                    HStack(spacing: 5) {
                        ForEach(probe.detectedTypes, id: \.self) { type in
                            Text(type)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(Color.blue.opacity(0.25)))
                                .foregroundColor(Color.blue)
                        }
                    }
                }
                
                // Vista previa de items
                if !probe.previewItems.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(probe.previewItems, id: \.self) { item in
                            HStack(spacing: 4) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.white.opacity(0.6))
                                Text(item)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            
            // Estado y Mensaje en vivo
            Text(probe.statusMessage)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(2)
            
            Spacer(minLength: 4)
            
            // Botones de control
            HStack {
                Button(action: {
                    probe.startProbe()
                }) {
                    Text("Reiniciar Sonda")
                        .font(.system(size: 11, weight: .medium))
                }
                
                Spacer()
                
                Button(action: {
                    DragProbeDebugWindowController.shared.toggleWindow()
                }) {
                    Text("Cerrar")
                        .font(.system(size: 11))
                }
            }
        }
        .padding(16)
        .frame(width: 380, height: 420)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
    }
}
