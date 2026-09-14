# Contributing

Herdr HUD is one product with native macOS and Windows hosts and a shared web
interface. Keep this project limited to the floating H, agents, output, prompts,
alerts, and visibility controls.

- `Sources/HerdrHUD/*.swift`: macOS host and transport.
- `Sources/HerdrHUD/Resources/`: UI used by both hosts. Windows copies these
  exact files at build time; do not maintain a second UI copy.
- `Windows/`: WinForms, WebView2, native desktop integration and CLI/SSH transport.
- `Tests/`, `Windows.Tests/`: model and transport checks.

Run `swift test` for Mac changes, `node --test Tests/*.test.cjs` for interface
changes, and `dotnet run --project Windows.Tests/HerdrHUD.Tests.csproj -c Release`
on Windows for transport changes. Build native hosts on their target operating
systems using the scripts in `scripts/`.

Test prompt delivery with a controlled transport, never with someone else's
active agents. Preserve identity/readiness checks and never automatically retry
an uncertain send. Treat terminal text as data, shell arguments as literal values,
and only bundled UI as trusted. Do not loosen SSH host-key checks to fix setup.

For game reports include OS version, game, window mode, monitor/DPI arrangement,
whether H stays visible, whether clicking it minimizes the game, whether typing
reaches the HUD only, and whether closing the panel returns focus. Separate actual
game results from fullscreen test-window results. Exclusive fullscreen and
anti-cheat compatibility cannot be inferred from an always-on-top flag.

Do not attach diagnostics, screenshots, transcripts, SSH settings, or machine
lists without reviewing them for private information. Demo screenshots should use
fictional agents. Local diagnostics are outside the source tree; `.evidence/`,
build directories, and installed apps are excluded from Git.
