# Herdr HUD development

This repository is the standalone game HUD, with native macOS and Windows implementations.
Preserve the existing Omarchy HUD, Herdr servers, user agents, and their chats.
The public scope is the floating H, agent roster/output/prompts, alerts, and
visibility controls. Do not introduce Squad, browser hosting, or tablet features.

Read README.md and HANDOFF.md before changing the app. The canonical Git checkout lives on the Mac. Build and test Windows on the
Windows PC using a source copy; bring source changes back to the canonical repo. Do not copy the user's machine settings, addresses, agent output, or
credentials into source or commits. Local `.evidence/` is ignored intentionally.

Run Swift transport tests and JavaScript model tests after relevant changes.
Verify the packaged app uses its bundled resources, not SwiftPM build paths.
Treat shell arguments as literal data. Never retry uncertain prompt delivery.
Do not prompt user agents during tests; use controlled test transports.

Fullscreen collection flags are not proof of game compatibility. Preserve the
distinction between window-order evidence, rendered UI, physical input, and
actual game tests. Use the isolated fullscreen fixture before broader testing.
Windows is implemented as an alpha; actual game tests remain outstanding.
Read CONTRIBUTING.md for platform checks and privacy boundaries.

Rebuild and relaunch only this app when needed. Preserve any active draft before
relaunching once the user starts using it. Publishing, signing credentials, and
public releases are separate from this local prototype work.
