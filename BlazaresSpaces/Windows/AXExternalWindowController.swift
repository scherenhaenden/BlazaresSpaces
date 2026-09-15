import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// AX write path for an explicitly authorized external window. It never accepts
/// a discovered-window collection and never falls back to a similar window.
struct AXExternalWindowController {
    let policy: WindowManagementPolicy
    let frameTolerance: CGFloat

    init(policy: WindowManagementPolicy = .developmentDefaults, frameTolerance: CGFloat = 2) {
        self.policy = policy
        self.frameTolerance = frameTolerance
    }

    func capture(
        _ target: AuthorizedExternalWindow,
        displays: [DisplaySnapshot]
    ) -> Result<WindowSnapshot, ExternalWindowOperationError> {
        guard policy.exclusionReason(for: target.snapshot) == nil else { return .failure(.unsupported("Window became excluded by policy.")) }
        let element: AXUIElement
        switch locate(target) {
        case let .success(found): element = found
        case let .failure(error): return .failure(error)
        }
        guard let frame = readFrame(of: element) else { return .failure(.unsupported("The selected window does not expose a readable frame.")) }

        return .success(WindowSnapshot(
            runtimeIdentity: target.snapshot.runtimeIdentity,
            applicationName: target.snapshot.applicationName,
            bundleIdentifier: target.snapshot.bundleIdentifier,
            title: stringAttribute(kAXTitleAttribute, of: element),
            role: stringAttribute(kAXRoleAttribute, of: element) ?? target.snapshot.role,
            subrole: stringAttribute(kAXSubroleAttribute, of: element),
            frame: frame,
            isMinimized: boolAttribute(kAXMinimizedAttribute, of: element),
            isFullscreen: boolAttribute("AXFullScreen", of: element),
            displayID: DisplayMapper.displayID(for: frame, among: displays)
        ))
    }

    func restore(
        _ target: AuthorizedExternalWindow,
        requested snapshot: WindowSnapshot
    ) -> WindowRestoreResult {
        let base = WindowRestoreResult(
            id: target.runtimeIdentity,
            applicationName: target.applicationName,
            processIdentifier: target.processIdentifier,
            requestedFrame: snapshot.frame,
            actualFrame: nil,
            status: .failed,
            message: "Restore did not run."
        )

        guard policy.exclusionReason(for: target.snapshot) == nil else {
            return WindowRestoreResult(base, status: .excluded, message: "Excluded by the active window-management policy.")
        }
        guard target.runtimeIdentity == snapshot.runtimeIdentity else {
            return WindowRestoreResult(base, status: .windowChanged, message: "Requested snapshot identity differs from the authorized target.")
        }
        let element: AXUIElement
        switch locate(target) {
        case let .success(found): element = found
        case let .failure(error): return result(base, for: error)
        }

        guard snapshot.isMinimized != true, snapshot.isFullscreen != true,
              boolAttribute(kAXMinimizedAttribute, of: element) != true,
              boolAttribute("AXFullScreen", of: element) != true else {
            return WindowRestoreResult(base, status: .unsupported, message: "Minimized and fullscreen windows are not mutated by the workspace experiment.")
        }

        // Size first, then position: the final position is applied after any
        // application geometry constraints have been handled by the resize.
        switch setSize(snapshot.frame.size, on: element) {
        case let .failure(error): return result(base, for: error)
        case .success: break
        }
        switch setPosition(snapshot.frame.origin, on: element) {
        case let .failure(error): return result(base, for: error)
        case .success: break
        }

        guard let actualFrame = readFrame(of: element) else {
            return WindowRestoreResult(base, status: .failed, message: "AX accepted the request but the resulting frame could not be read.")
        }
        let exact = WindowFrameComparison.isWithinTolerance(
            requested: snapshot.frame,
            actual: actualFrame,
            tolerance: frameTolerance
        )
        return WindowRestoreResult(
            base,
            actualFrame: actualFrame,
            status: exact ? .restoredExactly : .restoredWithAdjustment,
            message: exact ? "Requested frame verified after restore." : "AX restored a different frame; the actual result is reported."
        )
    }

    /// Recovery-only restore that avoids blindly writing a frame on a display
    /// which is no longer connected. Normal workspace switching remains strict.
    func recover(
        _ target: AuthorizedExternalWindow,
        requested snapshot: WindowSnapshot,
        displays: [DisplaySnapshot]
    ) -> WindowRestoreResult {
        let safeSnapshot = snapshot.recoveryAdjusted(to: displays)
        var result = restore(target, requested: safeSnapshot)
        if safeSnapshot.frame != snapshot.frame {
            result = WindowRestoreResult(
                id: result.id,
                applicationName: result.applicationName,
                processIdentifier: result.processIdentifier,
                requestedFrame: snapshot.frame,
                actualFrame: result.actualFrame,
                status: result.status,
                message: "Original display topology is unavailable; recovery used the main visible display. \(result.message)"
            )
        }
        return result
    }

    func park(
        _ target: AuthorizedExternalWindow,
        current snapshot: WindowSnapshot,
        at position: CGPoint
    ) -> WindowRestoreResult {
        let requestedFrame = CGRect(origin: position, size: snapshot.frame.size)
        let base = WindowRestoreResult(
            id: target.runtimeIdentity,
            applicationName: target.applicationName,
            processIdentifier: target.processIdentifier,
            requestedFrame: requestedFrame,
            actualFrame: nil,
            status: .failed,
            message: "Parking did not run."
        )
        guard policy.exclusionReason(for: target.snapshot) == nil else {
            return WindowRestoreResult(base, status: .excluded, message: "Excluded by the active window-management policy.")
        }
        guard snapshot.isMinimized != true, snapshot.isFullscreen != true else {
            return WindowRestoreResult(base, status: .unsupported, message: "Minimized and fullscreen windows are not parked by the workspace experiment.")
        }

        let element: AXUIElement
        switch locate(target) {
        case let .success(found): element = found
        case let .failure(error): return result(base, for: error)
        }
        guard boolAttribute(kAXMinimizedAttribute, of: element) != true,
              boolAttribute("AXFullScreen", of: element) != true else {
            return WindowRestoreResult(base, status: .unsupported, message: "The selected window became minimized or fullscreen.")
        }

        switch setPosition(position, on: element) {
        case let .failure(error): return result(base, for: error)
        case .success: break
        }
        guard let actualFrame = readFrame(of: element) else {
            return WindowRestoreResult(base, status: .failed, message: "AX accepted parking but the resulting frame could not be read.")
        }
        let exact = WindowFrameComparison.isWithinTolerance(requested: requestedFrame, actual: actualFrame, tolerance: frameTolerance)
        return WindowRestoreResult(
            base,
            actualFrame: actualFrame,
            status: exact ? .restoredExactly : .restoredWithAdjustment,
            message: exact ? "Parking frame verified." : "The application adjusted the parking frame."
        )
    }

    private func locate(_ target: AuthorizedExternalWindow) -> Result<AXUIElement, ExternalWindowOperationError> {
        let identity = target.runtimeIdentity
        guard let application = NSRunningApplication(processIdentifier: identity.processIdentifier), !application.isTerminated else {
            return .failure(.windowMissing)
        }
        if let expectedBundle = target.snapshot.bundleIdentifier, application.bundleIdentifier != expectedBundle {
            return .failure(.windowChanged)
        }

        let appElement = AXUIElementCreateApplication(identity.processIdentifier)
        var rawWindows: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawWindows)
        guard windowsError == .success else {
            switch windowsError {
            case .apiDisabled: return .failure(.permissionDenied)
            case .cannotComplete, .noValue: return .failure(.windowMissing)
            default: return .failure(.axFailure(operation: "Read selected application windows", axError: windowsError))
            }
        }
        guard let elements = rawWindows as? [AXUIElement] else { return .failure(.windowMissing) }

        // Selection requires an AX identifier. Never fall back to enumeration
        // order or title matching after a window has been selected.
        guard let expectedIdentifier = identity.accessibilityIdentifier, !expectedIdentifier.isEmpty else {
            return .failure(.unsupported("The selected window has no usable AX runtime identifier."))
        }
        let matches = elements.filter { element in
            stringAttribute(kAXRoleAttribute, of: element) == kAXWindowRole
                && stringAttribute(kAXIdentifierAttribute, of: element) == expectedIdentifier
        }
        guard !matches.isEmpty else { return .failure(.windowMissing) }
        guard matches.count == 1, let match = matches.first else {
            return .failure(.unsupported("The AX runtime identifier is not unique; refusing to choose a window."))
        }
        return .success(match)
    }

    private func setPosition(_ position: CGPoint, on element: AXUIElement) -> Result<Void, ExternalWindowOperationError> {
        var value = position
        guard let axValue = withUnsafePointer(to: &value, { AXValueCreate(.cgPoint, $0) }) else {
            return .failure(.unsupported("Could not create an AX position value."))
        }
        let error = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue)
        return errorResult(error, operation: "Set position")
    }

    private func setSize(_ size: CGSize, on element: AXUIElement) -> Result<Void, ExternalWindowOperationError> {
        var value = size
        guard let axValue = withUnsafePointer(to: &value, { AXValueCreate(.cgSize, $0) }) else {
            return .failure(.unsupported("Could not create an AX size value."))
        }
        let error = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axValue)
        return errorResult(error, operation: "Set size")
    }

    private func errorResult(_ error: AXError, operation: String) -> Result<Void, ExternalWindowOperationError> {
        switch error {
        case .success: return .success(())
        case .apiDisabled, .cannotComplete: return .failure(.permissionDenied)
        case .attributeUnsupported: return .failure(.unsupported("The selected window does not support this operation."))
        default: return .failure(.axFailure(operation: operation, axError: error))
        }
    }

    private func result(_ base: WindowRestoreResult, for error: ExternalWindowOperationError) -> WindowRestoreResult {
        switch error {
        case .windowMissing: return WindowRestoreResult(base, status: .windowMissing, message: error.localizedDescription)
        case .windowChanged: return WindowRestoreResult(base, status: .windowChanged, message: error.localizedDescription)
        case .unsupported: return WindowRestoreResult(base, status: .unsupported, message: error.localizedDescription)
        case .permissionDenied: return WindowRestoreResult(base, status: .permissionDenied, message: error.localizedDescription)
        case .axFailure: return WindowRestoreResult(base, status: .failed, message: error.localizedDescription)
        }
    }

    private func readFrame(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute, of: element),
              let size = sizeAttribute(kAXSizeAttribute, of: element) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? { attribute(name, of: element) as? String }
    private func boolAttribute(_ name: String, of element: AXUIElement) -> Bool? { attribute(name, of: element) as? Bool }

    private func pointAttribute(_ name: String, of element: AXUIElement) -> CGPoint? {
        guard let rawValue = attribute(name, of: element), CFGetTypeID(rawValue) == AXValueGetTypeID() else { return nil }
        let value = rawValue as! AXValue
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func sizeAttribute(_ name: String, of element: AXUIElement) -> CGSize? {
        guard let rawValue = attribute(name, of: element), CFGetTypeID(rawValue) == AXValueGetTypeID() else { return nil }
        let value = rawValue as! AXValue
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }
}

extension WindowSnapshot {
    func recoveryAdjusted(to displays: [DisplaySnapshot]) -> WindowSnapshot {
        guard let display = displays.first(where: { $0.frame.intersects(frame) })
                ?? displays.first(where: { $0.isMain })
                ?? displays.first else { return self }
        guard display.frame.intersects(frame) else {
            let visible = display.visibleFrame
            let width = min(frame.width, visible.width)
            let height = min(frame.height, visible.height)
            let adjusted = CGRect(
                x: visible.minX + max(0, (visible.width - width) / 2),
                y: visible.minY + max(0, (visible.height - height) / 2),
                width: width,
                height: height
            )
            return WindowSnapshot(
                runtimeIdentity: runtimeIdentity,
                applicationName: applicationName,
                bundleIdentifier: bundleIdentifier,
                title: title,
                role: role,
                subrole: subrole,
                frame: adjusted,
                isMinimized: isMinimized,
                isFullscreen: isFullscreen,
                displayID: display.id
            )
        }
        return self
    }
}

private extension WindowRestoreResult {
    init(_ base: WindowRestoreResult, actualFrame: CGRect? = nil, status: WindowRestoreStatus, message: String) {
        self.init(id: base.id, applicationName: base.applicationName, processIdentifier: base.processIdentifier, requestedFrame: base.requestedFrame, actualFrame: actualFrame, status: status, message: message)
    }
}
