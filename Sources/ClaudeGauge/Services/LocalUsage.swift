import Foundation

/// Reads context usage from Claude Code's local JSONL session logs.
/// The active session = the most recently modified top-level session file
/// (subagent files excluded) within `maxAge`. Context tokens come from that
/// file's last assistant turn.
enum LocalUsage {
    static let maxAge: TimeInterval = 30 * 60   // dead session deck; matches Claude Code idle drop

    private static var projectsDir: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/projects")
    }

    static func current(now: Date = Date(), maxAge: TimeInterval = LocalUsage.maxAge) -> TokenUsage? {
        guard let file = activeSessionFile(now: now, maxAge: maxAge),
              let turn = lastAssistantTurn(in: file.url),
              let usage = turn.message?.usage
        else { return nil }

        let tokens = (usage.input_tokens ?? 0)
            + (usage.cache_creation_input_tokens ?? 0)
            + (usage.cache_read_input_tokens ?? 0)
            + (usage.output_tokens ?? 0)

        let model = turn.message?.model ?? "unknown"
        let name = turn.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? file.url.deletingPathExtension().lastPathComponent

        return TokenUsage(
            tokens: tokens,
            window: contextWindow(model: model),
            model: model,
            sessionName: name,
            updated: file.modified
        )
    }

    // ponytail: Pro plan default (200K). Upgrade path: plan + model rule table
    // (Max/Team/Enterprise on Opus 4.6+ default to 1M) when we add remote plan detection.
    private static func contextWindow(model: String) -> Int {
        model.contains("[1m]") ? 1_000_000 : 200_000
    }

    private static func activeSessionFile(now: Date, maxAge: TimeInterval) -> (url: URL, modified: Date)? {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (url: URL, modified: Date)?
        for case let url as URL in walker {
            guard url.pathExtension == "jsonl" else { continue }
            guard !url.path.contains("/subagents/") else { continue }   // orchestrator, not sub-tasks
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if newest == nil || mod > newest!.modified { newest = (url, mod) }
        }
        guard let hit = newest, now.timeIntervalSince(hit.modified) <= maxAge else { return nil }
        return hit
    }

    // ponytail: whole-file read + full scan. Fine for typical session files;
    // switch to a bounded tail read if logs ever grow into the tens of MB.
    private static func lastAssistantTurn(in url: URL) -> AssistantTurn? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let decoder = JSONDecoder()
        var last: AssistantTurn?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let turn = try? decoder.decode(AssistantTurn.self, from: data),
                  turn.type == "assistant", turn.message?.usage != nil
            else { continue }
            last = turn
        }
        return last
    }
}

/// Minimal decodable view of an assistant JSONL line — only the fields we use.
/// Non-assistant lines simply fail the `usage != nil` guard and are skipped.
private struct AssistantTurn: Decodable {
    let type: String?
    let cwd: String?
    let message: Message?

    struct Message: Decodable {
        let model: String?
        let usage: Usage?
    }
    struct Usage: Decodable {
        let input_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
        let output_tokens: Int?
    }
}
