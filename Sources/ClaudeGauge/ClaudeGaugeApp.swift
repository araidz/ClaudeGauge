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

    // Menu bar shows only the session (5h) meter; everything else lives in the popover.
    private var labelText: String {
        switch store.remote {
        case .ok:         return store.limits.map { Gauge.dots($0.sessionPercent / 100) } ?? "…"
        case .loading:    return "…"
        case .needsLogin: return "log in"
        case .error:      return "!"
        }
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
            HStack {
                Text("ClaudeGauge").font(.headline)
                Spacer()
                if store.isFetching { SpinningArrows() }   // fetching in progress
            }

            // Remote limits — keep the last values on screen during a refresh.
            if let l = store.limits {
                GaugeRow(title: "Session (5h)", percent: l.sessionPercent, resetsAt: l.sessionResetsAt)
                GaugeRow(title: "Weekly", percent: l.weeklyPercent, resetsAt: l.weeklyResetsAt)
                if let opus = l.opusWeeklyPercent {
                    GaugeRow(title: "Weekly (Opus)", percent: opus, resetsAt: l.opusWeeklyResetsAt)
                }
            } else {
                switch store.remote {
                case .needsLogin: Text("Not logged in").font(.caption).foregroundStyle(.secondary)
                case .error(let msg): Text("Error: \(msg)").font(.caption).foregroundStyle(.red)
                default: Text("Loading limits…").font(.caption).foregroundStyle(.secondary)
                }
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

            HStack(spacing: 18) {
                IconButton(symbol: "arrow.clockwise", help: "Refresh") {
                    store.refreshLocal(); store.refreshRemote()
                }
                .disabled(store.isFetching)

                if case .needsLogin = store.remote {
                    IconButton(symbol: "person.crop.circle.badge.plus", help: "Log in") { store.logIn() }
                } else {
                    IconButton(symbol: "rectangle.portrait.and.arrow.right", help: "Log out") { store.logOut() }
                }

                Spacer()
                IconButton(symbol: "power", help: "Quit ClaudeGauge") { NSApplication.shared.terminate(nil) }
            }
            .font(.system(size: 15))
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

/// Refresh-style arrows that spin while a fetch is in flight.
struct SpinningArrows: View {
    @State private var spinning = false
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

/// Icon-only button with a hover tooltip.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
