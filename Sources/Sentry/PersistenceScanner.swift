import Foundation
import CryptoKit

/// Read-only enumeration of macOS persistence surfaces. Every method here
/// only *reads* — Sentry never disables or removes anything.
enum PersistenceScanner {
    static func scan() -> [PersistenceItem] {
        var out: [PersistenceItem] = []
        out += launchItems()
        out += loginItems()
        out += cronJobs()
        out += shellRCFiles()
        return out
    }

    // MARK: - LaunchAgents / LaunchDaemons

    private static func launchItems() -> [PersistenceItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs: [(URL, PersistenceSource)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .launchAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .launchAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .launchDaemon),
            // /System/Library/Launch* deliberately skipped — Apple-managed,
            // SIP-protected, pure noise for a persistence audit.
        ]

        var items: [PersistenceItem] = []
        let fm = FileManager.default
        for (dir, source) in dirs {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }
            for url in entries where url.pathExtension == "plist" {
                items.append(parseLaunchPlist(url, source: source))
            }
        }
        return items
    }

    private static func parseLaunchPlist(_ url: URL, source: PersistenceSource) -> PersistenceItem {
        let path = url.path
        var label = url.deletingPathExtension().lastPathComponent
        var target = ""
        var runAtLoad = false

        if let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
           ) as? [String: Any] {
            if let l = plist["Label"] as? String { label = l }
            if let program = plist["Program"] as? String {
                target = program
            } else if let args = plist["ProgramArguments"] as? [String],
                      let first = args.first {
                target = first
            }
            if let ral = plist["RunAtLoad"] as? Bool { runAtLoad = ral }
        } else {
            // Binary plist or unreadable XML — fall back to plutil → JSON.
            if let parsed = plutilJSON(path) {
                if let l = parsed["Label"] as? String { label = l }
                if let program = parsed["Program"] as? String {
                    target = program
                } else if let args = parsed["ProgramArguments"] as? [String],
                          let first = args.first {
                    target = first
                }
                if let ral = parsed["RunAtLoad"] as? Bool { runAtLoad = ral }
            }
        }

        let sig = Signature.classify(target)
        var detail = target.isEmpty ? "(no Program/ProgramArguments)" : target
        if runAtLoad { detail += "  ·  RunAtLoad" }

        return PersistenceItem(
            source: source,
            key: "agent:\(path)",
            name: label,
            detail: detail,
            signature: sig
        )
    }

    /// `plutil -convert json -o - <file>` for binary/edge-case plists.
    private static func plutilJSON(_ path: String) -> [String: Any]? {
        let res = runCapture("/usr/bin/plutil", ["-convert", "json", "-o", "-", path])
        guard res.exitCode == 0,
              let data = res.stdout.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    // MARK: - Login items

    private static func loginItems() -> [PersistenceItem] {
        let res = runCapture("/usr/bin/osascript", [
            "-e", "tell application \"System Events\" to get the name of every login item"
        ])
        guard res.exitCode == 0 else { return [] }
        let names = res.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return names.map { name in
            PersistenceItem(
                source: .loginItem,
                key: "login:\(name)",
                name: name,
                detail: "login item",
                // Login-item targets aren't reliably resolvable via AppleScript
                // without extra entitlements; classify by name is not possible,
                // so we report presence and leave signature unknown.
                signature: .unknown
            )
        }
    }

    // MARK: - cron

    private static func cronJobs() -> [PersistenceItem] {
        let res = runCapture("/usr/bin/crontab", ["-l"])
        // Exit 1 with "no crontab for" is the normal empty case.
        guard res.exitCode == 0 else { return [] }
        let lines = res.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        return lines.map { line in
            let hash = shortHash(line)
            return PersistenceItem(
                source: .cron,
                key: "cron:\(hash)",
                name: "crontab entry",
                detail: line,
                signature: .unknown
            )
        }
    }

    // MARK: - Shell rc files

    private static func shellRCFiles() -> [PersistenceItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let names = [".zshrc", ".zprofile", ".zshenv",
                     ".bashrc", ".bash_profile", ".profile"]
        var items: [PersistenceItem] = []
        for name in names {
            let url = home.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            let digest = SHA256.hash(data: data)
            let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
            // Key folds the hash in so a content change yields a NEW key,
            // which the snapshot diff surfaces as a "changed" notification.
            items.append(
                PersistenceItem(
                    source: .shellRC,
                    key: "shellrc:\(name):\(hex.prefix(12))",
                    name: name,
                    detail: "sha256 \(hex.prefix(12))…  ·  \(data.count) bytes",
                    signature: .unknown
                )
            )
        }
        return items
    }

    // MARK: - Helpers

    private static func shortHash(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.prefix(6).compactMap { String(format: "%02x", $0) }.joined()
    }

    private struct Captured {
        let exitCode: Int32
        let stdout: String
    }

    private static func runCapture(_ launchPath: String, _ args: [String]) -> Captured {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            return Captured(exitCode: -1, stdout: "")
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return Captured(
            exitCode: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? ""
        )
    }
}
