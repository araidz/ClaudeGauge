import Foundation
import WebKit
import AppKit

/// The claude.ai browser session cookie, persisted in Keychain.
struct Session: Codable {
    var sessionKey: String
    var expires: Date?
    var isExpired: Bool { expires.map { $0 <= Date() } ?? false }
}

enum Auth {
    private static let account = "claude-session"

    static func load() -> Session? {
        guard let json = Keychain.get(account),
              let s = try? JSONDecoder().decode(Session.self, from: Data(json.utf8))
        else { return nil }
        return s
    }

    static func save(_ s: Session) {
        guard let data = try? JSONEncoder().encode(s),
              let json = String(data: data, encoding: .utf8) else { return }
        Keychain.set(json, for: account)
    }

    static func clear() { Keychain.delete(account) }
}

/// Presents a WKWebView window to claude.ai and captures the `sessionKey` cookie
/// once the user has logged in. Native WebKit — no browser driver dependency.
@MainActor
final class LoginController: NSObject, WKHTTPCookieStoreObserver, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var onDone: ((Session?) -> Void)?
    private var captured = false
    private var closeRelay: WindowCloseRelay?

    func present(onDone: @escaping (Session?) -> Void) {
        self.onDone = onDone
        self.captured = false

        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: config)
        web.navigationDelegate = self
        config.websiteDataStore.httpCookieStore.add(self)
        web.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        self.webView = web

        let win = NSWindow(contentRect: web.frame,
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "Log in to Claude"
        win.contentView = web
        win.center()
        win.isReleasedWhenClosed = false
        let relay = WindowCloseRelay { [weak self] in self?.finish(nil) }
        closeRelay = relay
        win.delegate = relay
        NSApp.setActivationPolicy(.regular)          // let the login window take focus
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        self.window = win
    }

    // Fires whenever cookies change; capture sessionKey once the user is off the login page.
    // ponytail: heuristic (present + non-empty + not on /login). A bad cookie just 401s on
    // fetch and re-prompts login — self-correcting. Tighten by validating via /api/bootstrap.
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self,
                  let c = cookies.first(where: {
                      $0.name == "sessionKey" && $0.domain.contains("claude.ai") && !$0.value.isEmpty
                  }) else { return }
            self.tryCapture(Session(sessionKey: c.value, expires: c.expiresDate))
        }
    }

    private func tryCapture(_ session: Session) {
        guard !captured else { return }
        if let path = webView?.url?.path, path.contains("login") { return }  // still authenticating
        captured = true
        Auth.save(session)
        finish(session)
    }

    private func finish(_ session: Session?) {
        webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        webView = nil
        closeRelay = nil
        NSApp.setActivationPolicy(.accessory)        // back to menu bar agent
        onDone?(session)
        onDone = nil
    }
}

/// Bridges NSWindow close to a callback without subclassing the window.
private final class WindowCloseRelay: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
