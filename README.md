# ClaudeGauge

A macOS menu bar app that shows your Claude usage limits at a glance:
**session (5h) limit, weekly limit, and local context/token usage** — with
reset countdowns. Inspired by the Claudemeter VS Code extension, rebuilt as a
native Swift menu bar app.

> Status: **shipped v0.1.0** — all phases complete. Install via Homebrew below.

---

## Install

```sh
brew install --cask araidz/tap/claudegauge
```

Lives in the menu bar (no Dock icon). Open the menu → **Log in…** to authorize
with your Claude account (a WebKit window opens to claude.ai); the `sessionKey`
cookie is stored in your Keychain. Session + weekly limits refresh every 5 min.

Build from source instead: `swift build -c release && Scripts/bundle.sh`.
Dev self-check (run against the SwiftPM binary, not the bundled app):
`swift run ClaudeGauge --selftest`.

---


## Goal

The menu bar shows **only the session (5h) meter** — a compact five-dot gauge,
nothing else:

```
●●○○○
```

Clicking it opens the detail popover with everything:

- **Session (5h)** — utilization % + time to reset
- **Weekly** — utilization % + time to reset (plus Opus-weekly when present)
- account state, last-refresh, and log in / log out.

---

## Data sources (the crux)

The **session + weekly limits** need an authenticated call to Claude.ai's
private API.

### Session + weekly limits — remote, needs auth

- Undocumented **Claude.ai usage API** (same endpoints Claudemeter uses).
- Auth is a browser **`sessionKey` cookie** for `.claude.ai`, captured via a
  one-time login. The Claude Code CLI's OAuth token does **not** work — wrong
  scopes (`user:inference`, `user:profile`) don't cover usage/billing.
- Exact endpoint paths are undocumented and change without notice. **Reference
  the open-source Claudemeter repo** (`github.com/hyperi-io/claudemeter`) for
  the current paths, cookie handling, and the `/api/bootstrap` capabilities
  call, rather than guessing. Keep every remote call isolated in one file so a
  breakage is a one-file fix.

### Account info

- `~/.claude.json` — plan / account metadata.
- **macOS Keychain** holds the CLI credentials (service `Claude Code-credentials`)
  — note: NOT the `.credentials.json` file the Claudemeter README assumes. Only
  matters if we cross-check that the logged-in browser account matches the CLI
  account (optional for v1).

---

## Auth approach

Recommended: **embedded `WKWebView` login** (native WebKit) instead of shipping
a browser driver.

1. Open a `WKWebView` window pointed at the Claude.ai login.
2. User logs in (Google / email / Cloudflare check) inside it.
3. Read the `sessionKey` cookie from `WKWebsiteDataStore.httpCookieStore`.
4. Persist it in the **macOS Keychain**; close the window.
5. All later fetches use `URLSession` with that cookie — no browser.

Claudemeter uses Playwright because a VS Code extension can't embed WebKit
cleanly; a native Mac app can, so we skip that dependency entirely.

**On expiry / 401:** clear the stored cookie, surface a "Re-login" action in the
menu, re-open the `WKWebView`.

---

## Architecture

- **SwiftUI `MenuBarExtra`** (macOS 13+), `.menuBarExtraStyle(.window)` for a
  rich popover.
- **`LSUIElement = true`** — menu bar agent, no Dock icon.
- **No third-party dependencies** — SwiftUI, WebKit, Security (Keychain), and
  Foundation `URLSession` cover everything.
- Refresh: a `Timer` re-fetches the remote limits every ~5 min.

```
MenuBarExtra (label + popover)
        │
   UsageStore (ObservableObject)  ← timers, holds current state
    ├── ClaudeAPI     → session + weekly limits (URLSession + cookie)
    └── Auth/Keychain → WKWebView login + sessionKey storage
```

---

## Project structure

```
ClaudeGauge/
├── README.md                     # this plan
├── .gitignore
├── Package.swift                 # SwiftPM manifest (macOS 13+)
└── Sources/
    └── ClaudeGauge/
        ├── ClaudeGaugeApp.swift  # @main, session-meter label + popover + login   [done]
        ├── SelfTest.swift            # offline --selftest assertions                  [done]
        ├── Models/
        │   └── Usage.swift           # LimitUsage, Countdown                        [done]
        ├── Services/
        │   ├── ClaudeAPI.swift       # bootstrap + /usage fetch (session/weekly)    [done]
        │   ├── Auth.swift            # WKWebView login -> sessionKey                [done]
        │   └── Keychain.swift        # generic-password Security wrapper            [done]
        └── ViewModel/
            └── UsageStore.swift      # state + remote(5m) refresh timer             [done]
```

Built with **SwiftPM** (`swift build` / `swift run`); Xcode opens `Package.swift`
directly. No `.xcodeproj`, `Info.plist`, or entitlements file — a non-sandboxed
personal tool gets Keychain + network access without them, and the Dock icon is
hidden via `NSApplication.setActivationPolicy(.accessory)` instead of
`LSUIElement`. (Revisit only if we ever ship a signed, sandboxed `.app`.)

---

## Build phases

Ship the safe local part first, then layer on auth and remote limits.

1. **Scaffold** ✅ *done* — `MenuBarExtra` app showing static text, running as a
   menu bar agent via `.accessory` policy (no Dock icon). Confirms the shell works.
2. **Local token meter** — *removed.* Shipped in an early version (JSONL parse +
   `Tk` gauge), later dropped as unwanted; local-token code deleted entirely.
3. **Auth** ✅ *done* — `WKWebView` login window (`Auth.swift`) captures the
   `sessionKey` cookie once off the login page, persisted via `Keychain.swift`.
4. **Remote limits** ✅ *done* — `ClaudeAPI.swift` resolves orgId via `/api/bootstrap`,
   fetches `/usage`; `Se`/`Wk` gauges + reset countdowns render. 401/expired → re-login.
5. **Polish** ✅ *done* — remote(5m) refresh timer, green/yellow/red
   threshold colors in the popover, per-limit detail, login/logout, expired-cookie UX.
   Verify parsing/formatting offline with `swift run ClaudeGauge --selftest`.

---

## Risks / open questions

- **Undocumented API drift** — endpoints can change silently. Isolate in
  `ClaudeAPI.swift`; cross-check against the Claudemeter source when it breaks.
- **Cookie expiry** — needs a clean re-login path (covered above).
- **Endpoint paths** — not hard-coded here on purpose; pull the current ones
  from the Claudemeter repo before writing `ClaudeAPI.swift`.
- **Account matching** — cross-checking browser vs CLI account is optional for
  v1; skip it and just use whoever logs in.
- **Terms** — this is unofficial and hits a private API, same footing as
  Claudemeter. Personal-use tool.
