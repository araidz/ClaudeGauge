import Foundation
import ServiceManagement

/// Launch-at-login, backed by macOS ServiceManagement (macOS 13+).
/// Registers the running app bundle as a login item. No-op in `swift run`
/// (no bundle) — register() throws and is logged.
enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("ClaudeGauge: launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}
