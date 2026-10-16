import SwiftUI
import AppKit
import SceneKit

// MARK: - ActivityAirPodsPillView (Tarjeta 3D Expandida de Conexión de AirPods)
/// Tarjeta desplegada con animación nativa SceneKit de 360° en 3D para la conexión de AirPods:
/// - Dimensiones de tarjeta: 370 x 175 pt, anclada orgánicamente al notch físico.
/// - Canvas 3D SceneKit: Renderiza proceduralmente los AirPods con materiales PBR Apple (cerámica con clearCoat, punta de silicona, rejillas acústicas y anillo de carga cromado).
/// - GPU 0% en reposo: `rendersContinuously` se desactiva automáticamente al concluir el giro.
public struct ActivityAirPodsPillView: View {
    public let activity: LiveActivity
    @EnvironmentObject var screenService: ScreenService
    @ObservedObject var center = ActivityCenter.shared
    
    @State private var triggerSpin: Bool = false
    @State private var isContentRevealed: Bool = true
    @State private var batteryRingProgress: CGFloat = 0.0
    
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
        if name.isEmpty { return "AirPods Pro" }
        return name
    }
    
    private var batteryLevel: Int {
        max(0, min(100, airpodsState.batteryLevel))
    }
    
    // Verde Apple idéntico a iOS (#30D158)
    private let appleBatteryGreen = Color(red: 0x30 / 255.0, green: 0xD1 / 255.0, blue: 0x58 / 255.0)
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Canvas 3D Nativo con giro 360° espacioso y brillo de estudio
            AirPodsSceneView(animate: $triggerSpin)
                .frame(width: 360, height: 104)
                .padding(.top, 36) // Despeja completamente el notch físico
                .opacity(isContentVisible ? 1.0 : 0.0)
                .scaleEffect(isContentVisible ? 1.0 : 0.88)
                .animation(.spring(response: 0.44, dampingFraction: 0.80), value: isContentVisible)
            
            Spacer(minLength: 0)
            
            // MARK: - Estadísticas de Conexión / Batería (Fila Estilo iOS 18)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(modelName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("Conectado • Audio espacial")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.50))
                }
                
                Spacer()
                
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.16), lineWidth: 2.4)
                            .frame(width: 20, height: 20)
                        
                        Circle()
                            .trim(from: 0, to: (CGFloat(batteryLevel) / 100.0) * batteryRingProgress)
                            .stroke(
                                batteryLevel > 20 ? appleBatteryGreen : DesignTokens.orange,
                                style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 20, height: 20)
                        
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(batteryLevel > 20 ? appleBatteryGreen : DesignTokens.orange)
                    }
                    
                    Text("\(batteryLevel)%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 18)
            .opacity(isContentVisible ? 1.0 : 0.0)
            .offset(y: isContentVisible ? 0 : 8)
            .animation(.easeOut(duration: 0.25).delay(0.08), value: isContentVisible)
        }
        .frame(width: 370, height: 175, alignment: .top)
        .onAppear {
            withAnimation(.easeOut(duration: 0.20)) {
                isContentRevealed = true
            }
            withAnimation(.spring(response: 0.75, dampingFraction: 0.82).delay(0.15)) {
                batteryRingProgress = 1.0
            }
            // Disparar giro 3D coordinado con la apertura de la tarjeta
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                triggerSpin = true
            }
        }
    }
}

// MARK: - Escena 3D Nativa (SceneKit con Materiales PBR y 0% GPU en Reposo)
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
        // Ahorro energético: solo renderiza bajo demanda o mientras corre una SCNAction
        scnView.rendersContinuously = false
        scnView.isPlaying = false
        scnView.loops = false
        
        // Cámara con distancia focal ideal para perspectiva de estudio Apple
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.wantsHDR = true
        camera.bloomIntensity = 0.15
        camera.bloomThreshold = 0.85
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.14, 4.35)
        scene.rootNode.addChildNode(cameraNode)
        
        // Iluminación de estudio de 3 puntos (Key + Rim + Fill)
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 650
        ambientLight.light?.color = NSColor(calibratedWhite: 0.96, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
        
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 1350
        keyLight.light?.color = NSColor.white
        keyLight.position = SCNVector3(2.8, 3.8, 3.5)
        keyLight.eulerAngles = SCNVector3(-0.6, 0.5, 0)
        scene.rootNode.addChildNode(keyLight)
        
        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .omni
        rimLight.light?.intensity = 900
        rimLight.light?.color = NSColor(calibratedRed: 0.78, green: 0.88, blue: 1.0, alpha: 1.0)
        rimLight.position = SCNVector3(-3.0, 2.2, -2.5)
        scene.rootNode.addChildNode(rimLight)
        
        // --- NODO PADRE (Plataforma rígida compartida) ---
        let airPodsRig = SCNNode()
        airPodsRig.name = "airPodsRig"
        
        let separation: Float = 0.72
        let leftEarbud = createAirPod(isRight: false)
        leftEarbud.position = SCNVector3(-separation, -0.02, 0)
        leftEarbud.eulerAngles = SCNVector3(0.06, 0.28, 0.14)
        
        let rightEarbud = createAirPod(isRight: true)
        rightEarbud.position = SCNVector3(separation, -0.02, 0)
        rightEarbud.eulerAngles = SCNVector3(0.06, -0.28, -0.14)
        
        airPodsRig.addChildNode(leftEarbud)
        airPodsRig.addChildNode(rightEarbud)
        
        scene.rootNode.addChildNode(airPodsRig)
        
        return scnView
    }
    
    public func updateNSView(_ nsView: SCNView, context: Context) {
        guard let rig = nsView.scene?.rootNode.childNode(withName: "airPodsRig", recursively: true) else { return }
        
        if animate {
            nsView.isPlaying = true
            nsView.rendersContinuously = true
            rig.removeAllActions()
            
            // Giro de 360° con curva easeInEaseOut y flotación orgánica en Y/X
            let rotation = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 2.0)
            rotation.timingMode = .easeInEaseOut
            
            let pitchUp = SCNAction.rotateBy(x: 0.16, y: 0, z: 0, duration: 1.0)
            pitchUp.timingMode = .easeInEaseOut
            let pitchSeq = SCNAction.sequence([pitchUp, pitchUp.reversed()])
            
            let floatUp = SCNAction.moveBy(x: 0, y: 0.08, z: 0, duration: 1.0)
            floatUp.timingMode = .easeInEaseOut
            let floatSeq = SCNAction.sequence([floatUp, floatUp.reversed()])
            
            rig.runAction(SCNAction.group([rotation, pitchSeq, floatSeq])) {
                DispatchQueue.main.async {
                    nsView.rendersContinuously = false
                    nsView.isPlaying = false
                    self.animate = false
                }
            }
        }
    }
    
    // Generador geométrico PBR de un AirPod Pro con punta acústica y anillo cromado
    private func createAirPod(isRight: Bool) -> SCNNode {
        let node = SCNNode()
        let sideSign: CGFloat = isRight ? -1.0 : 1.0
        
        // Material cerámico blanco brillante Apple (PBR con ClearCoat)
        let ceramicWhite = SCNMaterial()
        ceramicWhite.lightingModel = .physicallyBased
        ceramicWhite.diffuse.contents = NSColor(calibratedWhite: 0.97, alpha: 1.0)
        ceramicWhite.roughness.contents = 0.08
        ceramicWhite.metalness.contents = 0.03
        ceramicWhite.specular.contents = NSColor.white
        
        // Material de silicona suave para la almohadilla (Ear Tip)
        let siliconeTip = SCNMaterial()
        siliconeTip.lightingModel = .physicallyBased
        siliconeTip.diffuse.contents = NSColor(calibratedWhite: 0.93, alpha: 0.96)
        siliconeTip.roughness.contents = 0.35
        siliconeTip.metalness.contents = 0.0
        
        // Material de rejilla acústica negra titanio
        let blackGrill = SCNMaterial()
        blackGrill.lightingModel = .physicallyBased
        blackGrill.diffuse.contents = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        blackGrill.roughness.contents = 0.65
        blackGrill.metalness.contents = 0.25
        
        // Material cromado para el contacto de carga inferior
        let chromeRing = SCNMaterial()
        chromeRing.lightingModel = .physicallyBased
        chromeRing.diffuse.contents = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        chromeRing.metalness.contents = 0.88
        chromeRing.roughness.contents = 0.16
        
        // 1. Cabeza ergonómica principal
        let headGeo = SCNSphere(radius: 0.35)
        headGeo.segmentCount = 48
        headGeo.materials = [ceramicWhite]
        let headNode = SCNNode(geometry: headGeo)
        headNode.scale = SCNVector3(1.08, 0.96, 0.90)
        headNode.position = SCNVector3(0, 0.38, 0.02)
        node.addChildNode(headNode)
        
        // 2. Almohadilla de silicona orientada hacia el interior
        let tipGeo = SCNCapsule(capRadius: 0.20, height: 0.42)
        tipGeo.materials = [siliconeTip]
        let tipNode = SCNNode(geometry: tipGeo)
        tipNode.eulerAngles = SCNVector3(0, 0, Float(sideSign * (.pi / 2.2)))
        tipNode.position = SCNVector3(Float(sideSign * 0.28), 0.36, 0.05)
        node.addChildNode(tipNode)
        
        // 3. Rejilla de ventilación acústica exterior
        let outerVentGeo = SCNCylinder(radius: 0.075, height: 0.02)
        outerVentGeo.materials = [blackGrill]
        let outerVentNode = SCNNode(geometry: outerVentGeo)
        outerVentNode.eulerAngles = SCNVector3(0, 0, Float(sideSign * (.pi / 2)))
        outerVentNode.position = SCNVector3(Float(-sideSign * 0.35), 0.43, 0.02)
        outerVentNode.scale = SCNVector3(1.6, 1.0, 0.75)
        node.addChildNode(outerVentNode)
        
        // 4. Vástago (Stem) con extremos redondeados
        let stemGeo = SCNCapsule(capRadius: 0.082, height: 0.82)
        stemGeo.materials = [ceramicWhite]
        let stemNode = SCNNode(geometry: stemGeo)
        stemNode.position = SCNVector3(Float(-sideSign * 0.06), -0.02, 0)
        node.addChildNode(stemNode)
        
        // 5. Anillo cromado inferior de carga
        let ringGeo = SCNCylinder(radius: 0.081, height: 0.06)
        ringGeo.materials = [chromeRing]
        let ringNode = SCNNode(geometry: ringGeo)
        ringNode.position = SCNVector3(Float(-sideSign * 0.06), -0.36, 0)
        node.addChildNode(ringNode)
        
        return node
    }
}

