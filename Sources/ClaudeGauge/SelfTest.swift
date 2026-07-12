import Foundation

/// Offline assertions over the parse/format logic. Run via `swift run ClaudeGauge --selftest`.
/// No frameworks — asserts crash on failure, prints "selftest: ok" on success.
enum SelfTest {
    static func run() {
        // 1. Usage response decode + mapping (utilization is 0-100, resets_at ISO8601).
        let usageJSON = """
        {"five_hour":{"utilization":42.5,"resets_at":"2026-07-07T18:30:00.000000Z"},
         "seven_day":{"utilization":88,"resets_at":"2026-07-11T00:00:00Z"},
         "seven_day_opus":{"utilization":12,"resets_at":null}}
        """
        let usage = try! JSONDecoder().decode(UsageResponse.self, from: Data(usageJSON.utf8))
        let limits = usage.toLimitUsage()
        assert(limits.sessionPercent == 42.5, "session percent")
        assert(limits.weeklyPercent == 88, "weekly percent")
        assert(limits.opusWeeklyPercent == 12, "opus percent")
        assert(limits.sessionResetsAt != nil, "session reset parsed (fractional seconds)")
        assert(limits.weeklyResetsAt != nil, "weekly reset parsed (no fractional seconds)")
        assert(limits.opusWeeklyResetsAt == nil, "null reset stays nil")

        // 2. Bootstrap decode → org uuid reachable.
        let bootJSON = """
        {"account":{"memberships":[
          {"organization":{"uuid":"org-abc","name":"Ahmed's Organization","capabilities":["chat","claude_pro"]}}
        ]}}
        """
        let boot = try! JSONDecoder().decode(Bootstrap.self, from: Data(bootJSON.utf8))
        assert(boot.account?.memberships?.first?.organization?.uuid == "org-abc", "org uuid")

        // 3. Countdown formatting.
        let now = Date(timeIntervalSince1970: 1_000_000)
        assert(Countdown.short(to: now.addingTimeInterval(90 * 60), now: now) == "1h 30m", "hours+mins")
        assert(Countdown.short(to: now.addingTimeInterval(2 * 86400 + 3600), now: now) == "2d 1h", "days+hours")
        assert(Countdown.short(to: now.addingTimeInterval(600), now: now) == "10m", "minutes only")
        assert(Countdown.short(to: now.addingTimeInterval(-5), now: now) == "soon", "past -> soon")
        assert(Countdown.short(to: now.addingTimeInterval(30), now: now) == "soon", "30s -> soon")
        assert(Countdown.short(to: now.addingTimeInterval(61), now: now) == "1m", "61s -> 1m")
        assert(Countdown.short(to: nil) == "—", "nil -> dash")

        // 4. Dot gauge + color thresholds.
        assert(Gauge.dots(0.0) == "○○○○○", "empty")
        assert(Gauge.dots(1.0) == "●●●●●", "full")
        assert(Gauge.dots(0.5) == "●●●○○", "half rounds up (2.5 -> 3)")

        print("selftest: ok")
    }
}
