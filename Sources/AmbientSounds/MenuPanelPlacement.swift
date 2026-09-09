import Foundation

/// Keep the entire menu panel below its status item, including on secondary screens.
enum MenuPanelPlacement {
    static func origin(
        size: CGSize,
        anchor: CGRect,
        visibleFrame: CGRect,
        lockedOrigin: CGPoint? = nil
    ) -> CGPoint {
        if let lockedOrigin { return lockedOrigin }

        // A status item's symbol can have a different intrinsic image height.
        // Using the button's minY makes the whole panel drift vertically when
        // that symbol changes. The menu bar boundary is stable for the screen,
        // so use it as the panel's vertical reference instead.
        let top = visibleFrame.maxY - 6
        return CGPoint(
            x: max(visibleFrame.minX, min(anchor.midX - size.width / 2, visibleFrame.maxX - size.width)),
            y: max(visibleFrame.minY, top - size.height)
        )
    }
}
