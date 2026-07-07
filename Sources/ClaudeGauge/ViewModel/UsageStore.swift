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
    private let remoteInterval: TimeInterval

    init(remoteInterval: TimeInterval = 300) {
        self.remoteInterval = remoteInterval

        remote = (Auth.load()?.isExpired == false) ? .loading : .needsLogin
        refreshRemote()

        remoteTimer = Timer.scheduledTimer(withTimeInterval: remoteInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshRemote() }
        }
    }

    func refreshRemote() {
        guard let session = Auth.load(), !session.isExpired else {
            limits = nil
            remote = .needsLogin
            return
        }
        // Keep the existing limits on screen; only show a placeholder on the very first load.
        if limits == nil { remote = .loading }
        isFetching = true
        Task {
            defer { isFetching = false }
            do {
                limits = try await ClaudeAPI.fetchUsage(sessionKey: session.sessionKey)
                remote = .ok
            } catch ClaudeAPI.APIError.sessionExpired {
                Auth.clear()
                limits = nil
                remote = .needsLogin
            } catch {
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
