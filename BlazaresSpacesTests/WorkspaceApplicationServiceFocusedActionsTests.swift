import CoreGraphics
import Foundation
import Testing
@testable import BlazaresSpaces

@MainActor
struct WorkspaceApplicationServiceFocusedActionsTests {
    @Test func focusIsReadOnlyAndReportsUnmanagedWindow() {
        let focused = testWindow()
        let service = makeService(focused: focused)
        service.refresh()

        if case let .unmanaged(window) = service.focusedWindowState {
            #expect(window.runtimeIdentity == focused.runtimeIdentity)
        } else {
            #expect(Bool(false), "Focus alone must not enroll a window")
        }
        #expect(service.workspaceManager.allMembers.isEmpty)
    }

    @Test func manageAndMoveAuthorizesAndTargetsExactRuntimeWindow() {
        let focused = testWindow(identifier: "a", index: 0)
        let other = testWindow(identifier: "b", index: 1)
        let provider = TestFocusedWindowProvider(observation: .init(runtimeIdentity: focused.runtimeIdentity, snapshot: focused))
        let service = makeService(provider: provider, windows: [focused, other])
        service.refresh()
        let target = WorkspaceID.workspace2

        #expect(service.manageAndMoveFocusedWindow(to: target))
        #expect(service.workspaceManager.member(for: focused.runtimeIdentity) != nil)
        #expect(service.workspaceManager.member(for: other.runtimeIdentity) == nil)
        #expect(service.workspaceManager.workspaceContaining(focused.runtimeIdentity) == [target])
    }

    @Test func manageAndShowPreservesExistingMembershipsAndStickyCanBeDisabledSafely() {
        let focused = testWindow()
        let service = makeService(focused: focused)
        service.refresh()

        #expect(service.manageAndMoveFocusedWindow(to: .workspace1))
        #expect(service.showFocusedWindow(on: .workspace2))
        #expect(service.workspaceManager.workspaceContaining(focused.runtimeIdentity) == [.workspace1, .workspace2])
        #expect(service.setFocusedWindowSticky(true))

        #expect(service.setFocusedWindowSticky(false))
        #expect(service.workspaceManager.workspaceContaining(focused.runtimeIdentity).isEmpty == false)
        if case let .managed(_, memberships, sticky) = service.focusedWindowState {
            #expect(memberships.isEmpty == false)
            #expect(sticky == false)
        } else {
            #expect(Bool(false))
        }
    }

    @Test func excludedFocusedWindowCannotBeManaged() {
        let focused = testWindow(app: "Citrix Workspace", bundle: "com.citrix.workspace")
        let service = makeService(focused: focused)
        service.refresh()

        if case .excluded = service.focusedWindowState { #expect(true) }
        else { #expect(Bool(false)) }
        #expect(!service.manageAndMoveFocusedWindow(to: .workspace2))
        #expect(service.workspaceManager.allMembers.isEmpty)
    }

    @Test func staleRuntimeIdentityFailsSafely() {
        let original = testWindow(identifier: "old")
        let replacement = testWindow(identifier: "new")
        let provider = TestFocusedWindowProvider(observation: .init(runtimeIdentity: original.runtimeIdentity, snapshot: original))
        let service = makeService(provider: provider)
        service.refresh()
        provider.observation = .init(runtimeIdentity: replacement.runtimeIdentity, snapshot: replacement)

        #expect(!service.manageAndMoveFocusedWindow(to: .workspace2))
        #expect(service.workspaceManager.allMembers.isEmpty)
        if case .stale = service.focusedWindowState { #expect(true) }
        else { #expect(Bool(false)) }
    }

    private func testWindow(
        app: String = "Safe App", bundle: String? = "com.example.safe",
        identifier: String? = "window", pid: pid_t = 42, index: Int = 0
    ) -> WindowSnapshot {
        WindowSnapshot(
            runtimeIdentity: WindowRuntimeIdentity(processIdentifier: pid, accessibilityIdentifier: identifier, enumerationIndex: index),
            applicationName: app, bundleIdentifier: bundle, title: "Test",
            role: "AXWindow", subrole: nil, frame: CGRect(x: 10, y: 10, width: 300, height: 200),
            isMinimized: false, isFullscreen: false, displayID: 1
        )
    }

    private func makeService(focused: WindowSnapshot) -> WorkspaceApplicationService {
        makeService(provider: TestFocusedWindowProvider(observation: .init(runtimeIdentity: focused.runtimeIdentity, snapshot: focused)), windows: [focused])
    }

    private func makeService(provider: TestFocusedWindowProvider, windows: [WindowSnapshot] = []) -> WorkspaceApplicationService {
        WorkspaceApplicationService(
            windowDiscovery: TestWindowDiscovery(windows: windows), focusedWindowProvider: provider,
            windowController: TestWindowController(), displayProvider: TestDisplayProvider(),
            permissionManager: TestPermissionManager(), stateStore: TestStateStore(),
            shortcutManager: TestShortcutManager(), managementPolicy: .developmentDefaults,
            workspaceEngine: WorkspaceSwitchEngine(controller: TestWindowController()), restorationCoordinator: SessionRestorationCoordinator()
        )
    }
}

struct VirtualSpaceActivationStrategyTests {
    @Test func logicalModeUsesLogicalActivationOnly() {
        let adapter = LogicalVirtualSpaceActivationAdapter()
        #expect(adapter.strategy(for: .logicalOnly) == .logicalOnly)
    }

    @Test func managedWindowModeRoutesToCurrentWindowMechanism() {
        let adapter = LogicalVirtualSpaceActivationAdapter()
        #expect(adapter.strategy(for: .managedWindows) == .managedWindowSwitch)
    }
}

private final class TestFocusedWindowProvider: @unchecked Sendable, FocusedWindowProviding {
    var observation: FocusedWindowObservation?
    init(observation: FocusedWindowObservation?) { self.observation = observation }
    func focusedWindow(displays: [DisplaySnapshot]) -> FocusedWindowObservation? { observation }
}

private struct TestWindowDiscovery: WindowDiscovering {
    let windows: [WindowSnapshot]
    func discover(displays: [DisplaySnapshot]) -> WindowDiscoveryResult { .init(windows: windows, issues: []) }
}

private struct TestDisplayProvider: DisplayTopologyProviding {
    func displays() -> [DisplaySnapshot] { [DisplaySnapshot(id: 1, name: "Test", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), backingScale: 1, isMain: true)] }
}

private struct TestPermissionManager: AccessibilityChecking {
    var isTrusted: Bool { true }
    func requestAccess() -> Bool { true }
}

private final class TestShortcutManager: NSObject, HotkeyRegistering {
    private(set) var isRunning = false
    func start(configuration: GlobalShortcutConfiguration, handler: @escaping (GlobalShortcutAction) -> Void) { isRunning = true }
    func stop() { isRunning = false }
}

private actor TestStateStore: WorkspaceStatePersisting {
    func load() async -> WorkspaceStateLoadResult { .missing }
    func save(_ state: PersistedStateV1) async -> WorkspaceStateSaveResult { .saved(file: URL(fileURLWithPath: "/tmp/test-state.json")) }
    func reset() async -> Result<Void, WorkspacePersistenceError> { .success(()) }
}

private struct TestWindowController: WindowControlling {
    func capture(_ target: AuthorizedExternalWindow, displays: [DisplaySnapshot]) -> Result<WindowSnapshot, ExternalWindowOperationError> { .success(target.snapshot) }
    func restore(_ target: AuthorizedExternalWindow, requested snapshot: WindowSnapshot) -> WindowRestoreResult { .init(id: target.runtimeIdentity, applicationName: target.applicationName, processIdentifier: target.processIdentifier, requestedFrame: snapshot.frame, actualFrame: snapshot.frame, status: .restoredExactly, message: "ok") }
    func park(_ target: AuthorizedExternalWindow, current snapshot: WindowSnapshot, at position: CGPoint) -> WindowRestoreResult { .init(id: target.runtimeIdentity, applicationName: target.applicationName, processIdentifier: target.processIdentifier, requestedFrame: snapshot.frame, actualFrame: snapshot.frame, status: .restoredExactly, message: "ok") }
    func recover(_ target: AuthorizedExternalWindow, requested snapshot: WindowSnapshot, displays: [DisplaySnapshot]) -> WindowRestoreResult { restore(target, requested: snapshot) }
}
