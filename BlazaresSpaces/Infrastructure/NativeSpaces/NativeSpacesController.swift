import AppKit
import CoreGraphics
import Foundation

/// Experimental activation through Mission Control's keyboard shortcuts.
/// It never creates, deletes, reorders, or moves windows between Spaces.
struct NativeSpacesController: NativeSpacesControlling {
    private let provider: any NativeSpacesProviding
    private let timeout: TimeInterval

    nonisolated init(provider: any NativeSpacesProviding = SkyLightNativeSpacesProvider(), timeout: TimeInterval = 1.5) {
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
            object: NSWorkspace.shared,
            // Never enqueue this observer on MainActor: activate() waits for
            // the signal synchronously and would otherwise deadlock the UI.
            queue: nil
        ) { _ in semaphore.signal() }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        guard postControlArrow(delta > 0 ? 124 : 123, count: abs(delta)) else {
            return .failed("Could not post Mission Control shortcut; check Accessibility permission")
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return .failed("Native Space transition was not observed before timeout")
        }
        guard let refreshed = provider.readTopology().value else {
            return .failed("Transition occurred but the target native Space was not verified")
        }
        let targetRuntimeID = target.spacesByDisplay[current.displayIdentifier]?.runtimeID
        guard let targetRuntimeID,
              refreshed.spaces.contains(where: { $0.runtimeID == targetRuntimeID && $0.isCurrent }) else {
            return .failed("Transition occurred but the target native Space was not verified on display \(current.displayIdentifier)")
        }
        return .activated
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
