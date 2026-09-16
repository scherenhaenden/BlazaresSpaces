import CoreGraphics
import Foundation

enum GeometryRestorationStrategy: Equatable, Sendable {
    case exactSameTopology
    case normalizedToMatchedDisplay
    case conservativeMainDisplayFallback
}

struct GeometryRestorationPlan: Equatable, Sendable {
    let frame: CGRect
    let displayID: CGDirectDisplayID
    let strategy: GeometryRestorationStrategy
}

enum PersistedDisplayMatch: Equatable, Sendable {
    case unique(DisplaySnapshot)
    case ambiguous([DisplaySnapshot])
    case missing
}

struct DisplayTopologyMapper: Sendable {
    let sizeTolerance: CGFloat
    let scaleTolerance: CGFloat

    init(sizeTolerance: CGFloat = 2, scaleTolerance: CGFloat = 0.05) {
        self.sizeTolerance = sizeTolerance
        self.scaleTolerance = scaleTolerance
    }

    func captureGeometry(frame: CGRect, on display: DisplaySnapshot) -> LogicalWindowGeometry {
        let visible = display.visibleFrame
        let normalized: WindowGeometryRect? = visible.width > 0 && visible.height > 0
            ? WindowGeometryRect(
                x: Double((frame.minX - visible.minX) / visible.width),
                y: Double((frame.minY - visible.minY) / visible.height),
                width: Double(frame.width / visible.width),
                height: Double(frame.height / visible.height)
            )
            : nil
        return LogicalWindowGeometry(
            absolute: WindowGeometryRect(frame),
            normalized: normalized,
            display: descriptor(for: display)
        )
    }

    func descriptor(for display: DisplaySnapshot) -> PersistedDisplayDescriptor {
        PersistedDisplayDescriptor(
            name: display.name,
            frameSize: WindowGeometryRect(display.frame),
            visibleFrameSize: WindowGeometryRect(display.visibleFrame),
            backingScale: Double(display.backingScale),
            wasMain: display.isMain
        )
    }

    func match(_ descriptor: PersistedDisplayDescriptor, among displays: [DisplaySnapshot]) -> PersistedDisplayMatch {
        let ranked = displays.map { ($0, displayScore($0, descriptor: descriptor)) }
            .filter { $0.1 >= 40 }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.id < $1.0.id
            }
        guard let first = ranked.first else { return .missing }
        let tied = ranked.filter { first.1 - $0.1 < 10 }.map(\.0)
        return tied.count == 1 ? .unique(first.0) : .ambiguous(tied)
    }

    func restorationPlan(
        for geometry: LogicalWindowGeometry,
        currentDisplays: [DisplaySnapshot]
    ) -> GeometryRestorationPlan? {
        guard !currentDisplays.isEmpty else { return nil }

        if let descriptor = geometry.display,
           case let .unique(display) = match(descriptor, among: currentDisplays) {
            if isSameTopology(display, descriptor: descriptor) {
                return GeometryRestorationPlan(
                    frame: geometry.absolute.cgRect,
                    displayID: display.id,
                    strategy: .exactSameTopology
                )
            }
            if let normalized = geometry.normalized {
                return GeometryRestorationPlan(
                    frame: conservativeFrame(normalized: normalized, in: display.visibleFrame),
                    displayID: display.id,
                    strategy: .normalizedToMatchedDisplay
                )
            }
        }

        let main = currentDisplays.first(where: \.isMain) ?? currentDisplays[0]
        let frame: CGRect
        if let normalized = geometry.normalized {
            frame = conservativeFrame(normalized: normalized, in: main.visibleFrame)
        } else {
            frame = centeredFrame(size: geometry.absolute.cgRect.size, in: main.visibleFrame)
        }
        return GeometryRestorationPlan(
            frame: frame,
            displayID: main.id,
            strategy: .conservativeMainDisplayFallback
        )
    }

    private func displayScore(_ display: DisplaySnapshot, descriptor: PersistedDisplayDescriptor) -> Int {
        var score = 0
        let oldFrame = descriptor.frameSize.cgRect
        let oldVisible = descriptor.visibleFrameSize.cgRect
        if abs(display.frame.width - oldFrame.width) <= sizeTolerance { score += 20 }
        if abs(display.frame.height - oldFrame.height) <= sizeTolerance { score += 20 }
        if abs(display.visibleFrame.width - oldVisible.width) <= sizeTolerance { score += 10 }
        if abs(display.visibleFrame.height - oldVisible.height) <= sizeTolerance { score += 10 }
        if abs(display.backingScale - CGFloat(descriptor.backingScale)) <= scaleTolerance { score += 10 }
        if display.isMain == descriptor.wasMain { score += 10 }
        if let name = descriptor.name, display.name.caseInsensitiveCompare(name) == .orderedSame { score += 20 }
        return score
    }

    private func isSameTopology(_ display: DisplaySnapshot, descriptor: PersistedDisplayDescriptor) -> Bool {
        approximatelyEqual(display.frame, descriptor.frameSize.cgRect)
            && approximatelyEqual(display.visibleFrame, descriptor.visibleFrameSize.cgRect)
            && abs(display.backingScale - CGFloat(descriptor.backingScale)) <= scaleTolerance
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= sizeTolerance
            && abs(lhs.minY - rhs.minY) <= sizeTolerance
            && abs(lhs.width - rhs.width) <= sizeTolerance
            && abs(lhs.height - rhs.height) <= sizeTolerance
    }

    private func conservativeFrame(normalized: WindowGeometryRect, in visible: CGRect) -> CGRect {
        let requested = CGRect(
            x: visible.minX + CGFloat(normalized.x) * visible.width,
            y: visible.minY + CGFloat(normalized.y) * visible.height,
            width: CGFloat(normalized.width) * visible.width,
            height: CGFloat(normalized.height) * visible.height
        )
        return clamp(requested, to: visible)
    }

    private func centeredFrame(size: CGSize, in visible: CGRect) -> CGRect {
        let fitted = CGSize(width: min(max(size.width, 1), visible.width), height: min(max(size.height, 1), visible.height))
        return CGRect(
            x: visible.midX - fitted.width / 2,
            y: visible.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func clamp(_ frame: CGRect, to visible: CGRect) -> CGRect {
        guard visible.width > 0, visible.height > 0 else { return visible }
        let width = min(max(frame.width, 1), visible.width)
        let height = min(max(frame.height, 1), visible.height)
        let x = min(max(frame.minX, visible.minX), visible.maxX - width)
        let y = min(max(frame.minY, visible.minY), visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

