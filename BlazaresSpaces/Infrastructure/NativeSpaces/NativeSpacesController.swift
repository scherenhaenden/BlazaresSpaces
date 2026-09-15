import AppKit
import CoreGraphics
import Foundation

/// Resolves positional native Spaces and delegates physical activation to the
/// Dock swipe backend. Keyboard shortcuts remain a diagnostic fallback.
struct NativeSpacesController: NativeSpacesControlling {
    private let provider: any NativeSpacesProviding
    private let gestureActivator: DockSwipeSpaceActivator
    private let logStore: NativeSpaceLogStore
    private let timeout: TimeInterval

    nonisolated init(provider: any NativeSpacesProviding = SkyLightNativeSpacesProvider(), gestureActivator: DockSwipeSpaceActivator = DockSwipeSpaceActivator(), logStore: NativeSpaceLogStore = NativeSpaceLogStore(), timeout: TimeInterval = 1.5) {
        self.provider = provider
        self.gestureActivator = gestureActivator
        self.logStore = logStore
        self.timeout = timeout
    }

    nonisolated func activate(virtualPosition: Int, topology: NativeSpaceTopology) -> NativeSpaceActivationResult {
        guard virtualPosition > 0 else { return .failed("Virtual Space position must be positive") }
        let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
        let activeDisplayID = activeDisplayIdentifier(in: topology)
        let current = topology.spaces.first {
            $0.isCurrent && $0.kind == .userDesktop && $0.displayIdentifier == activeDisplayID
        } ?? topology.spaces.first(where: { $0.isCurrent && $0.kind == .userDesktop })
        guard let current,
              let currentPosition = bindings.first(where: { binding in
                  binding.spacesByDisplay.values.contains { $0.runtimeID == current.runtimeID }
              })?.virtualSpacePosition else {
            return .failed("Current native desktop could not be resolved")
        }
        guard bindings.contains(where: { $0.virtualSpacePosition == virtualPosition }),
              let targetSpace = bindings.first(where: { $0.virtualSpacePosition == virtualPosition })?.spacesByDisplay[current.displayIdentifier] else {
            return .unavailable("No native desktop exists on active display (current.displayIdentifier) for Virtual Space (virtualPosition)")
        }
        let delta = virtualPosition - currentPosition
        if delta == 0 { return .activated }

        let semaphore = DispatchSemaphore(value: 0)
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in semaphore.signal() }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(token) }

        let direction: NativeSpaceSwipeDirection = delta > 0 ? .right : .left
        let step = delta > 0 ? 1 : -1
        for offset in 1...abs(delta) {
            let nextPosition = currentPosition + offset * step
            guard let nextSpace = bindings.first(where: { $0.virtualSpacePosition == nextPosition })?.spacesByDisplay[current.displayIdentifier] else {
                return .unavailable("Native desktop position " + String(nextPosition) + " is missing on active display " + current.displayIdentifier)
            }
            let progress = (direction == .right ? 1.0 : -1.0) * Double(Float.leastNonzeroMagnitude)
            logStore.append("SWIPE direction=" + String(describing: direction) + " phases=1,2,4 current=" + String(currentPosition) + " next=" + String(nextPosition) + " final=" + String(virtualPosition) + " progress=" + String(progress) + " velocity=" + String(direction == .right ? 2000 : -2000) + " runtime=" + String(nextSpace.runtimeID))
            guard gestureActivator.performSwitchGesture(direction: direction, velocity: 2_000) else {
                return .failed("Could not create native Dock swipe event; check Accessibility permission")
            }
            if waitForTarget(nextSpace.runtimeID, semaphore: semaphore, timeout: timeout) {
                return .activated
            }
        }

        // Diagnostic fallback only: Dock swipe remains the primary mechanism.
        let keyCode: CGKeyCode = delta > 0 ? 124 : 123
        guard postControlArrow(keyCode, count: abs(delta)) else {
            return .failed("Dock swipe was posted but keyboard diagnostic fallback could not be created")
        }
        if waitForTarget(targetSpace.runtimeID, semaphore: semaphore, timeout: timeout) {
            return .activated
        }
        return .failed("Dock swipe was posted, but native Desktop " + String(virtualPosition) + " was not verified")
    }

    private nonisolated func waitForTarget(_ targetRuntimeID: UInt64, semaphore: DispatchSemaphore, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            _ = semaphore.wait(timeout: .now() + 0.1)
            if let refreshed = provider.readTopology().value,
               refreshed.spaces.contains(where: { $0.runtimeID == targetRuntimeID && $0.isCurrent }) {
                return true
            }
        }
        return false
    }

    private nonisolated func activeDisplayIdentifier(in topology: NativeSpaceTopology) -> String? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }),
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(displayNumber.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        let identifier = CFUUIDCreateString(nil, uuid) as String
        return topology.displays.contains(where: { $0.displayIdentifier == identifier }) ? identifier : nil
    }

    private nonisolated func postControlArrow(_ keyCode: CGKeyCode, count: Int) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        for _ in 0..<count {
            guard let controlDown = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: true),
                  let controlUp = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: false),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return false }
            controlDown.post(tap: .cghidEventTap)
            down.flags = .maskControl
            up.flags = .maskControl
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            controlUp.post(tap: .cghidEventTap)
        }
        return true
    }
}

private extension Result where Failure == NativeSpacesReadError {
    nonisolated var value: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }
}
