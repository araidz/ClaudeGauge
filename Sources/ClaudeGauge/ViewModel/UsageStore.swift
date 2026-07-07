import Foundation
import Combine

/// Holds current usage state and refreshes it on a timer.
/// Phase 2: local context tokens only. Remote session/weekly limits land later.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var token: TokenUsage?

    private var timer: Timer?
    private let interval: TimeInterval

    init(interval: TimeInterval = 10) {
        self.interval = interval
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        // Parse off the main thread; file IO shouldn't hitch the menu.
        Task.detached(priority: .utility) {
            let t = LocalUsage.current()
            await MainActor.run { self.token = t }
        }
    }
}
