import Foundation
import Observation

/// The source bucket a persistence item came from. Drives UI grouping.
enum PersistenceSource: String, CaseIterable {
    case launchAgent  = "Launch Agents"
    case launchDaemon = "Launch Daemons"
    case loginItem    = "Login Items"
    case cron         = "Cron"
    case shellRC      = "Shell rc"

    /// Display order in the popover.
    var order: Int {
        switch self {
        case .launchAgent:  return 0
        case .launchDaemon: return 1
        case .loginItem:    return 2
        case .cron:         return 3
        case .shellRC:      return 4
        }
    }
}

/// One audited persistence entry. `key` is the stable identity used for
/// snapshot diffing and notification-click focus (e.g. `agent:/path.plist`).
struct PersistenceItem: Identifiable, Hashable {
    let source: PersistenceSource
    let key: String
    let name: String         // Label / login-item name / cron line / rc filename
    let detail: String       // target binary path, command, or hash summary
    let signature: SignatureStatus

    var id: String { key }
}

@MainActor
@Observable
final class SentryStore {
    var items: [PersistenceItem] = []
    var lastScan: Date?
    var scanning = false
    /// Stable key the user asked to jump to (set from a notification click).
    var focusedKey: String?

    @ObservationIgnored private var seenKeys: Set<String> = []
    @ObservationIgnored private var firstScanDone = false
    @ObservationIgnored private var timer: Timer?

    /// Items grouped + ordered by source, for the sectioned UI.
    var sections: [(source: PersistenceSource, items: [PersistenceItem])] {
        Dictionary(grouping: items, by: { $0.source })
            .sorted { $0.key.order < $1.key.order }
            .map { (source: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        scanning = true
        Task.detached {
            let scanned = PersistenceScanner.scan()
            await MainActor.run { self.applyScan(scanned) }
        }
    }

    private func applyScan(_ scanned: [PersistenceItem]) {
        items = scanned
        lastScan = Date()
        scanning = false

        let current = Set(scanned.map { $0.key })
        if firstScanDone {
            let newKeys = current.subtracting(seenKeys)
            if newKeys.count > 5 {
                // A burst (e.g. first run after a big software install) —
                // one summary instead of a notification storm.
                Notifier.postSummary(count: newKeys.count)
            } else {
                for item in scanned where newKeys.contains(item.key) {
                    Notifier.postNewItem(item)
                }
            }
        }
        seenKeys = current
        firstScanDone = true
    }
}
