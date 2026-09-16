import AppKit
import CoreGraphics
import Foundation

/// Global native Space activation. Each physical display is targeted and
/// verified independently; no external windows are moved.
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

    nonisolated func capabilities() -> NativeSpaceCapabilities {
        // Discovery is intentionally reported by the provider. Mutation via
        // synthetic Dock gestures is supported only as an explicit experimental
        // focus path; create/destroy/move remain unavailable.
        switch provider.readTopology() {
        case .success:
            return NativeSpaceCapabilities(discovery: true, create: false, destroy: false, focus: true, moveWindow: false, reasons: ["Focus uses an experimental Dock gesture; topology must be revalidated immediately before use"])
        case let .failure(error):
            return NativeSpaceCapabilities(discovery: false, create: false, destroy: false, focus: false, moveWindow: false, reasons: [String(describing: error)])
        }
    }

    nonisolated func focusSpace(_ space: NativeSpaceDescriptor, topology: NativeSpaceTopology) -> NativeSpaceActivationResult {
        guard topology.spaces.contains(where: { $0.runtimeID == space.runtimeID && $0.kind == .userDesktop }) else {
            return .failed("Refused to focus a stale or non-user native Space")
        }
        guard let position = NativeSpaceTopologyMapper().bindings(for: topology).first(where: { $0.spacesByDisplay.values.contains { $0.runtimeID == space.runtimeID } })?.virtualSpacePosition else {
            return .failed("Native Space has no conservative Virtual Space mapping")
        }
        return activate(virtualPosition: position, topology: topology)
    }

    nonisolated func activate(virtualPosition: Int, topology: NativeSpaceTopology) -> NativeSpaceActivationResult {
        guard virtualPosition > 0 else { return .failed("Virtual Space position must be positive") }
        let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
        guard !topology.displays.isEmpty else { return .failed("No native displays were discovered") }

        let originalCursor = NSEvent.mouseLocation
        defer {
            CGWarpMouseCursorPosition(originalCursor)
            CGAssociateMouseAndMouseCursorPosition(1)
        }

        let semaphore = DispatchSemaphore(value: 0)
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in semaphore.signal() }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(token) }

        var failures: [String] = []
        for display in topology.displays {
            let displaySpaces = topology.spaces.filter { $0.displayIdentifier == display.displayIdentifier && $0.kind == .userDesktop }
            guard let currentSpace = displaySpaces.first(where: { $0.isCurrent }),
                  let currentPosition = bindings.first(where: { $0.spacesByDisplay.values.contains { $0.runtimeID == currentSpace.runtimeID } })?.virtualSpacePosition else {
                failures.append("display \(display.displayIdentifier): current desktop unresolved")
                continue
            }
            guard let targetSpace = bindings.first(where: { $0.virtualSpacePosition == virtualPosition })?.spacesByDisplay[display.displayIdentifier] else {
                failures.append("display \(display.displayIdentifier): target Desktop \(virtualPosition) unavailable")
                continue
            }
            if currentPosition == virtualPosition {
                logStore.append("DISPLAY SUCCESS id=(display.displayIdentifier) current=(currentPosition) target=(virtualPosition) delta=0")
                continue
            }
            guard let center = displayCenter(for: display.displayIdentifier) else {
                failures.append("display (display.displayIdentifier): screen center unavailable")
                continue
            }
            CGWarpMouseCursorPosition(center)
            CGAssociateMouseAndMouseCursorPosition(1)

            let delta = virtualPosition - currentPosition
            let direction: NativeSpaceSwipeDirection = delta > 0 ? .right : .left
            let step = delta > 0 ? 1 : -1
            for offset in 1...abs(delta) {
                let nextPosition = currentPosition + offset * step
                guard let nextSpace = bindings.first(where: { $0.virtualSpacePosition == nextPosition })?.spacesByDisplay[display.displayIdentifier] else {
                failures.append("display " + display.displayIdentifier + ": intermediate Desktop " + String(nextPosition) + " unavailable")
                    break
                }
                let progress = (direction == .right ? 1.0 : -1.0) * Double(Float.leastNonzeroMagnitude)
                let velocity = direction == .right ? 2000 : -2000
                logStore.append("GLOBAL SWIPE display=" + display.displayIdentifier + " frame=" + String(describing: center) + " direction=" + String(describing: direction) + " phase=1,2,4 current=" + String(currentPosition) + " next=" + String(nextPosition) + " final=" + String(virtualPosition) + " progress=" + String(progress) + " velocity=" + String(velocity) + " runtime=" + String(nextSpace.runtimeID))
                guard gestureActivator.performSwitchGesture(direction: direction, velocity: 2_000) else {
                    failures.append("display " + display.displayIdentifier + ": could not post Dock swipe")
                    break
                }
                guard waitForTarget(nextSpace.runtimeID, semaphore: semaphore) else {
                    failures.append("display " + display.displayIdentifier + ": Desktop " + String(nextPosition) + " was not verified")
                    break
                }
            }
            if failures.last?.hasPrefix("display " + display.displayIdentifier + ":") != true {
                logStore.append("DISPLAY SUCCESS id=" + display.displayIdentifier + " current=" + String(currentPosition) + " target=" + String(virtualPosition))
            }
        }

        guard failures.isEmpty else {
            let message = "PARTIAL FAILURE: " + failures.joined(separator: "; ")
            logStore.append("GLOBAL PARTIAL FAILURE target=" + String(virtualPosition) + " details=" + message)
            return .failed(message)
        }

        guard let refreshed = provider.readTopology().value else {
            return .failed("GLOBAL FAILURE: final native topology could not be read")
        }
        let unverified = refreshed.displays.compactMap { display -> String? in
            let spaces = refreshed.spaces.filter { $0.displayIdentifier == display.displayIdentifier && $0.kind == .userDesktop }
            guard let current = spaces.first(where: { $0.isCurrent }),
                  let position = bindings.first(where: { $0.spacesByDisplay.values.contains { $0.runtimeID == current.runtimeID } })?.virtualSpacePosition,
                  position == virtualPosition else { return display.displayIdentifier }
            return nil
        }
        guard unverified.isEmpty else {
            let message = "PARTIAL FAILURE: final positions not verified on " + unverified.joined(separator: ", ")
            logStore.append("GLOBAL PARTIAL FAILURE target=" + String(virtualPosition) + " details=" + message)
            return .failed(message)
        }
        logStore.append("GLOBAL SUCCESS target=" + String(virtualPosition) + " displays=" + String(refreshed.displays.count))
        return .activated
    }

    private nonisolated func waitForTarget(_ runtimeID: UInt64, semaphore: DispatchSemaphore) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            _ = semaphore.wait(timeout: .now() + 0.1)
            if let refreshed = provider.readTopology().value,
               refreshed.spaces.contains(where: { $0.runtimeID == runtimeID && $0.isCurrent }) { return true }
        }
        return false
    }

    private nonisolated func displayCenter(for identifier: String) -> CGPoint? {
        NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue() else { return false }
            return (CFUUIDCreateString(nil, uuid) as String) == identifier || (identifier == "Main" && screen == NSScreen.main)
        }).map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
    }
}

private extension Result where Failure == NativeSpacesReadError {
    nonisolated var value: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }
}
