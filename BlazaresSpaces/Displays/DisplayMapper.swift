import CoreGraphics

enum DisplayMapper {
    /// Chooses the display containing the largest part of the window. A window with no
    /// intersection is assigned to the display nearest its center.
    static func displayID(for windowFrame: CGRect, among displays: [DisplaySnapshot]) -> CGDirectDisplayID? {
        guard !displays.isEmpty else { return nil }

        let overlaps = displays.map { display in
            (display.id, windowFrame.intersection(display.frame).area)
        }
        if let best = overlaps.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return best.0
        }

        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return displays.min { lhs, rhs in
            lhs.frame.squaredDistance(to: center) < rhs.frame.squaredDistance(to: center)
        }?.id
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return width * height
    }

    func squaredDistance(to point: CGPoint) -> CGFloat {
        let dx = max(minX - point.x, 0, point.x - maxX)
        let dy = max(minY - point.y, 0, point.y - maxY)
        return dx * dx + dy * dy
    }
}

