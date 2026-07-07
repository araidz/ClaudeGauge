import SwiftUI

@main
struct ClaudeGaugeApp: App {
    @StateObject private var store = UsageStore()

    init() {
        // Runnable self-check: `swift run ClaudeGauge --dump` prints the parsed
        // usage and exits, so the JSONL pipeline can be verified without the UI.
        // Add `--all` to ignore the 30m live-session gate (parses the newest log regardless).
        if CommandLine.arguments.contains("--dump") {
            let maxAge = CommandLine.arguments.contains("--all") ? .infinity : LocalUsage.maxAge
            let t = LocalUsage.current(maxAge: maxAge)
            print(t.map { "Tk \($0.tokens)/\($0.window) (\($0.percent)%)  model=\($0.model)  session=\($0.sessionName)" }
                ?? "no live session (nothing modified within \(Int(LocalUsage.maxAge / 60))m)")
            exit(0)
        }
        // Menu bar agent: no Dock icon, no app-switcher entry. Replaces LSUIElement.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            Text(labelText)
        }
        .menuBarExtraStyle(.window)
    }

    private var labelText: String {
        guard let t = store.token else { return "Tk -" }
        return "Tk \(Gauge.dots(t.fraction)) \(t.percent)%"
    }
}

enum Gauge {
    /// Five-segment dot meter: "●●○○○".
    static func dots(_ fraction: Double, segments: Int = 5) -> String {
        let filled = min(segments, max(0, Int((fraction * Double(segments)).rounded())))
        return String(repeating: "●", count: filled) + String(repeating: "○", count: segments - filled)
    }
}

struct MenuContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ClaudeGauge").font(.headline)

            if let t = store.token {
                Text("Context  \(Gauge.dots(t.fraction))  \(t.percent)%")
                Text("\(t.tokens.formatted()) / \(t.window.formatted()) tokens")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(t.sessionName) · \(t.model)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("updated \(t.updated.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("No active Claude Code session")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            Button("Refresh now") { store.refresh() }
            Button("Quit ClaudeGauge") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280)
    }
}
