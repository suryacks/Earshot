import AppKit

/// Where the island lives, and how big the notch actually is.
///
/// Notch dimensions are read from the screen's safe-area insets and auxiliary
/// top areas rather than hard-coded, because they differ between the 14" and
/// 16" MacBook Pro and the MacBook Air. Macs without a notch get a floating
/// island just below the menu bar instead, so the feature is not silently
/// useless on an iMac or an external display.
struct NotchGeometry {
    let screen: NSScreen
    let hasNotch: Bool
    /// Physical notch size, or a sensible stand-in on notchless displays.
    let notchSize: CGSize
    /// Distance from the top of the screen to the top of the island.
    let topOffset: CGFloat

    static let expandedSize = CGSize(width: 460, height: 190)
    static let peekSize = CGSize(width: 330, height: 44)

    init(screen: NSScreen) {
        self.screen = screen
        let inset = screen.safeAreaInsets.top
        let notched = inset > 0
        hasNotch = notched

        if notched {
            // The notch is whatever the two auxiliary "ears" do not cover.
            let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
            let width = leftWidth > 0 && rightWidth > 0
                ? screen.frame.width - leftWidth - rightWidth
                : 200
            notchSize = CGSize(width: max(160, width), height: inset)
            topOffset = 0
        } else {
            notchSize = CGSize(width: 200, height: 32)
            // Clear the menu bar so the island does not fight with it.
            topOffset = screen.frame.height - screen.visibleFrame.maxY + 4
        }
    }

    /// The window is fixed at the largest size the island can reach; the island
    /// animates inside it. Resizing the window every frame produced visible
    /// tearing, so the window stays still and only the content moves.
    var windowSize: CGSize {
        CGSize(width: Self.expandedSize.width + 80,
               height: Self.expandedSize.height + topOffset + 40)
    }

    var windowOrigin: CGPoint {
        CGPoint(x: screen.frame.midX - windowSize.width / 2,
                y: screen.frame.maxY - windowSize.height)
    }

    static func current() -> NotchGeometry? {
        // Follow the pointer across displays, falling back to the main screen.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return nil }
        return NotchGeometry(screen: screen)
    }
}
