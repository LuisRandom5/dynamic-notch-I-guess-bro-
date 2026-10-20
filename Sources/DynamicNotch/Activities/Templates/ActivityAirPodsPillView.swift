import SwiftUI
import AppKit
import SceneKit

// MARK: - AnimatedGIFView (Reproductor nativo de GIFs en bucle para AppKit/SwiftUI)
public struct AnimatedGIFView: NSViewRepresentable {
    public let gifURL: URL
    public let size: CGSize
    
    public init(gifURL: URL, size: CGSize = CGSize(width: 30, height: 26)) {
        self.gifURL = gifURL
        self.size = size
    }
    
    public func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.canDrawSubviewsIntoLayer = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        if let image = NSImage(contentsOf: gifURL) {
            imageView.image = image
        }
        return imageView
    }
    
    public func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image == nil, let image = NSImage(contentsOf: gifURL) {
            nsView.image = image
            nsView.animates = true
        }
    }
    
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        return size
    }
}

// MARK: - ActivityAirPodsPillView (Alas Compactas de Conexión de AirPods en el Notch)
/// Diseño compacto en alas simétricas a los lados del Notch:
/// - Ala izquierda: Animación de los AirPods girando en bucle (AirPods 3/4/5 o Pro 2) ajustada a escala miniatura.
/// - Espacio central: Sensor de cámara del MacBook.
/// - Ala derecha: Círculo de batería en verde (>30%) o rojo (<=29%), limpio sin números ni símbolo de rayo.
public struct ActivityAirPodsPillView: View {
    public let activity: LiveActivity
    @EnvironmentObject var screenService: ScreenService
    @ObservedObject var center = ActivityCenter.shared
    
    @State private var batteryRingProgress: CGFloat = 0.0
    private let wingWidth: CGFloat = 52
    
    // Verde Apple (#30D158)
    private let appleBatteryGreen = Color(red: 0x30 / 255.0, green: 0xD1 / 255.0, blue: 0x58 / 255.0)
    
    public init(activity: LiveActivity) {
        self.activity = activity
    }
    
    private var airpodsState: AirPodsActivityState {
        activity.airpodsState ?? AirPodsActivityState(name: "AirPods", batteryLevel: 100)
    }
    
    private var modelName: String {
        let name = airpodsState.name
        if name.isEmpty { return "AirPods" }
        return name
    }
    
    private var batteryLevel: Int {
        max(0, min(100, airpodsState.batteryLevel))
    }
    
    private var animationURL: URL? {
        let lower = modelName.lowercased()
        
        // 1. AirPods Pro 2 / Pro (cuando esté disponible el asset de Pro 2)
        if lower.contains("pro") {
            if let bundlePro = Bundle.main.url(forResource: "airpods_pro_2", withExtension: "gif") {
                return bundlePro
            }
            let docPro = "/Users/luisangelceroncastro/Documents/animaciones (creo que terminadas)/airpods pro 2.gif"
            if FileManager.default.fileExists(atPath: docPro) {
                return URL(fileURLWithPath: docPro)
            }
        }
        
        // 2. AirPods 3, 4, 5 (modelo estándar)
        if let bundleURL = Bundle.main.url(forResource: "airpods_3_4_5", withExtension: "gif") {
            return bundleURL
        }
        let localPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Assets/airpods_3_4_5.gif")
        if FileManager.default.fileExists(atPath: localPath.path) {
            return localPath
        }
        let userDocPath = "/Users/luisangelceroncastro/Documents/animaciones (creo que terminadas)/airpods 3-4-5gif.gif"
        if FileManager.default.fileExists(atPath: userDocPath) {
            return URL(fileURLWithPath: userDocPath)
        }
        
        return nil
    }
    
    @ObservedObject private var appState = AppState.shared

    /// Modelo del aviso (el que pidió el banco de pruebas o los AirPods conectados)
    private var assetIdentity: AirPodsAssetService.Identity? {
        AirPodsAssetService.identity(for: activity.airpodsState)
    }

    /// Los auriculares en el bucle "cargado" (giran a la izquierda del cuadro; el estuche, a la derecha)
    private static let earbudsCrop = CGRect(x: 0.08, y: 0.31, width: 0.38, height: 0.38)

    /// La animación oficial para el ala, según el ajuste "Animación en las alas"
    private var officialWingVideo: AnyView? {
        let isMax = assetIdentity?.product.hasPrefix("AirPodsMax") == true
        switch appState.airPodsAnimationStyle {
        case .earbuds:
            // Los AirPods girando en primer plano, sin estuche (los Max no tienen estuche: ellos solos girando)
            if isMax, let loop = AirPodsAssetService.shared.clipURL(.maxLoop, for: assetIdentity) {
                return AnyView(ProxCardVideoView(url: loop, rate: 1, zoom: 1.1, loops: true).id(loop.path))
            }
            // (Los AirPods de 1.ª generación lo traen como "ProxCard_loop")
            if !isMax, let loop = AirPodsAssetService.shared.clipURL(.charged, for: assetIdentity)
                ?? AirPodsAssetService.shared.clipURL(.maxLoop, for: assetIdentity) {
                return AnyView(ProxCardVideoView(url: loop, rate: 1, loops: true, crop: Self.earbudsCrop).id(loop.path))
            }
        case .minimal, .full:
            break
        }
        guard let clip = officialClipURL else { return nil }
        // Estuche: quieto (se abre y se queda) o girando. Los Max son más anchos: menos acercamiento
        let still = appState.airPodsAnimationStyle != .full
        return AnyView(ProxCardVideoView(url: clip, rate: still ? 1 : 1.4, zoom: isMax ? 1.1 : 1.5,
                                         startAt: still && isMax ? 2.9 : 0,
                                         holdAt: still ? (isMax ? 4.0 : 1.25) : nil)
            .id("\(clip.path)|\(still)"))
    }

    /// Video oficial del modelo conectado (si ya se bajó; si no, empieza a bajarlo para la próxima vez)
    private var officialClipURL: URL? {
        AirPodsAssetService.shared.clipURL(.connectEngage, for: assetIdentity)
    }

    private var batteryColor: Color {
        if batteryLevel >= 30 {
            return appleBatteryGreen
        } else {
            return Color(red: 1.0, green: 0.27, blue: 0.23) // Apple Red (#FF453A)
        }
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Ala Izquierda (Leading): Animación de los AirPods girando en bucle ampliada a tamaño óptimo (30x26)
            ZStack {
                if let wing = officialWingVideo {
                    // Un poco más chicos que el alto de la isla, como el ícono del iPhone
                    wing.frame(width: 31, height: 29)
                } else if let url = animationURL {
                    AnimatedGIFView(gifURL: url, size: CGSize(width: 30, height: 26))
                        .frame(width: 30, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 4.0, style: .continuous))
                } else {
                    Image(systemName: BluetoothAudioService.shared.currentAirPodsSymbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: wingWidth, height: screenService.currentGeometry.height)
            .contentShape(Rectangle())
            
            // Espacio central (coincide con el sensor de la cámara del notch físico)
            Color.clear
                .frame(
                    width: screenService.currentGeometry.width,
                    height: screenService.currentGeometry.height
                )
            
            // Ala Derecha (Trailing): Círculo de batería en verde (>30%) o rojo (<=29%), limpio sin números ni rayo
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 2.2)
                    .frame(width: 15, height: 15)
                
                Circle()
                    .trim(from: 0, to: (CGFloat(batteryLevel) / 100.0) * batteryRingProgress)
                    .stroke(
                        batteryColor,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 15, height: 15)
            }
            .frame(width: wingWidth, height: screenService.currentGeometry.height)
            .contentShape(Rectangle())
        }
        .frame(
            width: screenService.currentGeometry.width + (wingWidth * 2),
            height: screenService.currentGeometry.height
        )
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.78).delay(0.12)) {
                batteryRingProgress = 1.0
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

