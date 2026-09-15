import CoreGraphics

enum DisplayMapper {
    /// Chooses the display containing the largest part of the window. A window with no
    /// intersection is assigned to the display nearest its center.
    static func displayID(for windowFrame: CGRect, among displays: [DisplaySnapshot]) -> CGDirectDisplayID? {
        guard !displays.isEmpty else { return nil }

        var bestIndex = 0
        var bestArea: CGFloat = 0
        for (index, display) in displays.enumerated() {
            let area = windowFrame.intersection(display.frame).area
            // Keep the first display on a tie. DisplayManager supplies a stable order.
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        if bestArea > 0 {
            return displays[bestIndex].id
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
