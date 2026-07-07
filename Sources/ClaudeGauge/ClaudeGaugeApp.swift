import SwiftUI

@main
struct ClaudeGaugeApp: App {
    @StateObject private var store = UsageStore()

    init() {
        let args = CommandLine.arguments
        // `--dump [--all]` prints local context usage and exits (verifies the JSONL pipeline).
        if args.contains("--dump") {
            let maxAge = args.contains("--all") ? .infinity : LocalUsage.maxAge
            let t = LocalUsage.current(maxAge: maxAge)
            print(t.map { "Tk \($0.tokens)/\($0.window) (\($0.percent)%)  model=\($0.model)  session=\($0.sessionName)" }
                ?? "no live session (nothing modified within \(Int(LocalUsage.maxAge / 60))m)")
            exit(0)
        }
        // `--selftest` runs offline assertions on parsing/formatting and exits.
        if args.contains("--selftest") { SelfTest.run(); exit(0) }

        NSApplication.shared.setActivationPolicy(.accessory)   // menu bar agent, no Dock icon
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
        var parts: [String] = []
        switch store.remote {
        case .ok:
            if let l = store.limits {
                parts.append("Se \(Gauge.dots(l.sessionPercent / 100)) \(Countdown.short(to: l.sessionResetsAt))")
                parts.append("Wk \(Gauge.dots(l.weeklyPercent / 100)) \(Countdown.short(to: l.weeklyResetsAt))")
            }
        case .needsLogin: parts.append("log in")
        case .loading:    parts.append("…")
        case .error:      parts.append("!")
        }
        if let t = store.token { parts.append("Tk \(Gauge.dots(t.fraction)) \(t.percent)%") }
        return "Claude " + parts.joined(separator: "  ")
    }
}

enum Gauge {
    /// Five-segment dot meter: "●●○○○".
    static func dots(_ fraction: Double, segments: Int = 5) -> String {
        let filled = min(segments, max(0, Int((fraction * Double(segments)).rounded())))
        return String(repeating: "●", count: filled) + String(repeating: "○", count: segments - filled)
    }

    /// Green < 75%, yellow 75-90%, red >= 90%.
    static func color(_ percent: Double) -> Color {
        percent >= 90 ? .red : percent >= 75 ? .yellow : .green
    }
}

struct MenuContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ClaudeGauge").font(.headline)

            // Remote limits
            switch store.remote {
            case .ok:
                if let l = store.limits {
                    GaugeRow(title: "Session (5h)", percent: l.sessionPercent, resetsAt: l.sessionResetsAt)
                    GaugeRow(title: "Weekly", percent: l.weeklyPercent, resetsAt: l.weeklyResetsAt)
                    if let opus = l.opusWeeklyPercent {
                        GaugeRow(title: "Weekly (Opus)", percent: opus, resetsAt: l.opusWeeklyResetsAt)
                    }
                }
            case .needsLogin:
                Text("Not logged in").font(.caption).foregroundStyle(.secondary)
            case .loading:
                Text("Loading limits…").font(.caption).foregroundStyle(.secondary)
            case .error(let msg):
                Text("Error: \(msg)").font(.caption).foregroundStyle(.red)
            }

            Divider()

            // Local context
            if let t = store.token {
                GaugeRow(title: "Context (\(t.model))", percent: t.fraction * 100,
                         detail: "\(t.tokens.formatted()) / \(t.window.formatted()) · \(t.sessionName)")
            } else {
                Text("No active Claude Code session").font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Refresh") { store.refreshLocal(); store.refreshRemote() }
                Spacer()
                if case .needsLogin = store.remote {
                    Button("Log in…") { store.logIn() }
                } else {
                    Button("Log out") { store.logOut() }
                }
            }
            Button("Quit ClaudeGauge") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 300)
    }
}

/// One labeled meter: colored progress bar + percent + reset countdown / detail.
struct GaugeRow: View {
    let title: String
    let percent: Double
    var resetsAt: Date? = nil
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(Int(percent.rounded()))%").font(.subheadline).monospacedDigit()
                    .foregroundStyle(Gauge.color(percent))
            }
            ProgressView(value: min(max(percent / 100, 0), 1))
                .tint(Gauge.color(percent))
            if let resetsAt {
                Text("resets in \(Countdown.short(to: resetsAt))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
