# Code Style

- Follow the project's existing patterns and conventions
- Keep functions focused and small
- Prefer explicit over implicit
- Write self-documenting code — add comments only where logic isn't self-evident
- UI state lives in `SentryStore` (`@MainActor`, `@Observable`); views stay declarative.
- System calls (`PropertyListSerialization`, `Process`, file hashing) are confined to the non-UI scanner files.
- Sentry only ever *reads* persistence state — it never modifies, disables, or removes a launch item, login item, or rc file.
