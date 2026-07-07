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
cookie is stored in your Keychain. Session + weekly limits then refresh every
5 min; local context tokens every 10 s.

Build from source instead: `swift build -c release && Scripts/bundle.sh`.
Dev self-checks (run against the SwiftPM binary, not the bundled app):
`swift run ClaudeGauge --selftest` and `swift run ClaudeGauge --dump --all`.

---


## Goal

One menu bar item, refreshed on a timer, rendering something like:

```
Se ●●○○○ 1h 28m   Wk ●●○○○ 4d 17h   Tk ●○○○○ 12%
```

- `Se` — 5-hour session limit + time to reset
- `Wk` — weekly limit + time to reset
- `Tk` — current context/token usage of the active Claude Code session

Click opens a detail popover (per-limit percentages, reset times, account,
last-refresh, re-login button).

---

## Data sources (the crux)

Two independent sources. The **session + weekly limits are the hard part** —
they need an authenticated call to Claude.ai's private API.

### 1. Session + weekly limits — remote, needs auth

- Undocumented **Claude.ai usage API** (same endpoints Claudemeter uses).
- Auth is a browser **`sessionKey` cookie** for `.claude.ai`, captured via a
  one-time login. The Claude Code CLI's OAuth token does **not** work — wrong
  scopes (`user:inference`, `user:profile`) don't cover usage/billing.
- Exact endpoint paths are undocumented and change without notice. **Reference
  the open-source Claudemeter repo** (`github.com/hyperi-io/claudemeter`) for
  the current paths, cookie handling, and the `/api/bootstrap` capabilities
  call, rather than guessing. Keep every remote call isolated in one file so a
  breakage is a one-file fix.

### 2. Context / token usage — local, no auth

- Parse `~/.claude/projects/**/*.jsonl` session logs. Each assistant turn has a
  `usage` block (`input_tokens`, `output_tokens`, `cache_*`) plus `model`.
- The active session = the most-recently-written `.jsonl` within a live window
  (Claudemeter uses ~10 min live / ~30 min hard deck). Sum tokens, compare to
  the context window (200K / 1M by model+plan) for the `Tk` gauge.
- Fully offline, no login. Ship this first — it's the safe 80%.

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
- **No third-party dependencies** — SwiftUI, WebKit, Security (Keychain),
  Foundation `URLSession`, and `FileManager` cover everything.
- Refresh: a `Timer` for the remote limits (default ~5 min); a lightweight
  file-watch or short timer for local tokens (~10 s).

```
MenuBarExtra (label + popover)
        │
   UsageStore (ObservableObject)  ← timers, holds current state
    ├── ClaudeAPI     → session + weekly limits (URLSession + cookie)
    ├── LocalUsage    → context tokens (JSONL parser)
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
        ├── ClaudeGaugeApp.swift  # @main, Se/Wk/Tk label + colored popover + login   [done]
        ├── SelfTest.swift            # offline --selftest assertions                  [done]
        ├── Models/
        │   └── Usage.swift           # TokenUsage, LimitUsage, Countdown             [done]
        ├── Services/
        │   ├── LocalUsage.swift      # JSONL parser for context tokens              [done]
        │   ├── ClaudeAPI.swift       # bootstrap + /usage fetch (session/weekly)    [done]
        │   ├── Auth.swift            # WKWebView login -> sessionKey                [done]
        │   └── Keychain.swift        # generic-password Security wrapper            [done]
        └── ViewModel/
            └── UsageStore.swift      # state + local(10s)/remote(5m) timers         [done]
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
2. **Local token meter** ✅ *done* — `LocalUsage.swift` parses JSONL for the active
   session's context tokens, `Tk` gauge + detail popover render. No auth, no network.
   Verify with `swift run ClaudeGauge --dump` (add `--all` to ignore the 30m live gate).
3. **Auth** ✅ *done* — `WKWebView` login window (`Auth.swift`) captures the
   `sessionKey` cookie once off the login page, persisted via `Keychain.swift`.
4. **Remote limits** ✅ *done* — `ClaudeAPI.swift` resolves orgId via `/api/bootstrap`,
   fetches `/usage`; `Se`/`Wk` gauges + reset countdowns render. 401/expired → re-login.
5. **Polish** ✅ *done* — local(10s)/remote(5m) refresh timers, green/yellow/red
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
