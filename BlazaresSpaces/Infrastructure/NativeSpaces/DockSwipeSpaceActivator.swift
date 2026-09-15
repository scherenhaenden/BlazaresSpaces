import CoreGraphics

/// Direction for one native Mission Control Space transition.
nonisolated enum NativeSpaceSwipeDirection: Sendable {
    case left
    case right
}

/// Synthetic Dock swipe backend based on InstantSpaceSwitcher (MIT). These
/// CGEvent fields are undocumented and runtime-sensitive; keep them isolated.
struct DockSwipeSpaceActivator: Sendable {
    private nonisolated enum Field {
        static let eventType = CGEventField(rawValue: 55)!
        static let hidType = CGEventField(rawValue: 110)!
        static let motion = CGEventField(rawValue: 123)!
        static let progress = CGEventField(rawValue: 124)!
        static let velocityX = CGEventField(rawValue: 129)!
        static let velocityY = CGEventField(rawValue: 130)!
        static let phase = CGEventField(rawValue: 132)!
    }

    private nonisolated enum Value {
        static let dockControl: Int64 = 30
        static let dockSwipe: Int64 = 23
        static let horizontal: Int64 = 1
        static let began: Int64 = 1
        static let changed: Int64 = 2
        static let ended: Int64 = 4
    }

    nonisolated init() {}

    @discardableResult
    nonisolated func performSwitchGesture(direction: NativeSpaceSwipeDirection, velocity: Double = 2_000) -> Bool {
        let sign = direction == .right ? 1.0 : -1.0
        let progress = sign * Double.leastNonzeroMagnitude
        let signedVelocity = sign * velocity
        return post(phase: Value.began, progress: progress, velocity: signedVelocity)
            && post(phase: Value.changed, progress: progress, velocity: signedVelocity)
            && post(phase: Value.ended, progress: progress, velocity: signedVelocity)
    }

    private nonisolated func post(phase: Int64, progress: Double, velocity: Double) -> Bool {
        guard let event = CGEvent(source: nil) else { return false }
        event.setIntegerValueField(Field.eventType, value: Value.dockControl)
        event.setIntegerValueField(Field.hidType, value: Value.dockSwipe)
        event.setIntegerValueField(Field.motion, value: Value.horizontal)
        event.setIntegerValueField(Field.phase, value: phase)
        event.setDoubleValueField(Field.progress, value: progress)
        event.setDoubleValueField(Field.velocityX, value: velocity)
        event.setDoubleValueField(Field.velocityY, value: velocity)
        event.post(tap: .cgSessionEventTap)
        return true
    }
}
