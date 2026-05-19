import AppKit

/// Sentry's glyphs. Relocated out of the (now thin) `SentryApp`
/// shim so both the standalone shim AND the pane — which is what
/// the launcher loads — share one source. Pure SF Symbols, no
/// bundled assets.
enum SentryBrand {
    /// Half-filled shield, template so macOS tints it for the menu
    /// bar. Uses the resolution-independent drawing-handler
    /// initializer so it stays crisp on Retina (the old
    /// lockFocus path baked a 1× bitmap that looked blurry).
    static let menuBarIcon: NSImage = {
        let base = NSImage(
            systemSymbolName: "shield.lefthalf.filled",
            accessibilityDescription: "Sentry"
        ) ?? NSImage()
        let config = NSImage.SymbolConfiguration(
            pointSize: 14, weight: .regular)
        let symbol = base.withSymbolConfiguration(config) ?? base
        let h: CGFloat = 16
        let src = symbol.size
        let w = src.height > 0 ? (h * src.width / src.height) : h
        let fitted = NSImage(
            size: NSSize(width: w, height: h), flipped: false
        ) { rect in
            symbol.draw(in: rect, from: .zero,
                        operation: .sourceOver, fraction: 1)
            return true
        }
        fitted.isTemplate = true
        return fitted
    }()

    /// Same glyph for in-app branding (rendered with the accent tint).
    static let appIcon: NSImage = {
        NSImage(systemSymbolName: "shield.lefthalf.filled",
                accessibilityDescription: "Sentry") ?? NSImage()
    }()
}
