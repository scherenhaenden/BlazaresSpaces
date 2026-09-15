import AppKit
import CoreGraphics
import Foundation

/// Experimental activation through Mission Control's keyboard shortcuts.
/// It never creates, deletes, reorders, or moves windows between Spaces.
struct NativeSpacesController: NativeSpacesControlling {
    private let provider: any NativeSpacesProviding
    private let timeout: TimeInterval

    nonisolated init(provider: any NativeSpacesProviding = SkyLightNativeSpacesProvider(), timeout: TimeInterval = 4.0) {
        self.provider = provider
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
              let currentPosition = bindings.first(where: { $0.spacesByDisplay.values.contains { $0.runtimeID == current.runtimeID } })?.virtualSpacePosition else {
            return .failed("Current native desktop could not be resolved")
        }
        guard let target = bindings.first(where: { $0.virtualSpacePosition == virtualPosition }),
              target.spacesByDisplay[current.displayIdentifier] != nil else {
            return .unavailable("No native desktop exists on active display \(current.displayIdentifier) for Virtual Space \(virtualPosition)")
        }
        let delta = virtualPosition - currentPosition
        if delta == 0 { return .activated }

        let semaphore = DispatchSemaphore(value: 0)
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            // The workspace notification center does not consistently attach
            // the NSWorkspace instance as the notification object across macOS
            // releases. Filtering by object can therefore miss a real switch.
            object: nil,
            // Never enqueue this observer on MainActor: activate() waits for
            // the signal synchronously and would otherwise deadlock the UI.
            queue: nil
        ) { _ in semaphore.signal() }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        guard postControlArrow(delta > 0 ? 124 : 123, count: abs(delta)) else {
            return .failed("Could not post Mission Control shortcut; check Accessibility permission")
        }
        let targetRuntimeID = target.spacesByDisplay[current.displayIdentifier]?.runtimeID
        guard let targetRuntimeID else {
            return .unavailable("Target native desktop has no binding on active display \(current.displayIdentifier)")
        }

        // Notification delivery is the fast path, but polling the public
        // topology snapshot is the reliable confirmation path. Some macOS
        // versions deliver the notification late or without the expected
        // object while Mission Control is animating.
        let deadline = Date().addingTimeInterval(timeout)
        var notificationObserved = false
        while Date() < deadline {
            if semaphore.wait(timeout: .now() + 0.1) == .success {
                notificationObserved = true
            }
            if let refreshed = provider.readTopology().value,
               refreshed.spaces.contains(where: { $0.runtimeID == targetRuntimeID && $0.isCurrent }) {
                return .activated
            }
            if notificationObserved {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        return .failed(notificationObserved
            ? "Native Space changed notification arrived, but target Desktop \(virtualPosition) was not verified"
            : "Native Space transition was not observed before timeout (waited \(timeout)s)")
    }

    private nonisolated func activeDisplayIdentifier(in topology: NativeSpaceTopology) -> String? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }),
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(displayNumber.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        let identifier = CFUUIDCreateString(nil, uuid) as String
        return topology.displays.contains(where: { $0.displayIdentifier == identifier }) ? identifier : nil
    }

    private nonisolated func postControlArrow(_ keyCode: CGKeyCode, count: Int) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return false }
            down.flags = .maskControl
            up.flags = .maskControl
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
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
