import Foundation

/// Current context-window occupancy of the active Claude Code session,
/// derived entirely from local JSONL logs (no auth, no network).
struct TokenUsage {
    let tokens: Int      // input + cache_creation + cache_read + output of the latest turn
    let window: Int      // context window size (200K Pro, 1M on [1m] models)
    let model: String
    let sessionName: String
    let updated: Date

    var fraction: Double { window > 0 ? min(Double(tokens) / Double(window), 1) : 0 }
    var percent: Int { Int((fraction * 100).rounded()) }
}

/// Remote plan limits from Claude.ai (`utilization` is 0-100).
struct LimitUsage {
    var sessionPercent: Double        // 5-hour session window
    var sessionResetsAt: Date?
    var weeklyPercent: Double         // 7-day window
    var weeklyResetsAt: Date?
    var opusWeeklyPercent: Double?    // Opus-specific weekly (nil on plans without it)
    var opusWeeklyResetsAt: Date?
    var fetched: Date = Date()
}

enum Countdown {
    /// Compact time-to-reset: "4d 17h", "1h 28m", "12m", or "soon".
    static func short(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let secs = date.timeIntervalSince(now)
        if secs <= 0 { return "soon" }
        let mins = Int(secs / 60), hrs = mins / 60, days = hrs / 24
        if days >= 1 { return "\(days)d \(hrs % 24)h" }
        if hrs >= 1 { return "\(hrs)h \(mins % 60)m" }
        return "\(mins)m"
    }
}
