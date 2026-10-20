import AppKit
import AVFoundation
import SwiftUI

/// Video oficial de los AirPods (HEVC con transparencia) dentro de la isla: el estuche que se abre y los
/// auriculares, igual que la tarjeta del iPhone. El objeto ocupa el centro del cuadro; `zoom` lo acerca para que
/// llene el ala. Se reproduce una vez (o en bucle) sin sonido y suelta el reproductor al desaparecer.
struct ProxCardVideoView: NSViewRepresentable {
    let url: URL
    var rate: Float = 1.5
    var zoom: CGFloat = 1.45
    var loops = false
    /// Desde dónde empieza y en qué segundo se queda quieto (modo mínimo)
    var startAt: Double = 0
    var holdAt: Double? = nil

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(url: url, rate: rate, zoom: zoom, loops: loops, startAt: startAt, holdAt: holdAt)
        return view
    }

    func updateNSView(_ view: PlayerContainerView, context: Context) {}

    static func dismantleNSView(_ view: PlayerContainerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerContainerView: NSView {
        private let playerLayer = AVPlayerLayer()
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var boundaryObserver: Any?
        private var zoom: CGFloat = 1

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = .clear
            playerLayer.backgroundColor = .clear
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { nil }

        func configure(url: URL, rate: Float, zoom: CGFloat, loops: Bool, startAt: Double, holdAt: Double?) {
            self.zoom = zoom
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            if loops { looper = AVPlayerLooper(player: player, templateItem: item) } else { player.insert(item, after: nil) }
            playerLayer.player = player
            self.player = player
            if let holdAt {
                // Se queda quieto en ese cuadro (sin seguir decodificando video)
                boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: holdAt, preferredTimescale: 600))],
                                                                  queue: .main) { [weak player] in player?.pause() }
            }
            if startAt > 0 {
                player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak player] _ in
                    player?.playImmediately(atRate: rate)
                }
            } else {
                player.playImmediately(atRate: rate)
            }
        }

        func stop() {
            if let boundaryObserver { player?.removeTimeObserver(boundaryObserver) }
            boundaryObserver = nil
            player?.pause()
            looper = nil
            playerLayer.player = nil
            player = nil
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Acercar: el objeto está en el centro del cuadro del video
            let size = CGSize(width: bounds.width * zoom, height: bounds.height * zoom)
            playerLayer.frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                                       width: size.width, height: size.height)
            CATransaction.commit()
        }
    }
}
