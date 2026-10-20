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

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(url: url, rate: rate, zoom: zoom, loops: loops)
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

        func configure(url: URL, rate: Float, zoom: CGFloat, loops: Bool) {
            self.zoom = zoom
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            if loops { looper = AVPlayerLooper(player: player, templateItem: item) } else { player.insert(item, after: nil) }
            playerLayer.player = player
            self.player = player
            player.playImmediately(atRate: rate)
        }

        func stop() {
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
