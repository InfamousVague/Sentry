import Foundation

/// Code-signature / notarization status of a target binary, in increasing
/// order of trust. Drives the colored badge in the UI.
enum SignatureStatus: String {
    case notarized          // Notarized by Apple — `spctl --assess` accepts it.
    case signed             // Validly signed but not notarized (Developer ID / Apple-internal).
    case unsigned           // Ad-hoc, broken, or no signature at all.
    case unknown            // Target path missing or could not be evaluated.

    /// Traffic-light color name consumed by ContentView.
    var color: String {
        switch self {
        case .notarized: return "green"
        case .signed:    return "yellow"
        case .unsigned:  return "red"
        case .unknown:   return "gray"
        }
    }

    var label: String {
        switch self {
        case .notarized: return "notarized"
        case .signed:    return "signed, not notarized"
        case .unsigned:  return "unsigned"
        case .unknown:   return "unknown"
        }
    }
}

enum Signature {
    /// Classify the binary at `path`. Runs `spctl --assess` first (the
    /// authoritative notarization gate), falling back to `codesign -dv` to
    /// distinguish "validly signed but not notarized" from "no signature".
    static func classify(_ path: String) -> SignatureStatus {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return .unknown
        }

        // spctl assesses the same way Gatekeeper does. Exit 0 => accepted
        // (notarized or on a recognized allowlist). `--type execute` so it
        // evaluates a plain Mach-O the way it would a launchd target.
        let assess = run("/usr/sbin/spctl", ["--assess", "--type", "execute", "-vv", path])
        if assess.exitCode == 0 {
            let combined = (assess.stdout + assess.stderr).lowercased()
            // spctl prints the matched source; "notariz" only appears when
            // the ticket/notarization check actually passed.
            if combined.contains("notariz") {
                return .notarized
            }
            // Accepted by spctl but the wording doesn't mention notarization
            // (e.g. an Apple system binary) — still a trusted, signed binary.
            return signedOrUnsigned(path) == .signed ? .signed : .notarized
        }

        // spctl rejected it (or it isn't a notarized executable). Fall back
        // to codesign to tell "Developer ID but not notarized" (yellow)
        // apart from "no/ad-hoc signature" (red).
        return signedOrUnsigned(path)
    }

    /// codesign-only check: a valid Authority chain => `.signed`, an ad-hoc
    /// ("Signature=adhoc") or absent signature => `.unsigned`.
    private static func signedOrUnsigned(_ path: String) -> SignatureStatus {
        let cs = run("/usr/bin/codesign", ["-dv", "--verbose=2", path])
        let out = (cs.stdout + cs.stderr)
        if cs.exitCode != 0 {
            return .unsigned
        }
        if out.contains("Signature=adhoc") {
            return .unsigned
        }
        if out.contains("Authority=") {
            return .signed
        }
        return .unsigned
    }

    // MARK: - Process helper

    private struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private static func run(_ launchPath: String, _ args: [String]) -> Result {
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
            return Result(exitCode: -1, stdout: "", stderr: "\(error)")
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return Result(
            exitCode: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
