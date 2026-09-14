# Herdr HUD

Keep your agents working while you game. A draggable H button opens your Herdr
agents, recent output, and prompt composer above your desktop or fullscreen Space.

**macOS and Windows alpha — open source under MIT.** One repository contains
native hosts and a shared interface. Windows has been used over WoW Classic;
other games and exclusive fullscreen remain unverified.

## Download and install

Get the latest [alpha downloads](https://github.com/finna/herdr-hud/releases/tag/v0.1.0-alpha.1):

- **Apple Silicon Mac:** [Herdr-HUD-macOS-arm64.zip](https://github.com/finna/herdr-hud/releases/download/v0.1.0-alpha.1/Herdr-HUD-macOS-arm64.zip).
  Extract the ZIP, move **Herdr HUD.app** into Applications (or your own
  `~/Applications` folder), and open it. Intel Macs are not included in this build.
- **Windows 11 x64:** [Herdr-HUD-Windows-x64.zip](https://github.com/finna/herdr-hud/releases/download/v0.1.0-alpha.1/Herdr-HUD-Windows-x64.zip).
  Extract the whole ZIP into a folder, double-click **Install.cmd**, then open
  **Herdr HUD** from Start. The installer runs as your normal user. Keep all files
  together if running HerdrHUD.exe directly instead.
- **Omarchy Quattro:** use the existing [Omarchy plugin](https://github.com/finna/omarchy-herdr-hud).
  It installs directly without marketplace approval:
  `omarchy plugin add https://github.com/finna/omarchy-herdr-hud.git --enable`.

These first alpha downloads are **not notarized or signed with a public publisher
certificate** (the Mac app has a local ad-hoc signature). OS trust prompts are
expected. Download from this repository and compare the release's SHA256SUMS.
On a Mac, after attempting to open the app, trusted downloads can be allowed in
System Settings → Privacy & Security → Open Anyway; see
[Apple's instructions](https://support.apple.com/en-us/102445). This does not require
disabling Gatekeeper. Windows may show an unknown-publisher/SmartScreen prompt;
only proceed if you trust and have verified this download.

Close the HUD and preserve drafts before installing an update. No agent servers
need to be restarted. To uninstall, quit the HUD, turn off its optional login
startup, and remove the app; on Windows also remove its Start menu shortcut.
Settings locations are documented below.

## Run on macOS

Requires macOS 13+, Herdr 0.9+ installed with an existing running default session,
and existing SSH authentication for any saved remote machines. No account,
model API key, Python runtime, Node runtime, or hosted service is required to
run the packaged app. Xcode command-line tools are needed to build from source.

```sh
scripts/build-app.sh
mkdir -p ~/Applications
cp -R 'dist/Herdr HUD.app' ~/Applications/
open "$HOME/Applications/Herdr HUD.app"
```

The build is locally ad-hoc signed. Publisher signing/notarization and broader
hardware/game verification remain future release work.

- Click **H** to open or close the agents. Drag H to reposition it.
- **Command–Option–H:** toggle the agent panel.
- **Command–Option–Shift–H:** hide or restore the whole HUD.
- **Escape:** close the panel while keeping H visible.
- **Enter:** send a prompt to the selected ready agent.
- **Control–Enter or Shift–Enter:** insert a new line (Command/Option–Enter also insert a new line).
- The **H menu-bar item** has visibility, alternative shortcuts, launch-at-login,
  refresh, and quit controls. Login startup is off by default and remains unverified.
- Drag the roster divider to resize it. Visibility, position, view, and divider
  width are remembered. Prompt drafts are kept per agent while the app runs.
- Agents needing attention sort first, then working agents, then read idle agents.
- Silent alerts appear above H (below it near the top edge) after an agent finishes or needs input. Hover to
  retain one, click to open its agent, or dismiss it. The attention badge remains.

## Run on Windows

Requires Windows 11 x64 for the currently tested build, Microsoft Edge WebView2
Runtime, and either local Herdr 0.9+ or SSH access to an existing Mac/Linux Herdr setup.
The build includes its .NET runtime. Node and a .NET SDK are not needed to run it.
Windows 10 and ARM64 are untested.

To build with the .NET 10 SDK installed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/build-windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/install-windows.ps1
```

Open **Herdr HUD** from Start. Right-click the tray H and choose **Herdr connection**.
Leave the SSH target blank to use this PC's Herdr installation, or enter your
existing Mac/Linux SSH target and session. In SSH-source mode, the HUD reads that
host's saved Herdr machines and accesses them through the source host, using its
existing SSH aliases and credentials. It does not copy private keys or enroll
machines. Root and saved-host authentication must already work without prompts.

- **Ctrl+Alt+H:** open/close the agent panel.
- **Ctrl+Alt+Shift+H:** show/hide the entire HUD.
- Alternative Ctrl+Win shortcuts and shortcuts-off are available in the tray menu.
- H is draggable. Escape closes the panel; Enter sends; Ctrl/Shift+Enter adds a line.
- Launch at login is optional and off by default. Quit from the tray menu.
- The panel can be resized from its right and bottom edges.
- Notifications appear above H (below it near the top edge) and follow it when moved.

The Windows package is currently unsigned. It runs as your normal user and uses
WinForms, WebView2 and native topmost windows. It does not inject into games or
install a driver. **Exclusive fullscreen is not yet verified.** A visible overlay
and focus return over a test window do not prove compatibility with your game.

Settings and private diagnostic snapshots live in `%LOCALAPPDATA%\Herdr HUD`.
The installed app lives in `%LOCALAPPDATA%\Programs\Herdr HUD`.
The executable supports the same basic `--open`, `--close`, `--show`, `--hide`,
`--toggle`, `--roster`, `--inspect`, `--snapshot`, and `--verify-ui` controls.
Results are written under its private support directory. `--fixture` briefly
creates a test window, clicks only that window and H, checks focus/order, captures
that display, and then restores the prior window and pointer. It is a development
test, not an exclusive-fullscreen game test. Do not run it during active gameplay.

## Herdr connection

The app reads `herdr machine list --json` from your existing installation. It
lists the local default session and enabled saved SSH machines, respecting each
remote profile's named session. It does not enroll machines, create teams,
restart Herdr, or install/update anything on remote computers. Machine discovery
is one level deep, matching the host's configured Herdr machines.

Local Herdr is located in its standard user or Homebrew install, then on PATH.
Remote reads and sends use installed SSH with existing configuration, batch
mode, and strict host-key checking. Herdr must be available in its standard
remote user install, Homebrew path, or login PATH. Remote Mac/Linux hosts need Python 3 for a small, standard-library-only prompt
helper. It runs over SSH without installing files and forwards text from stdin
to the host’s Herdr socket. Local Mac/Windows prompts use native socket/pipe
clients and do not require Python. Complete authentication and
host-key setup in Herdr first; the HUD does not open hidden SSH questions.

Agent identities include machine, target, session, pane, terminal, and available
conversation identity. Each read/send rechecks the identity; sends also recheck
readiness and the saved machine configuration. Busy/blocked/unknown/offline
agents cannot receive prompts. Missing machines keep cached cards marked offline.

Herdr 0.9 does not atomically bind a prompt to an expected terminal ID. A fresh
identity check reduces risk, but another client can still replace a pane between
check and submission. Sends are serialized and never automatically retried.
An ambiguous result retains the draft and blocks another send until the user
inspects Herdr and explicitly reconciles it.

Chat is a conservative formatting of recent captured Codex terminal output,
not full structured conversation history. Other agents retain Terminal view.
Native approvals/questions must still be answered in Herdr.

## Prompt privacy and output limits

Prompt text never appears in process arguments or SSH command strings. It travels
over stdin across each SSH hop, then through Herdr's local socket API. The native
hosts and remote helper recheck the expected agent and validate acknowledgements.
Unknown delivery is never retried automatically.

Native command output is streamed with a 1 MiB stdout and 64 KiB stderr limit,
with 12-second Mac / 15-second Windows deadlines. Mac commands start in their own
process group; Windows commands are created suspended, assigned to a kill-on-close
Job Object, then resumed. Timeout or overflow terminates the owned group/job,
including descendants. The remote helper caps socket replies at 1 MiB and status
output at 64 KiB, and has a 12-second deadline. Prompts are limited to 60 KB.

## Architecture

- `Sources/HerdrHUD/App.swift`: AppKit nonactivating panels, fullscreen Spaces,
  menu-bar controls, Carbon shortcuts, monitor positioning, and WebKit bridge.
- `Sources/HerdrHUD/Transport.swift`: bounded process groups and native socket prompts.
- `Sources/HerdrHUD/Herdr.swift`: saved machine
  discovery, cached roster, fresh identity/readiness checks, literal SSH quoting.
- `Sources/HerdrHUD/Resources/`: reusable UI and transcript/attention logic.
- `Windows/`: native Windows shell, WebView2 bridge, and local/SSH-source transport.
- No HTTP listener, browser credentials, third-party model connection, telemetry,
  Squad integration, or tablet interface is included.

Only bundled files are loaded in the WebView. Its content security policy blocks
network requests. Terminal output is rendered as text, never executable HTML.
UI requests use a narrow native operation allowlist and main-frame checks.

Preferences use the `org.herdr.community.hud` defaults domain. Diagnostics and
explicitly requested panel snapshots live in `~/Library/Application Support/Herdr HUD/`.
Snapshots contain private agent output; do not include them in public releases.
The app itself requires neither Accessibility nor Screen Recording permission.
Those permissions may be needed by external tools to verify gameplay interactions.

## Checks

```sh
swift test
node --test Tests/*.test.cjs
node --check Sources/HerdrHUD/Resources/app.js
python3 Tests/test_prompt_helper.py
```

Node is needed only for JavaScript development tests; Python 3 is used by socket
fixtures and remote-helper tests during development. Swift tests exercise
identity changes, readiness, argument quoting, ambiguous delivery, large output,
saved-machine removal, offline caching, and reconnects with controlled transports.
They do not prompt active user agents.

With the app running:

```sh
"$HOME/Applications/Herdr HUD.app/Contents/MacOS/HerdrHUD" --open
```

The executable also supports `--close`, `--show`, `--hide`, `--toggle`,
`--roster` (read-only live JSON), `--inspect`, and `--snapshot` (own panel only).
`--verify-ui` checks live local/remote reads, draft retention, view switching,
search, text safety, and layout without sending prompts. It requires both hosts.

`scripts/fullscreen-probe.swift` creates an isolated temporary fullscreen window,
opens the HUD, records the window order and foreground application, closes the
fixture, and restores the prior app. Its evidence is stored under `.evidence/`.
This verifies macOS fullscreen window behavior, not actual gameplay or mouse input.

## Release boundary

Mac and Windows alpha. Verify real games, pointer/keyboard focus return, drag across
monitors, alert interactions, physical shortcuts, login startup, and restart
behavior before broad release. Intel Macs and older macOS releases are untested.
Windows exclusive fullscreen and other Linux compositors require further work
and game tests; ordinary always-on-top flags alone are not the release criterion.

MIT licensed. Derived from Alex Finn's MIT-licensed Herdr HUD for Omarchy.
Community project; not affiliated with Herdr or Basecamp.

Implementation references: [Apple fullscreen overlay behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications) and [Herdr CLI host/session scope](https://herdr.dev/docs/cli-reference/).
