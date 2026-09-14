# Herdr HUD

Keep your agents working while you game. A draggable H button opens your Herdr
agents, recent output, and prompt composer above your desktop or fullscreen Space.

**Mac preview, built directly on a Mac Studio.** This repository contains the
native macOS app and reusable HTML/CSS/JavaScript interface. Windows and Linux
shells are not implemented here yet. The existing Omarchy plugin remains at
https://github.com/finna/omarchy-herdr-hud.

## Run on macOS

Requires macOS 13+, Herdr installed with an existing running default session,
and existing SSH authentication for any saved remote machines. No account,
model API key, Python runtime, Node runtime, or hosted service is required to
run the packaged app. Xcode command-line tools are needed to build from source.

```sh
scripts/build-app.sh
mkdir -p ~/Applications
cp -R 'dist/Herdr HUD.app' ~/Applications/
open "$HOME/Applications/Herdr HUD.app"
```

The build is locally ad-hoc signed. Public distribution still needs release
packaging, signing/notarization, and broader hardware/game verification.

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
- Silent alerts appear beside H after an agent finishes or needs input. Hover to
  retain one, click to open its agent, or dismiss it. The attention badge remains.

## Herdr connection

The app reads `herdr machine list --json` from your existing installation. It
lists the local default session and enabled saved SSH machines, respecting each
remote profile's named session. It does not enroll machines, create teams,
restart Herdr, or install/update anything on remote computers. Machine discovery
is one level deep, matching the host's configured Herdr machines.

Local Herdr is located in its standard user or Homebrew install, then on PATH.
Remote reads and sends use installed SSH with existing configuration, batch
mode, and strict host-key checking. Herdr must be available in its standard
remote user install, Homebrew path, or login PATH. Complete authentication and
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

## Architecture

- `Sources/HerdrHUD/App.swift`: AppKit nonactivating panels, fullscreen Spaces,
  menu-bar controls, Carbon shortcuts, monitor positioning, and WebKit bridge.
- `Sources/HerdrHUD/Herdr.swift`: native process transport, saved machine
  discovery, cached roster, fresh identity/readiness checks, literal SSH quoting.
- `Sources/HerdrHUD/Resources/`: reusable UI and transcript/attention logic.
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
node --test Tests/model.test.cjs
node --check Sources/HerdrHUD/Resources/app.js
```

Node is needed only for JavaScript development tests. Swift tests exercise
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

Mac preview only. Verify real games, pointer/keyboard focus return, drag across
monitors, alert interactions, physical shortcuts, login startup, and restart
behavior before broad release. Intel Macs and older macOS releases are untested.
Windows fullscreen and other Linux compositors require their own implementations
and game tests; ordinary always-on-top flags alone are not the release criterion.

MIT licensed. Derived from Alex Finn's MIT-licensed Herdr HUD for Omarchy.
Community project; not affiliated with Herdr or Basecamp.

Implementation references: [Apple fullscreen overlay behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications) and [Herdr CLI host/session scope](https://herdr.dev/docs/cli-reference/).
