import AppKit
import SwiftUI
import Combine

// Reacciones de AppState a los servicios: carga y batería, volumen, música, pantalla
extension AppState {
    func setupSubscriptions() {
        // Battery MagSafe connection listener -> Publicar actividad de carga dedicada (sin forzar reproductor de música)
        batteryService.onPowerConnected = { percentage in
            ChargingActivityProvider.shared.publishChargingActivity(
                percentage: percentage,
                isLowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                isPluggedIn: true
            )
        }
        
        // Alerta de Batería Baja automática estilo Apple Card / Dynamic Island
        batteryService.onLowBattery = { percentage in
            ChargingActivityProvider.shared.publishLowBatteryActivity(percentage: percentage)
        }

        batteryService.onFullyCharged = {
            ChargingActivityProvider.shared.publishFullyChargedActivity()
        }
        
        // Volume change listener
        audioService.onVolumeChanged = { [weak self] volume, isMuted in
            self?.handleVolumeChanged(volume: volume, isMuted: isMuted)
        }
        
        // Music changes con retención de 30 segundos al pausar
        musicService.$hasActiveMusic
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self = self else { return }
                print("[AppState] hasActiveMusic: \(isPlaying), current mode: \(self.mode)")
                if isPlaying {
                    // Cancela cualquier timer de colapso pendiente
                    self.musicPauseDismissTimer?.invalidate()
                    self.musicPauseDismissTimer = nil
                    self.reconcileCompactMode()
                } else {
                    // Al pausar: retener el minirreproductor durante 30 segundos antes de colapsar
                    self.musicPauseDismissTimer?.invalidate()
                    self.musicPauseDismissTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self = self, !self.musicService.hasActiveMusic else { return }
                            self.musicPauseDismissTimer = nil
                            if self.mode == .compact || self.mode == .idle {
                                self.reconcileCompactMode()
                            } else if self.mode == .expanded && !self.isHovered {
                                self.collapse()
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
}
