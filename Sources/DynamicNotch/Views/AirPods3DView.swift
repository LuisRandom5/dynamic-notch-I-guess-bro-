import SwiftUI

/// Representación visual animada en 3D de AirPods conectándose al estilo Dynamic Island del iPhone.
/// Incluye rotación física en perspectiva 3D, reflejo especular, y anillos dinámicos de batería.
public struct AirPods3DView: View {
    public let name: String
    public let leftPercent: Int
    public let rightPercent: Int
    public let casePercent: Int
    
    @State private var rotationY: Double = -65.0
    @State private var scale: CGFloat = 0.75
    @State private var opacity: Double = 0.0
    @State private var ringProgress: CGFloat = 0.0
    @State private var isSpinningContinuous: Bool = false
    
    public init(name: String, leftPercent: Int, rightPercent: Int, casePercent: Int) {
        self.name = name
        self.leftPercent = leftPercent
        self.rightPercent = rightPercent
        self.casePercent = casePercent
    }
    
    private var isAirPodsMax: Bool {
        name.localizedCaseInsensitiveContains("Max")
    }
    
    private var isAirPodsPro: Bool {
        name.localizedCaseInsensitiveContains("Pro") || (!isAirPodsMax && !name.localizedCaseInsensitiveContains("3"))
    }
    
    public var body: some View {
        HStack(spacing: 16) {
            // Contenedor 3D de los AirPods
            ZStack {
                // Sombra de piso
                Ellipse()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 48, height: 10)
                    .offset(y: 22)
                    .blur(radius: 3)
                    .scaleEffect(scale)
                
                // Representación de los auriculares
                HStack(spacing: 6) {
                    // Auricular Izquierdo
                    podView(isLeft: true)
                    
                    // Auricular Derecho
                    podView(isLeft: false)
                }
                .rotation3DEffect(
                    .degrees(rotationY),
                    axis: (x: 0.1, y: 1.0, z: 0.0),
                    anchor: .center,
                    perspective: 0.55
                )
                .scaleEffect(scale)
                .opacity(opacity)
            }
            .frame(width: 58, height: 52)
            
            // Detalles del dispositivo e indicadores de batería
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("CONECTADO")
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.24))
                        .foregroundColor(Color(red: 0.35, green: 0.70, blue: 1.0))
                        .clipShape(Capsule())
                }
                
                // Anillos de batería individuales
                HStack(spacing: 14) {
                    batteryGauge(
                        icon: "airpodpro.left",
                        percent: leftPercent,
                        label: "I"
                    )
                    
                    batteryGauge(
                        icon: "airpodpro.right",
                        percent: rightPercent,
                        label: "D"
                    )
                    
                    if casePercent > 0 {
                        batteryGauge(
                            icon: "airpodspro.chargingcase.wireless",
                            percent: casePercent,
                            label: "Estuche"
                        )
                    }
                }
            }
        }
        .onAppear {
            // Animación de entrada con física elástica de la isla dinámica
            withAnimation(.spring(response: 0.62, dampingFraction: 0.72)) {
                rotationY = 0.0
                scale = 1.0
                opacity = 1.0
            }
            
            withAnimation(.easeOut(duration: 0.85).delay(0.15)) {
                ringProgress = 1.0
            }
        }
    }
    
    // Vista individual de un auricular con acabado vítreo y brillo cerámico
    private func podView(isLeft: Bool) -> some View {
        ZStack {
            // Cuerpo del auricular
            VStack(spacing: 0) {
                // Cabeza
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.98),
                                Color(white: 0.82),
                                Color(white: 0.68)
                            ],
                            startPoint: isLeft ? .topLeading : .topTrailing,
                            endPoint: isLeft ? .bottomTrailing : .bottomLeading
                        )
                    )
                    .frame(width: 17, height: 17)
                    .overlay(
                        // Rejilla acústica negra
                        Ellipse()
                            .fill(Color(white: 0.22))
                            .frame(width: 5, height: 3.5)
                            .offset(x: isLeft ? -3.5 : 3.5, y: -1)
                    )
                
                // Vástago (Stem)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.90),
                                Color(white: 0.75)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 5.5, height: isAirPodsPro ? 16 : 22)
                    .overlay(
                        // Punta plateada de carga
                        VStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(white: 0.85), Color(white: 0.45)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 5.5, height: 2.5)
                        }
                    )
                    .offset(x: isLeft ? 2 : -2, y: -2)
            }
            // Reflejo de brillo cerámico blanco
            Ellipse()
                .fill(Color.white.opacity(0.85))
                .frame(width: 5, height: 3)
                .offset(x: isLeft ? -2 : 2, y: -6)
        }
        .rotationEffect(.degrees(isLeft ? 8 : -8))
    }
    
    // Indicador de batería circular con icono
    private func batteryGauge(icon: String, percent: Int, label: String) -> some View {
        HStack(spacing: 4) {
            ZStack {
                // Fondo del anillo
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2)
                    .frame(width: 16, height: 16)
                
                // Progreso de batería verde/ámbar
                Circle()
                    .trim(from: 0, to: (CGFloat(percent) / 100.0) * ringProgress)
                    .stroke(
                        percent > 20
                            ? Color(red: 0.20, green: 0.84, blue: 0.40)
                            : Color(red: 1.00, green: 0.60, blue: 0.00),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 16, height: 16)
                
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.85))
            }
            
            RollingNumberView(
                value: percent,
                suffix: "%",
                font: .system(size: 11, weight: .bold, design: .rounded),
                color: .white,
                alignment: .center
            )
        }
    }
}
