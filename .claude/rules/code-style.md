# Code Style

- Follow the project's existing patterns and conventions
- Keep functions focused and small
- Prefer explicit over implicit
- Write self-documenting code — add comments only where logic isn't self-evident
- UI state lives in `SentryStore` (`@MainActor`, `@Observable`); views stay declarative.
- System calls (`PropertyListSerialization`, `Process`, file hashing, `NSWorkspace`) are confined to the non-UI files (`PersistenceScanner`, `PersistenceActions`, `Signature`).
- Scanning is read-only. State-changing actions (block/restore/remove) live only in `PersistenceActions`, must be user-initiated and confirmed in the UI, and reversible where possible (launch items are renamed to `.sentry-disabled`, never deleted; Restore round-trips). Login-item removal is the one non-reversible action and is flagged as such in its confirmation.
- Privilege boundary: never assume root. User-domain items act directly; system-domain items escalate via a single `osascript … with administrator privileges` prompt — no privileged helper.
