import Foundation
import ServiceManagement

/// Thin wrapper over SMAppService for launch-at-login (macOS 13+).
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[LucidWallpaper] LaunchAtLogin toggle failed: \(error.localizedDescription)")
        }
    }
}
