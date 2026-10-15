import SwiftUI
import AppKit
import SceneKit

// MARK: - ActivityAirPodsPillView (Tarjeta 3D Expandida de Conexión de AirPods)
/// Tarjeta desplegada con animación nativa SceneKit de 360° en 3D para la conexión de AirPods:
/// - Dimensiones de tarjeta: 360 x 170 pt, anclada orgánicamente al notch físico.
/// - Canvas 3D SceneKit: Renderiza proceduralmente los AirPods con materiales Apple (plástico cerámico brillante y rejilla acústica negra).
/// - Fila inferior: Nombre del dispositivo y nivel de carga (con soporte para auricular izquierdo, derecho y estuche).
public struct ActivityAirPodsPillView: View {
    public let activity: LiveActivity
    @EnvironmentObject var screenService: ScreenService
    @ObservedObject var center = ActivityCenter.shared
    
    @State private var triggerSpin: Bool = false
    @State private var isContentRevealed: Bool = true
    
    public init(activity: LiveActivity) {
        self.activity = activity
    }
    
    private var isContentVisible: Bool {
        isContentRevealed && center.dismissingActivityId != activity.id
    }
    
    private var airpodsState: AirPodsActivityState {
        activity.airpodsState ?? AirPodsActivityState(name: "AirPods Pro", batteryLevel: 100)
    }
    
    private var modelName: String {
        let name = airpodsState.name
        if name.isEmpty { return "AirPods" }
        return name
    }
    
    private var batteryLevel: Int {
        airpodsState.batteryLevel
    }
    
    // Verde Apple idéntico a iOS (#30D158)
    private let appleBatteryGreen = Color(red: 0x30 / 255.0, green: 0xD1 / 255.0, blue: 0x58 / 255.0)
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Canvas 3D Nativo con giro 360° espacioso
            AirPodsSceneView(animate: $triggerSpin)
                .frame(width: 360, height: 102)
                .padding(.top, 38) // Despeja completamente el notch físico
                .opacity(isContentVisible ? 1.0 : 0.0)
                .scaleEffect(isContentVisible ? 1.0 : 0.90)
                .animation(.spring(response: 0.44, dampingFraction: 0.80), value: isContentVisible)
            
            Spacer(minLength: 0)
            
            // MARK: - Estadísticas de Conexión / Batería (Fila Limpia y Elegante)
            HStack(alignment: .center) {
                Text(modelName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "battery.100.bolt")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(appleBatteryGreen)
                    Text("\(batteryLevel)%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
            .opacity(isContentVisible ? 1.0 : 0.0)
            .offset(y: isContentVisible ? 0 : 8)
            .animation(.easeOut(duration: 0.25).delay(0.08), value: isContentVisible)
        }
        .frame(width: 370, height: 175, alignment: .top)
        .onAppear {
            withAnimation(.easeOut(duration: 0.20)) {
                isContentRevealed = true
            }
            // Disparar giro 3D coordinado con la apertura de la tarjeta
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                triggerSpin = true
            }
        }
    }
}

// MARK: - Escena 3D Nativa (SceneKit)
public struct AirPodsSceneView: NSViewRepresentable {
    @Binding public var animate: Bool
    
    public init(animate: Binding<Bool>) {
        self._animate = animate
    }
    
    public func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        let scene = SCNScene()
        scnView.scene = scene
        scnView.backgroundColor = .clear
        scnView.wantsLayer = true
        scnView.layer?.isOpaque = false
        scnView.antialiasingMode = .multisampling4X
        scnView.isPlaying = true
        scnView.loops = true
        
        // Cámara con distancia focal ideal para perspectiva elegante
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 34
        cameraNode.position = SCNVector3(0, 0.12, 4.4)
        scene.rootNode.addChildNode(cameraNode)
        
        // Luces tipo estudio Apple
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 750
        ambientLight.light?.color = NSColor.white
        scene.rootNode.addChildNode(ambientLight)
        
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 1300
        keyLight.position = SCNVector3(3, 4, 3)
        scene.rootNode.addChildNode(keyLight)
        
        // --- NODO PADRE (Plataforma rígida compartida) ---
        let airPodsRig = SCNNode()
        airPodsRig.name = "airPodsRig"
        
        // Separación amplia (0.74) para que respire con libertad sin verse amontonado
        let separation: Float = 0.74
        let leftEarbud = createAirPod(isRight: false)
        leftEarbud.position = SCNVector3(-separation, 0, 0)
        
        let rightEarbud = createAirPod(isRight: true)
        rightEarbud.position = SCNVector3(separation, 0, 0)
        
        // Ambos auriculares se montan como hijos del mismo padre
        airPodsRig.addChildNode(leftEarbud)
        airPodsRig.addChildNode(rightEarbud)
        
        scene.rootNode.addChildNode(airPodsRig)
        
        return scnView
    }
    
    public func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.isPlaying = true
        guard let rig = nsView.scene?.rootNode.childNode(withName: "airPodsRig", recursively: true) else { return }
        
        if animate {
            DNDLogger.log("AirPodsSceneView: Starting 3D spin animation on airPodsRig")
            rig.removeAllActions()
            // Animación suave de giro completo (360°) en bloque sobre el eje Y
            let rotation = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 1.8)
            rotation.timingMode = .easeInEaseOut
            
            // Sutil cabeceo en X durante el giro para mostrar perspectiva 3D
            let pitchUp = SCNAction.rotateBy(x: 0.14, y: 0, z: 0, duration: 0.9)
            pitchUp.timingMode = .easeInEaseOut
            let pitchDown = pitchUp.reversed()
            let pitchSeq = SCNAction.sequence([pitchUp, pitchDown])
            
            rig.runAction(SCNAction.group([rotation, pitchSeq])) {
                DispatchQueue.main.async {
                    self.animate = false
                    DNDLogger.log("AirPodsSceneView: 3D spin animation completed")
                }
            }
        }
    }
    
    // Generador geométrico y material de un AirPod
    private func createAirPod(isRight: Bool) -> SCNNode {
        let node = SCNNode()
        
        // Material plástico blanco brillante Apple
        let whitePlastic = SCNMaterial()
        whitePlastic.diffuse.contents = NSColor(white: 0.96, alpha: 1.0)
        whitePlastic.roughness.contents = 0.12
        whitePlastic.metalness.contents = 0.0
        
        // Material de rejilla acústica negra
        let blackGrill = SCNMaterial()
        blackGrill.diffuse.contents = NSColor(white: 0.1, alpha: 1.0)
        blackGrill.roughness.contents = 0.9
        
        // Cabeza
        let headGeo = SCNSphere(radius: 0.36)
        headGeo.materials = [whitePlastic]
        let headNode = SCNNode(geometry: headGeo)
        headNode.scale = SCNVector3(1.0, 1.15, 0.95)
        headNode.position = SCNVector3(0, 0.4, 0)
        node.addChildNode(headNode)
        
        // Rejilla de audio interna
        let grillGeo = SCNCylinder(radius: 0.13, height: 0.02)
        grillGeo.materials = [blackGrill]
        let grillNode = SCNNode(geometry: grillGeo)
        grillNode.rotation = SCNVector4(0, 0, 1, CGFloat.pi / 2)
        grillNode.position = SCNVector3(isRight ? -0.32 : 0.32, 0.4, 0.06)
        node.addChildNode(grillNode)
        
        // Tallo
        let stemGeo = SCNCylinder(radius: 0.082, height: 0.72)
        stemGeo.materials = [whitePlastic]
        let stemNode = SCNNode(geometry: stemGeo)
        stemNode.position = SCNVector3(0, 0, 0)
        node.addChildNode(stemNode)
        
        // Inclinación ergonómica fanning hacia afuera (+/- 0.16)
        node.rotation = SCNVector4(0, 0, 1, isRight ? -0.16 : 0.16)
        
        return node
    }
}
