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

## macOS notification placement

Notifications now anchor above H, falling below it near the top edge and trying
either side if needed. Placement is clamped to the button's screen without
overlapping H wherever space permits. Visible alerts follow button movement and
display changes. Their native window level is above H and they are raised when
switching Spaces.

All 15 Swift tests pass, including placement at corners, edges and the middle of
two displays with different origins. The rebuilt installed app's ad-hoc signature
verifies. Its own notification preview reported a 10-point gap above H, fully
on-screen, no overlap, higher window order than H, and unchanged foreground focus.
The private ToastView snapshot also rendered correctly. No test prompts were sent
to user agents. The active composer was empty before the HUD-only relaunch.

The macOS --preview-alert command writes private notification-preview.json and
notification-preview.png under the app support directory. It uses a temporary
preview without activating another app. --inspect now reports draftLength.

## Public alpha preparation

The transport now sends prompts through native local sockets/pipes or a static
Python helper over SSH stdin, including nested SSH from a Windows source host.
Remote Mac/Linux hosts require Python 3; no helper files are installed there.
Native output capture is bounded before decoding. Mac uses posix_spawn process
groups; Windows creates processes suspended and assigns a kill-on-close Job Object
before resuming. Timeout/overflow tears down descendants. Local native socket,
remote helper, stdin privacy, overflow and child-cleanup tests cover the change.

Packaging scripts create Mac arm64 and Windows x64 ZIPs. The first public alpha is
v0.1.0-alpha.1, unsigned/ad-hoc signed, with checksums and explicit installation
instructions. No developer signing identity was available on the build Mac.

Release verification: 19 Swift tests, 16 Windows tests, 12 shared JavaScript tests,
and 5 remote-helper tests pass. Both packaged builds were installed locally after
checking for active drafts. Live UI verification passed local/remote reads, draft
retention, view switching, search, safe text rendering and layout on each platform.
The source privacy pattern scan returned no findings. Package signing remains
ad-hoc/unsigned; alpha release notes distinguish tested behavior from unverified
exclusive-fullscreen, Intel Mac, Windows ARM64 and broader game compatibility.


## macOS drag-to-Applications packaging

A user reported Gatekeeper's cannot-check-for-malware warning with the public
ZIP. The app remains ad-hoc signed and unnotarized. The build Mac still has zero
valid code-signing identities. `scripts/package-macos-dmg.sh` creates a verified
compressed disk image with the app, an Applications symlink, and installation
instructions. It derives the filename architecture from the executable, stages
in a temporary directory, and cleans that directory on exit. This only improves
the copy-to-Applications step; it cannot remove the Gatekeeper warning. Do not
present this DMG as a signed release. Developer ID signing, hardened runtime,
notarization, stapling and a fresh downloaded-copy Gatekeeper check remain
necessary before publishing a release that claims a normal verified launch.

## Prepared Developer ID release workflow

The user renewed their Apple Developer membership. Xcode account setup and a
usable local Developer ID Application identity are still required. Build scripts
now accept HERDR_SIGNING_IDENTITY, use hardened runtime and timestamping for a
Developer ID build, and retain ad-hoc signing by default. The DMG --notarize mode
uses HERDR_NOTARY_PROFILE to submit and staple the app and then the image, checks
Accepted and Gatekeeper assessment, and creates a final checksum. Credentials
stay in Keychain. See docs/macos-release.md for setup and interrupted submission
recovery. Actual signing/notarization remains unverified until credentials are
configured; no notarized release has been published by this preparation.

Preparation checks: all 19 Swift tests pass, development DMG builds and mounts,
bundled UI and app signature verify, and missing credentials/ad-hoc notarization
are rejected before submission. No signed build or notarization service request
was made, and the running HUD was not replaced or restarted.
