import SwiftUI
import AppKit
import UserNotifications

@main
struct SentryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Accessory app: the real UI is the NSStatusItem/NSPopover the
        // delegate manages. This scene stays empty/never shown.
        Settings { EmptyView() }
    }

    /// Half-filled shield, set as a template so macOS tints it for the
    /// active menu-bar appearance (dark on light bars, light on dark).
    /// No bundled asset — the SF Symbol ships with the OS.
    static let menuBarIcon: NSImage = {
        let base = NSImage(
            systemSymbolName: "shield.lefthalf.filled",
            accessibilityDescription: "Sentry"
        ) ?? NSImage()
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = base.withSymbolConfiguration(config) ?? base
        // The menu bar is only ~22pt thick and `shield.lefthalf.filled`
        // is a tall glyph, so drawing it at its natural size clipped
        // the top and bottom. Redraw into a fixed 16pt-tall canvas
        // (aspect preserved) so it always fits with breathing room.
        let h: CGFloat = 16
        let src = symbol.size
        let w = src.height > 0 ? (h * src.width / src.height) : h
        let fitted = NSImage(size: NSSize(width: w, height: h))
        fitted.lockFocus()
        symbol.draw(in: NSRect(x: 0, y: 0, width: w, height: h),
                    from: .zero, operation: .sourceOver, fraction: 1)
        fitted.unlockFocus()
        fitted.isTemplate = true
        return fitted
    }()

    /// Same glyph for in-app branding (rendered with the accent tint).
    static let appIcon: NSImage = {
        NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "Sentry")
            ?? NSImage()
    }()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = SentryStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = SentryApp.menuBarIcon
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environment(store)
        )

        store.start()

        UNUserNotificationCenter.current().delegate = self
        Notifier.requestAuthorization()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let key = response.notification.request.content.userInfo["sentryKey"] as? String
        DispatchQueue.main.async {
            self.store.focusedKey = key
            self.showPopover()
        }
        completionHandler()
    }
}
