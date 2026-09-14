# Mac preview handoff — September 14, 2026

The source lives directly on the Mac Studio at `~/Projects/herdr-hud-desktop`.
The installed app is `~/Applications/Herdr HUD.app`. This is a native AppKit app
with a bundled reusable WebKit interface and a Swift Herdr/SSH transport.

## Current functionality

Floating draggable H button, agent roster from the local default Herdr session
and enabled saved machines, per-host status, recent output, Codex Chat and plain
Terminal views, expandable tool activity, model metadata, working timer, prompt
composer, per-agent drafts, unread badges, silent hoverable alerts, roster resizing,
saved visibility/position/view preferences, menu-bar controls, two shortcut presets,
and optional macOS login registration. There is no Squad or tablet component.

The first live roster resolved 13 Mac agents and 7 remote agents. Live UI checks
read both hosts and passed draft retention, view switching, search, safe text
rendering, and layout checks. The installed app's diagnostics confirm resources
come from the app bundle rather than the build checkout.

13 Swift tests and 5 JavaScript tests pass. Tests cover machine and session scope,
stale/replaced agent refusal, busy/blocked/unknown refusal, literal arguments,
uncertain sends without retries, large output, machine removal, offline cached
cards, and reconnection. Prompt delivery tests use controlled transports; there
has been no test prompt sent into active user conversations.

## Runtime evidence

Private evidence files, excluded from Git:

- `.evidence/fullscreen-probe.json`: exact fullscreen fixture window ID, on-screen
  ordering, overlap, HUD frames, and foreground app. The probe closes itself.
- `.evidence/visibility.json`: show/hide/open/close checks.
- `~/Library/Application Support/Herdr HUD/ui-verification.json`: live WebKit
  integration checks. No Send click occurs during this verification.
- Same directory: `diagnostics.json`, `ui-check.json`, `panel-preview.png`.
  The panel screenshot contains real private agent output. Do not publish it.

External screen capture and accessibility were denied to the SSH test process.
Own-WebView snapshot rendering worked and was visually inspected. Window ordering
can be queried without screen capture. These checks do not establish physical
mouse/keyboard behavior over an actual game. That remains the next Mac test.

## Resume

Read README.md and AGENTS.md. Check the existing app and diagnostics before
restarting anything. The user can already click the gold H or press Command–Option–H.
Command–Option–Shift–H toggles visibility; the menu-bar H is always available.

Use `scripts/build-app.sh` to build the local preview. To replace it, quit only
this app, copy the built bundle into `~/Applications`, and reopen it. Once the
user starts using the app, preserve their draft or coordinate the reload first.
Herdr servers and agent sessions are independent and must remain running.

Remaining release work: actual game and physical-input validation; monitor
hot-plug/drag and alert interaction checks; login startup test; installer icon,
public signing/notarization, and broader macOS/Intel coverage. The interface is
prepared for reuse, but Windows and new Linux shells have not been implemented.
The user has a Windows gaming PC for later testing and requested Mac-first work.

## Composer shortcut update

Enter sends; Control/Shift/Command/Option–Enter insert a newline at the cursor
and preserve the per-agent draft. IME composition Enter is left to the input
method, and held Enter does not submit repeatedly. The visible hint is updated.
