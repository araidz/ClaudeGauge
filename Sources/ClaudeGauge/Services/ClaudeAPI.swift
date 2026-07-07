import Foundation

/// Fetches session + weekly limits from Claude.ai's private usage API using the
/// browser `sessionKey` cookie. Endpoints and shapes mirror the claudemeter client.
enum ClaudeAPI {
    enum APIError: Error, Equatable { case sessionExpired, noOrg, http(Int), badResponse }

    private static let base = "https://claude.ai"

    // Mimic a browser so Cloudflare doesn't reject the request.
    private static let headers: [String: String] = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://claude.ai/settings/usage",
        "Origin": "https://claude.ai",
    ]

    static func fetchUsage(sessionKey: String) async throws -> LimitUsage {
        let orgId = try await resolveOrgId(sessionKey: sessionKey)
        let usage: UsageResponse = try await get("\(base)/api/organizations/\(orgId)/usage", sessionKey: sessionKey)
        return usage.toLimitUsage()
    }

    private static func resolveOrgId(sessionKey: String) async throws -> String {
        let boot: Bootstrap = try await get("\(base)/api/bootstrap", sessionKey: sessionKey)
        guard let memberships = boot.account?.memberships, !memberships.isEmpty else { throw APIError.noOrg }
        // ponytail: personal accounts have one org; prefer a claude.ai-capable membership, else first.
        let pick = memberships.first(where: hasClaudeAiCapability) ?? memberships[0]
        guard let uuid = pick.organization?.uuid else { throw APIError.noOrg }
        return uuid
    }

    private static func hasClaudeAiCapability(_ m: Bootstrap.Membership) -> Bool {
        guard let caps = m.organization?.capabilities else { return true }
        return caps.contains { $0 == "chat" || $0.hasPrefix("claude_") }
    }

    private static func get<T: Decodable>(_ urlString: String, sessionKey: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw APIError.badResponse }
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.contains("permission_error") || text.contains("account_session_invalid") || text.contains("\"type\":\"error\"") {
                throw APIError.sessionExpired
            }
            throw APIError.http(http.statusCode)
        }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // ISO8601 with or without fractional seconds.
    fileprivate static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - Response models

struct UsageResponse: Decodable {
    struct Limit: Decodable { let utilization: Double?; let resets_at: String? }
    let five_hour: Limit?
    let seven_day: Limit?
    let seven_day_opus: Limit?

    func toLimitUsage() -> LimitUsage {
        LimitUsage(
            sessionPercent: five_hour?.utilization ?? 0,
            sessionResetsAt: ClaudeAPI.parseDate(five_hour?.resets_at),
            weeklyPercent: seven_day?.utilization ?? 0,
            weeklyResetsAt: ClaudeAPI.parseDate(seven_day?.resets_at),
            opusWeeklyPercent: seven_day_opus?.utilization,
            opusWeeklyResetsAt: ClaudeAPI.parseDate(seven_day_opus?.resets_at)
        )
    }
}

struct Bootstrap: Decodable {
    struct Org: Decodable { let uuid: String?; let capabilities: [String]? }
    struct Membership: Decodable { let organization: Org? }
    struct Account: Decodable { let memberships: [Membership]? }
    let account: Account?
}
