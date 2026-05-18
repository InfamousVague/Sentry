import Foundation
import AppKit

struct PersistenceError: Error {
    let message: String
}

/// User-initiated, confirmed actions on persistence items. All shell / AppKit
/// side effects live here so the views and scanner stay declarative.
///
/// Blocking is reversible: launch items are unloaded and renamed to
/// `<plist>.sentry-disabled` (launchd ignores non-`.plist` files), and Restore
/// renames them back. Login items are removed (not auto-restorable).
enum PersistenceActions {
    private static let disabledSuffix = ".sentry-disabled"
    private static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    // MARK: - Read-only conveniences

    static func reveal(_ item: PersistenceItem) {
        guard let target = item.path ?? item.program,
              FileManager.default.fileExists(atPath: target) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target)])
    }

    static func copyPath(_ item: PersistenceItem) {
        let value = item.path ?? item.program ?? item.detail
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
    }

    static func inspect(_ item: PersistenceItem) -> String {
        var lines = [
            "\(item.name)",
            "Source: \(item.source.rawValue)",
            "Signature: \(item.signature.label)",
        ]
        if let program = item.program { lines.append("Program: \(program)") }
        lines.append("")

        switch item.source {
        case .launchAgent, .launchDaemon:
            if let path = item.path {
                lines.append("Path: \(path)")
                lines.append("")
                let dump = run("/usr/bin/plutil", ["-p", path])
                lines.append(dump.exitCode == 0 ? dump.stdout : "(could not read plist)")
            }
        case .shellRC:
            if let path = item.path,
               let data = FileManager.default.contents(atPath: path) {
                let text = String(decoding: data.prefix(16_384), as: UTF8.self)
                lines.append("Path: \(path)")
                lines.append("")
                lines.append(text)
                if data.count > 16_384 { lines.append("\n… (truncated)") }
            }
        case .cron:
            lines.append(item.detail)
        case .loginItem:
            lines.append("Login item — target not resolvable without extra entitlements.")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Block / Restore

    static func block(_ item: PersistenceItem) throws {
        switch item.source {
        case .loginItem:
            let name = item.name.replacingOccurrences(of: "\"", with: "\\\"")
            let r = run("/usr/bin/osascript", [
                "-e", "tell application \"System Events\" to delete login item \"\(name)\"",
            ])
            if r.exitCode != 0 {
                throw PersistenceError(message: "Couldn't remove login item: \(r.stderr)")
            }

        case .launchAgent, .launchDaemon:
            guard let path = item.path, !item.disabled else {
                throw PersistenceError(message: "Nothing to block.")
            }
            let dest = path + disabledSuffix
            if path.hasPrefix(home) {
                _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())", path])
                try move(path, to: dest)
            } else {
                let qPath = try shq(path)
                let qDest = try shq(dest)
                try adminShell("/bin/launchctl bootout system \(qPath) ; /bin/mv \(qPath) \(qDest)")
            }

        default:
            throw PersistenceError(message: "This item type can't be blocked.")
        }
    }

    static func restore(_ item: PersistenceItem) throws {
        guard item.disabled, let path = item.path, path.hasSuffix(disabledSuffix) else {
            throw PersistenceError(message: "Not a Sentry-disabled item.")
        }
        let original = String(path.dropLast(disabledSuffix.count))
        if path.hasPrefix(home) {
            try move(path, to: original)
        } else {
            let qPath = try shq(path)
            let qOrig = try shq(original)
            try adminShell("/bin/mv \(qPath) \(qOrig)")
        }
    }

    // MARK: - Helpers

    private static func move(_ from: String, to: String) throws {
        do {
            if FileManager.default.fileExists(atPath: to) {
                try FileManager.default.removeItem(atPath: to)
            }
            try FileManager.default.moveItem(atPath: from, toPath: to)
        } catch {
            throw PersistenceError(message: "File move failed: \(error.localizedDescription)")
        }
    }

    /// Single-quote a path for `do shell script`. Refuses paths containing a
    /// single quote rather than risk a broken/injected command.
    private static func shq(_ s: String) throws -> String {
        guard !s.contains("'") else {
            throw PersistenceError(message: "Path contains a quote — not supported.")
        }
        return "'\(s)'"
    }

    private static func adminShell(_ command: String) throws {
        let script = "do shell script \"\(command.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let r = run("/usr/bin/osascript", ["-e", script])
        if r.exitCode != 0 {
            // User-cancelled auth → exit 1 with "User canceled."
            throw PersistenceError(
                message: r.stderr.contains("canceled")
                    ? "Cancelled."
                    : "Admin action failed: \(r.stderr)"
            )
        }
    }

    private struct Result { let exitCode: Int32; let stdout: String; let stderr: String }

    private static func run(_ launchPath: String, _ args: [String]) -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do { try proc.run() } catch {
            return Result(exitCode: -1, stdout: "", stderr: "\(error)")
        }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return Result(
            exitCode: proc.terminationStatus,
            stdout: String(data: o, encoding: .utf8) ?? "",
            stderr: String(data: e, encoding: .utf8) ?? ""
        )
    }
}
