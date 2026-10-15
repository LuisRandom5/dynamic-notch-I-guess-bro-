import SwiftUI

public struct NotchAlertView: View {
    public var alert: NotchAlert
    
    public var body: some View {
        HStack(spacing: 16) {
            switch alert.type {
            case .magsafe(let percent):
                // MagSafe Apple-style ring
                ZStack {
                    Circle()
                        .stroke(Color.green.opacity(0.2), lineWidth: 4)
                        .frame(width: 52, height: 52)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(percent) / 100.0)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 52, height: 52)
                    
                    VStack(spacing: 1) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.green)
                        Text("\(percent)%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("MagSafe")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("CONECTADO")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                    
                    Text("Carga rápida de macOS activa")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
            case .airpods(let name, let leftPercent, let rightPercent, let casePercent):
                AirPods3DView(
                    name: name,
                    leftPercent: leftPercent,
                    rightPercent: rightPercent,
                    casePercent: casePercent
                )
                
            case .batteryLow(let percent):
                ZStack {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0.0, to: CGFloat(percent) / 100.0)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 52, height: 52)
                    Image(systemName: "battery.25")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.red)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Batería baja")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Te queda un \(percent)% de batería")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
            case .airdrop(let sender, let fileName):
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 52, height: 52)
                    Image(systemName: "airdrop")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("AirDrop de \(sender)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(fileName)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
            case .timer(let remaining):
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 52, height: 52)
                    Image(systemName: "timer")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Temporizador")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Quedan \(remaining)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
            case .custom(let title, let subtitle, let symbol):
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 52, height: 52)
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
