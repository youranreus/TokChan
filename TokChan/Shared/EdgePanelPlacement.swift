import CoreGraphics

/// All coordinates use AppKit's global, bottom-left-origin screen space.
struct EdgePanelPlacement {
    enum Side { case left, right }

    static let contentSize = CGSize(width: 380, height: 708)
    private(set) var side: Side = .right
    /// Position within the distance the entire panel can travel vertically.
    private var fraction: CGFloat = 0.5

    init() {}

    init(dropPoint: CGPoint, grabAnchor: CGPoint, screen: CGRect) {
        side = dropPoint.x < screen.midX ? .left : .right
        let area = Self.expandedArea(in: screen)
        let size = Self.fittedSize(in: area)
        let travel = area.height - size.height
        let offset = dropPoint.y - grabAnchor.y * size.height - area.minY
        if travel > 0 { fraction = min(1, max(0, offset / travel)) }
    }

    private static func expandedArea(in screen: CGRect) -> CGRect {
        screen.insetBy(dx: min(8, screen.width / 4), dy: min(8, screen.height / 4))
    }

    private static func fittedSize(in area: CGRect) -> CGSize {
        let scale = min(1, area.width / contentSize.width, area.height / contentSize.height)
        return CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    }

    func expandedFrame(in screen: CGRect) -> CGRect {
        let area = Self.expandedArea(in: screen)
        let size = Self.fittedSize(in: area)
        let x = side == .left ? area.minX : area.maxX - size.width
        let y = area.minY + (area.height - size.height) * fraction
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    func frame(in screen: CGRect, reveal: CGFloat, peekWidth: Int = UserPreferences.defaultEdgePeekWidth) -> CGRect {
        let full = expandedFrame(in: screen)
        let exposed = min(CGFloat(peekWidth), full.width)
        let startX = side == .left ? screen.minX - full.width + exposed : screen.maxX - exposed
        let x = startX + (full.minX - startX) * reveal
        return CGRect(x: x, y: full.minY, width: full.width, height: full.height).intersection(screen)
    }

    func contentOrigin(window: CGRect, full: CGRect) -> CGPoint {
        CGPoint(x: side == .left ? window.width - full.width : 0, y: 0)
    }

    /// The cursor may still be on the collapsed edge when the panel finishes sliding away.
    func hoverCorridor(in screen: CGRect) -> CGRect {
        let full = expandedFrame(in: screen)
        let x = side == .left ? screen.minX : full.maxX
        let width = side == .left ? full.minX - x : screen.maxX - x
        return CGRect(x: x, y: full.minY, width: width, height: full.height)
    }
}
