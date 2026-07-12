import Foundation
import Combine

/// Holds usage state and refreshes the remote session/weekly limits on a timer.
@MainActor
final class UsageStore: ObservableObject {
    enum RemoteState: Equatable {
        case needsLogin
        case loading
        case ok
        case error(String)
    }

    @Published private(set) var limits: LimitUsage?    // remote session + weekly
    @Published private(set) var remote: RemoteState = .needsLogin
    @Published private(set) var isFetching = false   // a remote fetch is in flight

    private let login = LoginController()
    private var remoteTimer: Timer?
    private var activeFetch: Task<Void, Never>?
    private var cachedOrgId: String?
    private var lastActive = Date.distantPast
    private let activeInterval: TimeInterval
    private let idleInterval: TimeInterval
    private static let idleThreshold: TimeInterval = 900  // 15 min without popover open -> idle

    init(activeInterval: TimeInterval = 300, idleInterval: TimeInterval = 900) {
        self.activeInterval = activeInterval
        self.idleInterval = idleInterval

        remote = (Auth.load()?.isExpired == false) ? .loading : .needsLogin
        refreshRemote()
        scheduleTimer()
    }

    /// Called when the popover opens; resets idle timer and refreshes if stale.
    func popoverOpened() {
        lastActive = Date()
        rescheduleTimer()
        if remote != .ok { refreshRemote() }
    }

    private func scheduleTimer() {
        let interval = Date().timeIntervalSince(lastActive) > Self.idleThreshold ? idleInterval : activeInterval
        remoteTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshRemote() }
        }
    }

    private func rescheduleTimer() {
        remoteTimer?.invalidate()
        scheduleTimer()
    }

    func refreshRemote() {
        guard let session = Auth.load(), !session.isExpired else {
            limits = nil
            remote = .needsLogin
            return
        }
        // Cancel any in-flight fetch to prevent races.
        activeFetch?.cancel()
        // Keep the existing limits on screen; only show a placeholder on the very first load.
        if limits == nil { remote = .loading }
        isFetching = true
        activeFetch = Task {
            defer {
                isFetching = false
                activeFetch = nil
            }
            do {
                let result = try await ClaudeAPI.fetchUsage(sessionKey: session.sessionKey, cachedOrgId: cachedOrgId)
                guard !Task.isCancelled else { return }
                cachedOrgId = result.orgId
                limits = result.usage
                remote = .ok
            } catch ClaudeAPI.APIError.sessionExpired {
                guard !Task.isCancelled else { return }
                Auth.clear()
                cachedOrgId = nil
                limits = nil
                remote = .needsLogin
            } catch {
                guard !Task.isCancelled else { return }
                remote = .error(short(error))   // stale limits stay visible
            }
        }
    }

    func logIn() {
        login.present { [weak self] session in
            guard let self else { return }
            if session != nil { self.refreshRemote() }
        }
    }

    func logOut() {
        Auth.clear()
        limits = nil
        remote = .needsLogin
    }

    private func short(_ error: Error) -> String {
        switch error {
        case ClaudeAPI.APIError.noOrg: return "no organization"
        case ClaudeAPI.APIError.http(let code): return "HTTP \(code)"
        case ClaudeAPI.APIError.badResponse: return "bad response"
        default: return (error as NSError).localizedDescription
        }
    }
}
