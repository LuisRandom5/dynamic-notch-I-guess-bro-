# Dynamic Notch — Agent Guidelines & System Architecture

Please refer to [ARCHITECTURE.md](file:///Users/luisangelceroncastro/Documents/Dynamic%20Notch/ARCHITECTURE.md) for the complete technical guide, window hierarchy, engines, event pipelines, and design principles of Dynamic Notch.

## Quick Reference
- **Build**: `./scripts/build_app.sh`
- **Binary**: `DynamicNotch.app/Contents/MacOS/DynamicNotch`
- **Main Views**: `Sources/DynamicNotch/Views/` (`NotchContainerView.swift`, `NotchPlayerView.swift`, `NotchShelfView.swift`, `NotchCompactView.swift`)
- **Core State**: `Sources/DynamicNotch/Core/` (`AppState.swift`, `AnimationSpeedManager.swift`)
- **Window Management**: `Sources/DynamicNotch/Window/` (`NotchPanel.swift`, `NotchWindowManager.swift`)
- **Live Activities**: `Sources/DynamicNotch/Activities/` (`ActivityCenter.swift`, `LiveActivity.swift`, `Templates/QuickReplyNotificationView.swift`)
- **Services**: `Sources/DynamicNotch/Services/` (`MusicService.swift`, `NowPlayingService.swift`, `VolumeInterceptorService.swift`, `WhatsAppWebObserverService.swift`, `ShelfStorageService.swift`)
