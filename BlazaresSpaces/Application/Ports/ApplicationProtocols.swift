import CoreGraphics
import Foundation

protocol WindowDiscovering: Sendable {
    func discover(displays: [DisplaySnapshot]) -> WindowDiscoveryResult
}

struct FocusedWindowObservation: Equatable, Sendable {
    let runtimeIdentity: WindowRuntimeIdentity
    let snapshot: WindowSnapshot?
}

protocol FocusedWindowProviding: Sendable {
    /// Read-only. The observation contains the exact runtime identity: PID + AX
    /// identifier (when available) + current AX enumeration index.
    func focusedWindow(displays: [DisplaySnapshot]) -> FocusedWindowObservation?
}

protocol WindowControlling: Sendable {
    func capture(
        _ target: AuthorizedExternalWindow,
        displays: [DisplaySnapshot]
    ) -> Result<WindowSnapshot, ExternalWindowOperationError>

    func restore(
        _ target: AuthorizedExternalWindow,
        requested snapshot: WindowSnapshot
    ) -> WindowRestoreResult

    func park(
        _ target: AuthorizedExternalWindow,
        current snapshot: WindowSnapshot,
        at position: CGPoint
    ) -> WindowRestoreResult

    func recover(
        _ target: AuthorizedExternalWindow,
        requested snapshot: WindowSnapshot,
        displays: [DisplaySnapshot]
    ) -> WindowRestoreResult
}

protocol DisplayTopologyProviding: Sendable {
    func displays() -> [DisplaySnapshot]
}

protocol HotkeyRegistering: AnyObject {
    var isRunning: Bool { get }
    func start(configuration: GlobalShortcutConfiguration, handler: @escaping (GlobalShortcutAction) -> Void)
    func stop()
}

protocol AccessibilityChecking: Sendable {
    var isTrusted: Bool { get }
    func requestAccess() -> Bool
}
