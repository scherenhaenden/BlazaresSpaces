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
    case nativeSpacesExperimental
}

enum VirtualSpaceActivationStrategy: Equatable, Sendable {
    case logicalOnly
    case managedWindowSwitch
    case nativeSpacesExperimental
}

protocol VirtualSpaceActivationStrategyProviding: Sendable {
    func strategy(for mode: VirtualSpaceActivationMode) -> VirtualSpaceActivationStrategy
}

enum NativeSpaceActivationResult: Equatable, Sendable {
    case activated
    case unavailable(String)
    case failed(String)
}

protocol NativeSpacesControlling: Sendable {
    nonisolated func activate(virtualPosition: Int, topology: NativeSpaceTopology) -> NativeSpaceActivationResult
    nonisolated func capabilities() -> NativeSpaceCapabilities
    nonisolated func createSpace(on displayIdentifier: String) -> Result<NativeSpaceDescriptor, NativeSpaceOperationError>
    nonisolated func destroySpace(_ space: NativeSpaceDescriptor, confirmedOwnedByBlazaresSpaces: Bool) -> Result<Void, NativeSpaceOperationError>
    nonisolated func focusSpace(_ space: NativeSpaceDescriptor, topology: NativeSpaceTopology) -> NativeSpaceActivationResult
    nonisolated func moveWindow(_ window: WindowRuntimeIdentity, to space: NativeSpaceDescriptor, topology: NativeSpaceTopology) -> Result<Void, NativeSpaceOperationError>
}

extension NativeSpacesControlling {
    nonisolated func capabilities() -> NativeSpaceCapabilities { .unavailable }
    nonisolated func createSpace(on displayIdentifier: String) -> Result<NativeSpaceDescriptor, NativeSpaceOperationError> {
        .failure(.unavailable("Native Space creation is not implemented safely on this macOS release"))
    }
    nonisolated func destroySpace(_ space: NativeSpaceDescriptor, confirmedOwnedByBlazaresSpaces: Bool) -> Result<Void, NativeSpaceOperationError> {
        guard confirmedOwnedByBlazaresSpaces else { return .failure(.unsafe("Refused to destroy an unowned native Space")) }
        return .failure(.unavailable("Native Space destruction is disabled until ownership can be verified"))
    }
    nonisolated func focusSpace(_ space: NativeSpaceDescriptor, topology: NativeSpaceTopology) -> NativeSpaceActivationResult {
        .unavailable("Native Space focus is unavailable")
    }
    nonisolated func moveWindow(_ window: WindowRuntimeIdentity, to space: NativeSpaceDescriptor, topology: NativeSpaceTopology) -> Result<Void, NativeSpaceOperationError> {
        .failure(.unavailable("Native window movement is unavailable until the private ABI is verified"))
    }
}

struct LogicalVirtualSpaceActivationAdapter: VirtualSpaceActivationStrategyProviding {
    nonisolated init() {}

    nonisolated func strategy(for mode: VirtualSpaceActivationMode) -> VirtualSpaceActivationStrategy {
        switch mode {
        case .logicalOnly:
            return .logicalOnly
        case .managedWindows:
            return .managedWindowSwitch
        case .nativeSpacesExperimental:
            return .nativeSpacesExperimental
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
