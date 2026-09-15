import CoreGraphics

struct ParkingPositionCalculator: Equatable, Sendable {
    let gap: CGFloat
    let rowSpacing: CGFloat

    init(gap: CGFloat = 120, rowSpacing: CGFloat = 160) {
        self.gap = gap
        self.rowSpacing = rowSpacing
    }

    func topologyBounds(for displays: [DisplaySnapshot]) -> CGRect? {
        guard let first = displays.first else { return nil }
        return displays.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    /// Parks to the right of the union of all displays, with deterministic rows.
    /// It uses topology bounds rather than a fixed global coordinate.
    func parkingFrame(
        slot: Int,
        windowSize: CGSize,
        displays: [DisplaySnapshot]
    ) -> CGRect? {
        guard let bounds = topologyBounds(for: displays), slot >= 0 else { return nil }
        let safeWidth = max(windowSize.width, 1)
        let safeHeight = max(windowSize.height, 1)
        let y = bounds.minY + CGFloat(slot) * max(rowSpacing, safeHeight + gap)
        return CGRect(x: bounds.maxX + gap, y: y, width: safeWidth, height: safeHeight)
    }
}

