# ClaudeGauge

A tiny macOS menu bar app that shows your Claude usage limits at a glance —
**5-hour session** and **weekly** limits with reset countdowns — so you never
get surprised by a limit you didn't see coming.

Unofficial, personal tool. Not affiliated with Anthropic. Inspired by the
[Claudemeter](https://github.com/hyperi-io/claudemeter) VS Code extension,
rebuilt as a native Swift menu bar app with zero third-party dependencies.

---

## What it shows

**Menu bar** — only the session (5h) meter, a compact five-dot gauge:

```
●●○○○
```

**Popover** (click the meter) — the full picture:

- **Session (5h)** — utilization % + time to reset
- **Weekly** — utilization % + time to reset
- **Weekly (Opus)** — shown only on plans that have a separate Opus weekly limit
- Colored bars: green < 75 %, yellow 75–90 %, red ≥ 90 %
- A spinning-arrows indicator while a refresh is in flight (old numbers stay put)
- **Launch at login** toggle
- Icon buttons: Refresh · Log in / Log out · Quit

---

## Install

```sh
brew install --cask araidz/tap/claudegauge
```

It lives in the menu bar (no Dock icon). Open the menu → **Log in…**, sign in
with your normal Claude account in the window that appears, and the gauges
populate. Limits then auto-refresh every 5 minutes.

> Ad-hoc signed, not Apple-notarized. The cask strips the quarantine attribute
> on install so Gatekeeper doesn't block first launch.

---

## How it works

Two steps, both against Claude.ai's private (undocumented) API using your
browser session — **no developer API key, no billing**. A `$20` Pro
subscription is enough.

1. **Login** — a native `WKWebView` window opens claude.ai. After you sign in,
   the `sessionKey` cookie is captured and stored in the macOS **Keychain**.
   The Claude Code CLI's OAuth token can't be reused — its scopes don't cover
   the usage endpoints, so a browser session is required.
2. **Fetch** — `GET /api/bootstrap` resolves your organization id, then
   `GET /api/organizations/{id}/usage` returns `five_hour` / `seven_day` /
   `seven_day_opus` (`utilization` 0–100, ISO-8601 `resets_at`). A `401/403`
   with an expired-session marker clears the cookie and re-prompts login.

Refresh: a 5-minute timer plus the manual Refresh button. During a refresh the
last-fetched values stay on screen; only the very first load shows a placeholder.

---

## Architecture

- **SwiftUI `MenuBarExtra`** (macOS 13+), `.menuBarExtraStyle(.window)`.
- Runs as a menu bar agent (`LSUIElement` in the bundle / `.accessory` policy).
- **Zero third-party dependencies** — SwiftUI, WebKit, Security (Keychain),
  ServiceManagement (launch-at-login), and Foundation `URLSession`.

```
MenuBarExtra (dots label + popover)
        │
   UsageStore (ObservableObject)  ← 5-min timer, holds state
    ├── ClaudeAPI     → session + weekly limits (URLSession + sessionKey cookie)
    └── Auth/Keychain → WKWebView login + cookie storage
   LoginItem          → launch-at-login (SMAppService)
```

### Project structure

```
ClaudeGauge/
├── README.md
├── .gitignore
├── Package.swift                 # SwiftPM manifest (macOS 13+, no deps)
├── Scripts/bundle.sh             # build .app + Info.plist + ad-hoc sign
└── Sources/ClaudeGauge/
    ├── ClaudeGaugeApp.swift      # @main, dots label, popover, Gauge helpers
    ├── SelfTest.swift            # offline --selftest assertions
    ├── Models/
    │   └── Usage.swift           # LimitUsage, Countdown
    ├── Services/
    │   ├── ClaudeAPI.swift       # bootstrap + /usage fetch
    │   ├── Auth.swift            # WKWebView login → sessionKey
    │   ├── Keychain.swift        # generic-password wrapper
    │   └── LoginItem.swift       # launch-at-login (SMAppService)
    └── ViewModel/
        └── UsageStore.swift      # state + 5-min refresh timer
```

---

## Build from source

```sh
swift build -c release      # compile
Scripts/bundle.sh           # produce ClaudeGauge.app (ad-hoc signed)
swift run ClaudeGauge --selftest   # offline decode/format/countdown checks
```

Xcode opens `Package.swift` directly. No `.xcodeproj` needed.

Releasing: `Scripts/bundle.sh <version>` → zip → GitHub release → bump the cask
in `araidz/homebrew-tap` (version + sha256) → `brew upgrade --cask claudegauge`.

---

## Areas for improvement

Deliberately left out to keep it lean. Reach for these only when actually wanted:

- **Threshold notifications** — a `UNUserNotification` when session/weekly cross
  ~80 % and ~95 %, fired once per tier per window (re-armed on reset). Turns it
  from "a thing I check" into "a thing that tells me." *(Considered, skipped for
  now — the dots are enough at a glance.)*
- **Critical glyph in the menu bar** — prepend a `⚠` to the dots when session
  ≥ 90 %, so the danger state reads without opening the popover.
- **Signing + notarization** — a Developer ID cert would remove the ad-hoc
  signature and the cask's quarantine-strip workaround.
- **orgId caching** — cache the resolved org id so each poll makes one request
  instead of two (marginal at a 5-min cadence).
- **Tighter login capture** — validate the captured `sessionKey` against
  `/api/bootstrap` before saving, instead of the "off the login page" heuristic
  (currently self-correcting: a bad cookie just 401s and re-prompts).
- **Configurable thresholds / refresh interval** — a small settings surface;
  currently hardcoded (75/90 colors, 5-min refresh).
- **Account-switch detection** — watch `~/.claude/.credentials.json` /
  `~/.claude.json` and re-prompt login when the CLI account changes.
- **Usage history** — a sparkline of utilization over time (needs local storage).
- **Happy-hour / peak-window indicator** — highlight Anthropic's off-peak window.

## Known limitations

- The usage endpoints are **undocumented and can change without notice**. All
  remote calls are isolated in `ClaudeAPI.swift`, so a break is a one-file fix —
  cross-check against the Claudemeter source when it happens.
- Session cookies expire; you'll re-login occasionally (there's a button).
- Context-window / token defaults assume a Pro plan where relevant.

---

*Personal use. Uses a private API with your own session — no credentials leave
your machine (the cookie lives only in your Keychain).*
