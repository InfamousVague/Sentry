# sentry (native)

Native macOS menu-bar persistence/launch-item auditor. Enumerates LaunchAgents/Daemons, login items, cron, and shell rc files, classifies each target binary's code-signature/notarization status, and notifies on NEW or CHANGED persistence. Swift + SwiftUI, `NSStatusItem`/`NSPopover`, no third-party dependencies.

## Commit Convention
Angular commits required with scope. See @.claude/rules/commit-rules.md for details.

## Code Style
See @.claude/rules/code-style.md

## Architecture

- `Sources/Sentry/SentryApp.swift` — `@main` SwiftUI app: `Settings` scene + `.accessory` activation (no Dock icon); `AppDelegate` owns the `NSStatusItem` + transient `NSPopover`.
- `Sources/Sentry/Models.swift` — model types + `SentryStore` (`@Observable`, `@MainActor`): 8s `Timer` poll, snapshot diff, first-scan guard.
- `Sources/Sentry/PersistenceScanner.swift` — enumerates LaunchAgents/Daemons (`PropertyListSerialization`), login items (`osascript`), cron (`crontab -l`), shell rc files (content hash).
- `Sources/Sentry/Signature.swift` — `spctl --assess` / `codesign -dv` wrapper → notarized / signed / unsigned classification.
- `Sources/Sentry/Notifier.swift` — `UNUserNotificationCenter` wrapper; carries a stable focus key.
- `Sources/Sentry/ContentView.swift` — the menu-bar panel UI (sections per source, signature badges).

## Menu-bar icon

Uses the SF Symbol `shield.lefthalf.filled` as a template `NSStatusItem` image — no bundled icon assets.

## Running

```
swift build
swift run                 # menu-bar item appears; no Dock icon
bash scripts/make-app.sh  # assembles Sentry.app (LSUIElement), Developer-ID signed
open Sentry.app           # run the bundled menu-bar agent
```
