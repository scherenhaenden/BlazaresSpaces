import AppKit
import CoreGraphics
import OSLog

struct DisplayManager {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BlazaresSpaces", category: "DisplayManager")

    func displays() -> [DisplaySnapshot] {
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0

        let snapshots = NSScreen.screens.compactMap { screen -> DisplaySnapshot? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = CGDirectDisplayID(number.uint32Value)
            let frame = CGDisplayBounds(id)
            let visibleFrame = Self.accessibilityFrame(fromAppKitFrame: screen.visibleFrame, primaryHeight: primaryHeight)
            return DisplaySnapshot(
                id: id,
                name: screen.localizedName,
                frame: frame,
                visibleFrame: visibleFrame,
                backingScale: screen.backingScaleFactor,
                isMain: CGDisplayIsMain(id) != 0
            )
        }

        logger.info("Detected \(snapshots.count, privacy: .public) display(s)")
        return snapshots.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
            return lhs.frame.minY < rhs.frame.minY
        }
    }

    static func accessibilityFrame(fromAppKitFrame frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}

