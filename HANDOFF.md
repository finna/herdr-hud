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


## Windows alpha — September 14, 2026

The same repository now includes `Windows/` and `Windows.Tests/`. The canonical
Git checkout remains on the Mac; Windows has a source copy under
`~/Projects/herdr-hud-desktop`. Do not treat the Windows copy as a second repo.
The source has no GitHub remote and has not been published.

Windows uses .NET 10 WinForms and WebView2, sharing the exact Mac HTML/CSS/JS files.
Its host provides a draggable H, resizable panel, tray menu, visibility toggles,
Ctrl+Alt+H / Ctrl+Alt+Shift+H (alternative Ctrl+Win), optional startup, silent alerts,
DPI-aware initial sizing, a narrow WebView bridge, and user-only named-pipe controls.
Foreground changes reassert topmost positioning without activating the HUD.
The app runs as the normal desktop user, not an elevated task or service.

The user's PC has no local Herdr install. Its private connection preferences point
to the existing Mac setup; saved remote profiles are executed from that source
host so its aliases and credentials continue to work. The Windows key was created
on Windows and its public key authorized on the Mac. No private key was copied.
A Mac host key obtained through the existing trusted connection was pinned on
Windows. Source credentials and addresses are absent from repository files.

Installed Windows app: `%LOCALAPPDATA%/Programs/Herdr HUD/HerdrHUD.exe`.
Start menu shortcut: Herdr HUD. Preferences, diagnostics, UI checks and screenshots
are under `%LOCALAPPDATA%/Herdr HUD`. Screenshots contain private output and can
include other desktop windows; never publish them. The development SDK was
installed per-user under `%LOCALAPPDATA%/Herdr HUD BuildTools/dotnet`.
The temporary interactive launch task is removed after launch; no background
service or login startup was enabled.

Verification: 12 Windows transport tests, 12 shared JavaScript tests, 13 Swift
transport tests. Both native packages build; Mac ad-hoc signature verifies. The
Windows build script restores its dependency lock and creates a self-contained
x64 package. GitHub checks are authored but have not run on GitHub.

Live Windows WebView checks read 13 source-host and 7 saved-remote agents, preserve
drafts, switch Chat/Terminal, filter the roster, render terminal text safely, and
fit the panel. Visibility controls pass. The 4K desktop uses 150 percent scaling;
the initial panel is now 1410 by 975 physical pixels (940 by 650 design units).
The fullscreen test fixture checks z-order, overlap, synthetic clicks confined to
its own windows, panel focus, return to the fixture, and nonactivating overlays.
It restores the prior app and cursor. This is a borderless test window; actual
fullscreen games and exclusive fullscreen remain untested.

Enter/newline and IME behavior is covered by shared handler tests with controlled
bridges. Prompt transports are tested with fakes; no test prompts went into user
agents. Physical keyboard entry in games, alerts, multi-monitor hot-plug/drag,
login startup, Windows local-Herdr mode, Windows 10/ARM64, public signing/installer
polish and actual games are still release checks. Never claim universal fullscreen
support from the fixture. Keep any user draft before relaunching the installed app.

## Compact reading layout

Removed the footer and its redundant status update, removed the header tagline,
and reduced brand, header, machine-strip and conversation-header spacing. Shared
UI is installed on both Mac and Windows. All 12 JavaScript tests and both live
WebView read/draft/layout checks pass. No native transport changes were made.

## Windows badge and notification placement

The bubble region now unions the circular button with its visible badge, using
winding fill to avoid clipping or holes. Badge geometry and text scale with the
button. Notifications use manual initial positioning and appear above the current
H, below it near the top edge, clamped to that monitor's work area. Visible toasts
follow H when dragged and are raised without activation on foreground changes.
Notification size/padding now respect display DPI.

Verified the installed bubble's native window region with a controlled badge at
64, 96 and 128 pixel sizes; the full badge interior fits at all three scales and
clearing it restores the circular button. The installed `--preview-alert` check
showed the toast 15 physical pixels above H at 150 percent DPI on the same screen,
fully on-screen, with foreground focus unchanged. An actual screenshot over WoW
Classic confirmed the placement. Test tools and screenshots are private support
files, not committed source. The user has also sent messages through the game HUD;
WoW and the panel were observed focused separately while both remained visible.
This does not establish exclusive-fullscreen or other-game compatibility.
