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
