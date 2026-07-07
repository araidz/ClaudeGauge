import SwiftUI

@main
struct ClaudeGaugeApp: App {
    init() {
        // Menu bar agent: no Dock icon, no app-switcher entry. Replaces LSUIElement.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
        } label: {
            // ponytail: static placeholder. Real Se/Wk/Tk gauges arrive in later phases.
            Text("Claude …")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ClaudeGauge").font(.headline)
            Text("Scaffold running. Usage meters arrive in later phases.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit ClaudeGauge") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
