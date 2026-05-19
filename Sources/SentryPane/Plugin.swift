import AppKit
import SwiftUI
import SuiteKit

/// Sentry as a SuiteKit pane. Owns the store, vends the UI + glyph,
/// and routes a tapped notification to the offending item. Both the
/// standalone shim and the MattsSoftware host talk to Sentry only
/// through this object.
@MainActor
public final class SentryPaneProvider: NSObject, SuitePane {
    private let store = SentryStore()

    public var suiteABIVersion: Int { SuiteKitABI.current }
    public var paneID: String { "sentry" }
    public var paneTitle: String { "SENTRY" }
    public var paneTintHex: String { "#5B8DEF" }

    public func paneMenuBarImage() -> NSImage { SentryBrand.menuBarIcon }

    public func paneMakeView() -> NSView {
        NSHostingView(rootView: ContentView().environment(store))
    }

    public func paneStart() {
        store.start()
        Notifier.requestAuthorization()
    }

    public func paneStop() {
        // Sentry's audit timer is harmless to leave running; there's
        // no explicit teardown and re-merging must not lose history.
    }

    public func paneFocus(_ key: String) {
        store.focusedKey = key
    }
}

@_cdecl("suitePaneCreate")
public func suitePaneCreate() -> Unmanaged<AnyObject> {
    MainActor.assumeIsolated {
        Unmanaged.passRetained(SentryPaneProvider())
    }
}
