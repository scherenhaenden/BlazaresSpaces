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

/// Semantic activation intent for a Virtual Space. Native macOS Spaces are
/// intentionally outside this boundary; the current implementation only
/// chooses between the logical model and the managed-window mechanism.
enum VirtualSpaceActivationMode: Equatable, Sendable {
    case logicalOnly
    case managedWindows
}

enum VirtualSpaceActivationStrategy: Equatable, Sendable {
    case logicalOnly
    case managedWindowSwitch
}

protocol VirtualSpaceActivationStrategyProviding: Sendable {
    func strategy(for mode: VirtualSpaceActivationMode) -> VirtualSpaceActivationStrategy
}

struct LogicalVirtualSpaceActivationAdapter: VirtualSpaceActivationStrategyProviding {
    nonisolated init() {}

    nonisolated func strategy(for mode: VirtualSpaceActivationMode) -> VirtualSpaceActivationStrategy {
        switch mode {
        case .logicalOnly:
            return .logicalOnly
        case .managedWindows:
            return .managedWindowSwitch
        }
    }
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
