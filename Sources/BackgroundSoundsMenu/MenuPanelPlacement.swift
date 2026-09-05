import Foundation

/// Keep the entire menu panel below its status item, including on secondary screens.
enum MenuPanelPlacement {
    static func origin(size: CGSize, anchor: CGRect, visibleFrame: CGRect) -> CGPoint {
        let top = min(anchor.minY, visibleFrame.maxY) - 6
        return CGPoint(
            x: max(visibleFrame.minX, min(anchor.midX - size.width / 2, visibleFrame.maxX - size.width)),
            y: max(visibleFrame.minY, top - size.height)
        )
    }
}
