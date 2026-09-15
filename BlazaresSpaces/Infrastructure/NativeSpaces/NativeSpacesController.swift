import AppKit
import CoreGraphics
import Foundation

/// Focuses an existing native Space through the public Mission Control
/// keyboard mechanism. It never creates Spaces or moves windows.
struct NativeSpacesController: NativeSpacesControlling {
    private let provider: any NativeSpacesProviding
    private let timeout: TimeInterval

    nonisolated init(provider: any NativeSpacesProviding = SkyLightNativeSpacesProvider(), timeout: TimeInterval = 1.5) {
        self.provider = provider
        self.timeout = timeout
    }

    nonisolated func activate(virtualPosition: Int, topology: NativeSpaceTopology) -> NativeSpaceActivationResult {
        guard virtualPosition > 0 else { return .failed("Virtual Space position must be positive") }
        guard !topology.separateSpaces else { return .unavailable("Native activation requires Displays have separate Spaces to be OFF") }
        let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
        guard let target = bindings.first(where: { $0.virtualSpacePosition == virtualPosition }),
              let targetSpace = target.spacesByDisplay.values.first else {
            return .unavailable("No native desktop binding exists for Virtual Space \(virtualPosition)")
        }
        guard let current = topology.spaces.first(where: { $0.isCurrent && $0.kind == .userDesktop }),
              let currentPosition = bindings.first(where: { $0.spacesByDisplay.values.contains { $0.runtimeID == current.runtimeID } })?.virtualSpacePosition else {
            return .failed("Current native desktop could not be resolved")
        }
        let delta = virtualPosition - currentPosition
        if delta == 0 { return .activated }

        // Register before posting: Mission Control transitions can be fast and
        // the notification carries no destination identity.
        let semaphore = DispatchSemaphore(value: 0)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: queue
        ) { _ in semaphore.signal() }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(token) }

        guard postControlArrow(delta > 0 ? 124 : 123, count: abs(delta)) else {
            return .failed("Could not post Mission Control keyboard event; check Accessibility permission")
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return .failed("Native Space transition was not observed before timeout")
        }
        guard let refreshed = provider.readTopology().get(),
              refreshed.spaces.contains(where: { $0.runtimeID == targetSpace.runtimeID && $0.isCurrent }) else {
            return .failed("Native transition occurred but target desktop could not be verified")
        }
        return .activated
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

private extension Result {
    nonisolated func get() -> Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }
}
