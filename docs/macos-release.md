# macOS signing and notarization

The public alpha ZIP remains ad-hoc signed. These scripts prepare a future signed
release; their existence does not establish that any published asset is notarized.

## One-time setup on the release Mac

1. Use an active Apple Developer Program membership. Sign in through Xcode
   Settings > Apple Accounts (Accounts on older Xcode versions).
2. Select the paid team, open Manage Certificates, and create a Developer ID
   Application certificate. Keep its private key in this Mac's Keychain.
3. Confirm the certificate is usable with
   `security find-identity -v -p codesigning`.
4. In a local Terminal, run `xcrun notarytool store-credentials herdr-hud-release`.
   Follow its interactive prompts for the Apple Account, Team ID and an
   app-specific password. Create that password through your Apple Account.
   Enter it at the secure prompt, never in a shell command, chat or repository.
   The tool validates the credentials and stores them in Keychain.

An App Store Connect API key can also authenticate notarytool. Store credentials
outside this repository; scripts only consume a Keychain profile name.

## Build and verify

Run platform tests first. Then set the public identity name (including its Team
ID) exactly as shown by `security find-identity`; the example below is a placeholder:

```sh
export HERDR_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export HERDR_NOTARY_PROFILE='herdr-hud-release'
scripts/package-macos-dmg.sh --notarize
```

This validates notary access, builds a clean app with hardened runtime and a secure
timestamp, submits the app, checks for Accepted, staples and validates its ticket,
and asks Gatekeeper to assess it. It copies that app into a drag-to-Applications
DMG, signs and notarizes the DMG, staples its ticket, assesses it and writes a
SHA256 checksum. Neither credentials nor private diagnostics are packaged.
The release path refuses missing credentials or ad-hoc signing instead of silently
falling back. Ordinary `scripts/build-app.sh` remains an ad-hoc development build.

Submission records are retained under ignored `dist/notary.*/submission.plist`.
If a wait times out or a response is uncertain, inspect the recorded submission
ID with `xcrun notarytool info ID --keychain-profile herdr-hud-release` or `wait`.
Fetch rejection details with `xcrun notarytool log ID --keychain-profile
herdr-hud-release`. Do not resubmit just because the local wait timed out.
For an accepted submission, finish with `xcrun stapler staple PATH`,
`xcrun stapler validate PATH`, and Gatekeeper assessment. Do not publish an
intermediate image or reuse a checksum from before stapling.

Before publishing, mount the completed DMG and verify the contained app's ticket
and signature. Copy it to a fresh location and test the actual downloaded/quarantined
launch flow on a Mac, preserving any existing HUD draft before replacing or
relaunching it. Verify bundled UI, agent discovery and prompt controls without
sending test prompts to live agents. Signing and Gatekeeper assessment alone do
not prove the hardened runtime app works. Recalculate the final checksum after
all changes. Publish the verified DMG and update download links together.

Apple references: [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates),
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
