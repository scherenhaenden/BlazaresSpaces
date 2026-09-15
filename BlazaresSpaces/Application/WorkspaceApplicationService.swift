import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog

/// Application-level coordinator / facade for BlazaresSpaces.
///
/// Encapsulates application use cases and orchestrates domain logic,
/// persistence, display topology, window discovery, and window control.
/// UI components (e.g. DiagnosticsViewModel or SwiftUI Views) delegate user intent
/// here and observe published application state.
@MainActor
final class WorkspaceApplicationService: ObservableObject {
    enum FocusedWindowState: Equatable, Sendable {
        case none
        case unmanaged(WindowSnapshot)
        case managed(WindowSnapshot, memberships: Set<WorkspaceID>, sticky: Bool)
        case excluded(WindowSnapshot, reason: String)
        case stale(WindowRuntimeIdentity)
        case unavailable(String)
    }

    @Published private(set) var accessibilityGranted = false
    @Published private(set) var displays: [DisplaySnapshot] = []
    @Published private(set) var windows: [WindowSnapshot] = []
    @Published private(set) var issues: [WindowDiscoveryIssue] = []
    @Published private(set) var lastRefresh: Date?

    @Published private(set) var workspaceManager = WorkspaceManager()
    @Published private(set) var experimentalWorkspaceModeEnabled = false
    @Published private(set) var workspaceSwitchResult: WorkspaceSwitchResult?
    @Published private(set) var workspaceSwitchState: WorkspaceSwitchState = .idle
    @Published private(set) var workspaceTopologyChanged = false
    @Published private(set) var globalShortcutsEnabled = false
    @Published private(set) var shortcutConfiguration = GlobalShortcutConfiguration()
    @Published private(set) var persistenceStatus: SessionPersistenceStatus = .loading
    @Published private(set) var restorationItems: [RestorationReviewItem] = []
    @Published private(set) var actionStatus: String?
    @Published private(set) var restoreReport: WindowRestoreReport?
    @Published private(set) var focusedWindowState: FocusedWindowState = .none

    let windowDiscovery: any WindowDiscovering
    let focusedWindowProvider: any FocusedWindowProviding
    let activationStrategyProvider: any VirtualSpaceActivationStrategyProviding
    let windowController: any WindowControlling
    let displayProvider: any DisplayTopologyProviding
    let permissionManager: any AccessibilityChecking
    let stateStore: any WorkspaceStatePersisting
    let shortcutManager: any HotkeyRegistering
    @Published private(set) var managementPolicy: WindowManagementPolicy
    let workspaceEngine: WorkspaceSwitchEngine
    let restorationCoordinator: SessionRestorationCoordinator

    private var persistedState: PersistedStateV1?
    private var switchQueue = WorkspaceSwitchRequestQueue()
    private var hasCompletedInitialRefresh = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BlazaresSpaces", category: "ApplicationService")

    convenience init() {
        self.init(
            windowDiscovery: AXWindowDiscovery(),
            focusedWindowProvider: AXFocusedWindowProvider(),
            windowController: AXExternalWindowController(),
            displayProvider: DisplayManager(),
            permissionManager: AccessibilityPermissionManager(),
            stateStore: AtomicJSONWorkspaceStateStore(),
            shortcutManager: GlobalShortcutManager(),
            managementPolicy: WindowManagementPolicyStore().load(),
            workspaceEngine: WorkspaceSwitchEngine(),
            restorationCoordinator: SessionRestorationCoordinator(),
            activationStrategyProvider: LogicalVirtualSpaceActivationAdapter()
        )
    }

    init(
        windowDiscovery: any WindowDiscovering,
        focusedWindowProvider: any FocusedWindowProviding,
        windowController: any WindowControlling,
        displayProvider: any DisplayTopologyProviding,
        permissionManager: any AccessibilityChecking,
        stateStore: any WorkspaceStatePersisting,
        shortcutManager: any HotkeyRegistering,
        managementPolicy: WindowManagementPolicy,
        workspaceEngine: WorkspaceSwitchEngine,
        restorationCoordinator: SessionRestorationCoordinator,
        activationStrategyProvider: any VirtualSpaceActivationStrategyProviding = LogicalVirtualSpaceActivationAdapter()
    ) {
        self.windowDiscovery = windowDiscovery
        self.focusedWindowProvider = focusedWindowProvider
        self.activationStrategyProvider = activationStrategyProvider
        self.windowController = windowController
        self.displayProvider = displayProvider
        self.permissionManager = permissionManager
        self.stateStore = stateStore
        self.shortcutManager = shortcutManager
        self.managementPolicy = managementPolicy
        self.workspaceEngine = workspaceEngine
        self.restorationCoordinator = restorationCoordinator

        Task { @MainActor [weak self] in
            await self?.loadPersistedState()
        }
    }

    // MARK: - Lifecycle & Diagnostics

    func refresh() {
        let previousDisplays = displays
        accessibilityGranted = permissionManager.isTrusted
        displays = displayProvider.displays()

        if hasCompletedInitialRefresh && !previousDisplays.isEmpty && previousDisplays != displays {
            workspaceTopologyChanged = true
            workspaceSwitchState = .degraded(message: "Display topology changed; switching is paused until recovery or refresh validation.")
            actionStatus = "Display topology changed. Review the topology and use Recover Managed Windows before switching again."
        } else if hasCompletedInitialRefresh && workspaceTopologyChanged {
            // A second stable read validates that the display configuration has
            // settled. This only clears the safety latch when no managed window
            // is parked; it never performs window mutation.
            let hasParkedWindows = workspaceManager.allMembers.contains(where: \.isParked)
            let topologyPause: Bool = {
                guard case let .degraded(message) = workspaceSwitchState else { return false }
                return message.localizedCaseInsensitiveContains("topology")
            }()
            if topologyPause && !hasParkedWindows {
                workspaceTopologyChanged = false
                if workspaceSwitchState.isDegraded {
                    workspaceSwitchState = .idle
                }
                actionStatus = "Display topology validated. Switching is available again."
            }
        }

        if accessibilityGranted {
            let result = windowDiscovery.discover(displays: displays)
            windows = result.windows
            issues = result.issues
            refreshFocusedWindow()
            evaluateRestoration()
        } else {
            windows = []
            issues = []
            focusedWindowState = .unavailable("Accessibility permission is unavailable.")
            shortcutManager.stop()
            globalShortcutsEnabled = false
            if experimentalWorkspaceModeEnabled {
                workspaceSwitchState = .degraded(message: "Accessibility permission is unavailable.")
                actionStatus = "Accessibility permission is unavailable; AX mutations are paused. Re-enable it in System Settings."
            }
        }
        if accessibilityGranted && !globalShortcutsEnabled && shortcutConfiguration.enabled {
            startGlobalShortcuts()
        }
        lastRefresh = Date()
        hasCompletedInitialRefresh = true
    }

    // MARK: - Focused Window Quick Actions

    func refreshFocusedWindow() {
        guard accessibilityGranted else {
            focusedWindowState = .unavailable("Accessibility permission is unavailable.")
            return
        }
        guard let observation = focusedWindowProvider.focusedWindow(displays: displays),
              observation.runtimeIdentity.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            if case let .unmanaged(previous) = focusedWindowState { focusedWindowState = .stale(previous.runtimeIdentity) }
            else if case let .managed(previous, _, _) = focusedWindowState { focusedWindowState = .stale(previous.runtimeIdentity) }
            else if case let .excluded(previous, _) = focusedWindowState { focusedWindowState = .stale(previous.runtimeIdentity) }
            else { focusedWindowState = .none }
            return
        }
        guard let focused = observation.snapshot ?? windows.first(where: { $0.runtimeIdentity == observation.runtimeIdentity }) else {
            focusedWindowState = .stale(observation.runtimeIdentity)
            return
        }
        focusedWindowState = state(for: focused)
    }

    private func state(for window: WindowSnapshot) -> FocusedWindowState {
        if let reason = managementPolicy.exclusionReason(for: window) {
            return .excluded(window, reason: reason)
        }
        guard let member = workspaceManager.member(for: window.runtimeIdentity) else {
            return .unmanaged(window)
        }
        return .managed(window, memberships: member.workspaceIDs, sticky: member.visibleOnAllWorkspaces)
    }

    private func exactFocusedWindowForAction() -> WindowSnapshot? {
        let state = focusedWindowState
        let identity: WindowRuntimeIdentity
        switch state {
        case let .unmanaged(window), let .managed(window, _, _), let .excluded(window, _): identity = window.runtimeIdentity
        default: return nil
        }
        if let current = focusedWindowProvider.focusedWindow(displays: displays) {
            guard current.runtimeIdentity == identity else {
                focusedWindowState = .stale(identity)
                actionStatus = "The focused window changed; no action was performed."
                return nil
            }
            return current.snapshot ?? windows.first(where: { $0.runtimeIdentity == identity })
        }
        guard let discovered = windows.first(where: { $0.runtimeIdentity == identity }) else {
            focusedWindowState = .stale(identity)
            actionStatus = "The focused window is stale; no action was performed."
            return nil
        }
        return discovered
    }

    @discardableResult
    func manageAndMoveFocusedWindow(to workspaceID: WorkspaceID) -> Bool {
        manageAndAssignFocusedWindow(to: workspaceID, move: true)
    }

    @discardableResult
    func manageAndShowFocusedWindow(on workspaceID: WorkspaceID) -> Bool {
        manageAndAssignFocusedWindow(to: workspaceID, move: false)
    }

    @discardableResult
    private func manageAndAssignFocusedWindow(to workspaceID: WorkspaceID, move: Bool) -> Bool {
        guard let window = exactFocusedWindowForAction(), workspaceManager.workspaceIDs.contains(workspaceID) else { return false }
        guard case let .success(authorized) = WindowAuthorization.authorize(window, policy: managementPolicy) else {
            focusedWindowState = state(for: window)
            actionStatus = "This focused window is excluded or has no safe runtime identity."
            return false
        }
        let member = workspaceManager.member(for: authorized.runtimeIdentity)
            ?? WorkspaceMember(authorizedWindow: authorized, logicalSnapshot: window)
        if move { workspaceManager.moveToWorkspace(member, workspaceID: workspaceID) }
        else { workspaceManager.addToWorkspace(member, workspaceID: workspaceID) }
        persistAuthoritativeState()
        focusedWindowState = state(for: window)
        actionStatus = move ? "Managed and moved \(window.applicationName)." : "Managed and showed \(window.applicationName)."
        return true
    }

    @discardableResult
    func moveFocusedWindow(to workspaceID: WorkspaceID) -> Bool {
        guard let window = exactFocusedWindowForAction(), isManaged(window) else { return false }
        assignWindow(window, to: workspaceID, move: true)
        focusedWindowState = state(for: window)
        return true
    }

    @discardableResult
    func showFocusedWindow(on workspaceID: WorkspaceID) -> Bool {
        guard let window = exactFocusedWindowForAction(), isManaged(window) else { return false }
        assignWindow(window, to: workspaceID, move: false)
        focusedWindowState = state(for: window)
        return true
    }

    @discardableResult
    func setFocusedWindowSticky(_ visible: Bool) -> Bool {
        guard let window = exactFocusedWindowForAction(), isManaged(window) else { return false }
        guard let member = workspaceManager.member(for: window.runtimeIdentity) else { return false }
        if !visible && member.workspaceIDs.isEmpty {
            workspaceManager.addToWorkspace(member, workspaceID: workspaceManager.activeWorkspaceID)
        }
        setWindowVisibleOnAllWorkspaces(window, visible: visible)
        focusedWindowState = state(for: window)
        return true
    }

    func handleDisplayTopologyChange() {
        guard hasCompletedInitialRefresh else {
            refresh()
            return
        }
        workspaceTopologyChanged = true
        workspaceSwitchState = .degraded(message: "Display topology changed.")
        refresh()
    }

    func requestAccessibilityAccess() {
        logger.info("Requesting Accessibility access")
        accessibilityGranted = permissionManager.requestAccess()
        if accessibilityGranted {
            refresh()
        }
    }

    // MARK: - Authoritative Persistence

    private func loadPersistedState() async {
        switch await stateStore.load() {
        case .missing:
            // Check if legacy UserDefaults state exists for one-time seamless migration
            let legacyStore = WorkspaceConfigurationStore()
            if let legacyConfig = legacyStore.load() {
                workspaceManager.apply(configuration: legacyConfig)
                shortcutConfiguration = GlobalShortcutConfigurationStore().load()
                persistAuthoritativeState()
                persistenceStatus = .loaded
            } else {
                persistenceStatus = .missing
            }
        case let .loaded(state):
            persistedState = state
            workspaceManager.apply(configuration: WorkspaceManager.Configuration(persisted: state))
            shortcutConfiguration = GlobalShortcutConfiguration(persisted: state.shortcuts)
            persistenceStatus = .loaded
            evaluateRestoration()
        case let .unsupported(version):
            persistenceStatus = .unsupported(schemaVersion: version)
        case let .corrupted(_, description):
            persistenceStatus = .corrupted(description: description)
        case let .ioFailure(description):
            persistenceStatus = .ioFailure(description: description)
        }
    }

    func persistAuthoritativeState() {
        let state = PersistedStateV1.make(from: workspaceManager, shortcuts: shortcutConfiguration, displays: displays)
        persistedState = state
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch await stateStore.save(state) {
            case .saved:
                if case .loading = persistenceStatus { persistenceStatus = .loaded }
            case let .validationFailed(issues):
                persistenceStatus = .ioFailure(description: issues.map(\.message).joined(separator: " "))
            case let .refusedToOverwriteExistingState(description):
                persistenceStatus = .corrupted(description: description)
            case let .ioFailure(description):
                persistenceStatus = .ioFailure(description: description)
            }
        }
    }

    func resetPersistedConfiguration() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch await stateStore.reset() {
            case .success:
                persistedState = nil
                restorationItems = []
                persistenceStatus = .missing
                actionStatus = "Saved configuration reset. No external window was changed."
            case let .failure(error):
                actionStatus = "Could not reset saved configuration: \(error.message)"
            }
        }
    }

    // MARK: - Session Restoration

    func evaluateRestoration() {
        guard let persistedState else { return }
        restorationItems = restorationCoordinator.review(persistedState, windows: windows)
    }

    func confirmRestoration(_ item: RestorationReviewItem) {
        guard persistenceStatus.isSafeForExternalMutation,
              item.canConfirm,
              let candidate = item.candidate,
              let state = persistedState,
              let record = state.managedWindows.first(where: { $0.id == item.id }) else {
            actionStatus = "Only high-confidence matches can be confirmed after saved-state validation."
            return
        }
        guard case let .success(authorized) = WindowAuthorization.authorize(candidate, policy: managementPolicy) else {
            actionStatus = "The candidate is no longer eligible; no restoration was performed."
            evaluateRestoration()
            return
        }
        let geometry = DisplayTopologyMapper().restorationPlan(for: record.logicalGeometry, currentDisplays: displays)
        let frame = geometry?.frame ?? record.logicalGeometry.absolute.cgRect
        let snapshot = WindowSnapshot(
            runtimeIdentity: candidate.runtimeIdentity,
            applicationName: candidate.applicationName,
            bundleIdentifier: candidate.bundleIdentifier,
            title: nil,
            role: candidate.role,
            subrole: candidate.subrole,
            frame: frame,
            isMinimized: candidate.isMinimized,
            isFullscreen: candidate.isFullscreen,
            displayID: geometry?.displayID ?? candidate.displayID
        )
        let member = WorkspaceMember(
            managedWindowID: record.id,
            authorizedWindow: authorized,
            logicalSnapshot: snapshot,
            workspaceIDs: Set(record.workspaceIDs.map { WorkspaceID($0) }),
            visibleOnAllWorkspaces: record.sticky
        )
        workspaceManager.replaceMember(member, in: workspaceManager.activeWorkspaceID)
        let result = windowController.restore(authorized, requested: snapshot)
        restoreReport = WindowRestoreReport(results: [result])
        if result.status == .restoredExactly || result.status == .restoredWithAdjustment {
            restorationItems.removeAll { $0.id == item.id }
            persistAuthoritativeState()
            actionStatus = "Restored and re-associated \(candidate.applicationName) after explicit confirmation."
        } else {
            actionStatus = "Association was confirmed, but physical restoration was not completed: \(result.message)"
        }
    }

    // MARK: - Workspace CRUD & Switching

    func addWorkspace(name: String? = nil) -> WorkspaceID {
        let id = workspaceManager.addWorkspace(name: name)
        persistAuthoritativeState()
        actionStatus = "Created \(workspaceName(id))."
        return id
    }

    func renameWorkspace(_ id: WorkspaceID, name: String) -> Bool {
        let renamed = workspaceManager.renameWorkspace(id, name: name)
        if renamed { persistAuthoritativeState() }
        actionStatus = renamed ? "Renamed desktop." : "Desktop name cannot be empty."
        return renamed
    }

    func reorderWorkspace(_ id: WorkspaceID, by offset: Int) -> Bool {
        let moved = workspaceManager.moveWorkspace(id, by: offset)
        if moved {
            persistAuthoritativeState()
            actionStatus = "Desktop order updated."
        }
        return moved
    }

    func deleteWorkspace(_ id: WorkspaceID, destination: WorkspaceID?) -> Bool {
        let deleted = workspaceManager.deleteWorkspace(id, moveExclusiveMembersTo: destination)
        if deleted { persistAuthoritativeState() }
        actionStatus = deleted
            ? "Deleted the logical desktop; windows were not closed or destroyed."
            : "Choose an explicit replacement desktop for exclusive members or the active desktop."
        return deleted
    }

    func activateWorkspace(_ id: WorkspaceID) {
        guard workspaceManager.workspaceIDs.contains(id) else {
            actionStatus = "That desktop no longer exists."
            return
        }
        let mode: VirtualSpaceActivationMode = experimentalWorkspaceModeEnabled ? .managedWindows : .logicalOnly
        switch activationStrategyProvider.strategy(for: mode) {
        case .managedWindowSwitch:
            switchWorkspace(to: id)
        case .logicalOnly:
            _ = workspaceManager.activate(id)
            persistAuthoritativeState()
            actionStatus = "Activated \(workspaceName(id)) in the logical desktop model."
        case .nativeSpacesExperimental:
            actionStatus = "Native Spaces integration is experimental and unavailable."
        }
    }

    func activateNextWorkspace() {
        guard let id = workspaceManager.nextWorkspaceID() else { return }
        activateWorkspace(id)
    }

    func activatePreviousWorkspace() {
        guard let id = workspaceManager.previousWorkspaceID() else { return }
        activateWorkspace(id)
    }

    func switchWorkspace(to targetID: WorkspaceID) {
        guard experimentalWorkspaceModeEnabled else {
            actionStatus = "Enable desktop switching before switching desktops."
            return
        }
        guard accessibilityGranted else {
            workspaceSwitchState = .degraded(message: "Accessibility permission is unavailable.")
            actionStatus = "Accessibility permission is unavailable; switching is paused."
            return
        }
        guard !workspaceTopologyChanged else {
            actionStatus = "Switching is paused because display topology changed. Recover managed windows first."
            return
        }
        guard !workspaceSwitchState.isDegraded else {
            actionStatus = "Switching is paused after a partial operation. Recover managed windows before switching again."
            return
        }
        let sourceID = workspaceManager.activeWorkspaceID
        guard sourceID != targetID, workspaceManager.workspaceIDs.contains(targetID) else { return }
        guard let immediate = switchQueue.request(targetID) else {
            actionStatus = "Switch already running; keeping only the latest requested desktop."
            workspaceSwitchState = switchQueue.state
            return
        }
        performSwitch(to: immediate)
    }

    private func performSwitch(to targetID: WorkspaceID) {
        workspaceSwitchState = .switching(target: targetID)
        let sourceID = workspaceManager.activeWorkspaceID
        let execution = workspaceEngine.switchWorkspace(
            from: workspaceManager.workspace(for: sourceID),
            to: workspaceManager.workspace(for: targetID),
            displays: displays
        )
        if let source = execution.sourceWorkspace { workspaceManager.replaceWorkspace(source) }
        workspaceManager.replaceWorkspace(execution.targetWorkspace)
        _ = workspaceManager.activate(targetID)
        persistAuthoritativeState()
        workspaceSwitchResult = execution.result
        actionStatus = execution.result.isDegraded
            ? "Switched to \(workspaceName(targetID)) with recoverable partial results; inspect the report below."
            : "Switched to \(workspaceName(targetID))."
        let pending = switchQueue.finish(
            completedTarget: targetID,
            degradedMessage: execution.result.isDegraded ? "The last switch completed with partial results." : nil
        )
        workspaceSwitchState = switchQueue.state
        if let pending { performSwitch(to: pending) }
    }

    func enterExperimentalWorkspaceMode() {
        guard persistenceStatus.isSafeForExternalMutation else {
            actionStatus = "Resolve the saved-configuration state before enabling external window switching."
            return
        }
        guard accessibilityGranted else {
            actionStatus = "Accessibility permission is required before enabling desktop switching."
            return
        }
        let activeID = workspaceManager.activeWorkspaceID
        let activeIDs = Set(workspaceManager.workspace(for: activeID).members.map(\.id))
        var results: [WorkspaceWindowResult] = []
        var captureMS = 0.0
        var parkingMS = 0.0
        var processed = 0
        for id in workspaceManager.workspaceIDs where id != activeID {
            let execution = workspaceEngine.parkInactiveWorkspace(
                workspaceManager.workspace(for: id),
                displays: displays,
                excludingVisibleIDs: activeIDs
            )
            workspaceManager.replaceWorkspace(execution.targetWorkspace)
            results.append(contentsOf: execution.result.results)
            captureMS += execution.result.metrics.captureMilliseconds
            parkingMS += execution.result.metrics.parkingMilliseconds
            processed += execution.result.metrics.windowsProcessed
        }
        experimentalWorkspaceModeEnabled = true
        switchQueue.reset()
        workspaceSwitchState = .idle
        workspaceSwitchResult = WorkspaceSwitchResult(
            sourceWorkspaceID: nil,
            targetWorkspaceID: activeID,
            results: results,
            metrics: WorkspaceSwitchMetrics(captureMilliseconds: captureMS, parkingMilliseconds: parkingMS, restoreMilliseconds: 0, totalMilliseconds: captureMS + parkingMS, windowsProcessed: processed)
        )
        actionStatus = "Desktop switching enabled. Only explicitly managed windows are controlled."
    }

    func exitExperimentalWorkspaceMode() {
        guard experimentalWorkspaceModeEnabled else { return }
        guard performManagedWindowRecovery() else {
            actionStatus = "Desktop switching remains enabled because one or more parked windows could not be recovered."
            return
        }
        experimentalWorkspaceModeEnabled = false
        actionStatus = "Desktop switching exited after explicit recovery."
    }

    // MARK: - Window Management & Enrollment

    func isManaged(_ window: WindowSnapshot) -> Bool {
        workspaceManager.member(for: window.runtimeIdentity) != nil
    }

    func updateManagementExclusions(applicationNames: [String], bundlePrefixes: [String]) {
        managementPolicy.excludedApplicationNames = normalizedUnique(applicationNames)
        managementPolicy.excludedBundleIdentifierPrefixes = normalizedUnique(bundlePrefixes)
        WindowManagementPolicyStore().save(managementPolicy)
        actionStatus = "Safety exclusions updated. Refresh to apply them to discovered windows."
    }

    private func normalizedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }
    }

    func manageWindow(_ window: WindowSnapshot) {
        guard case let .success(authorized) = WindowAuthorization.authorize(window, policy: managementPolicy) else {
            actionStatus = "This window cannot be managed because it is excluded or lacks a safe identifier."
            return
        }
        if let member = workspaceManager.member(for: authorized.runtimeIdentity) {
            actionStatus = "\(window.applicationName) is already managed."
            if member.workspaceIDs.isEmpty && !member.visibleOnAllWorkspaces {
                workspaceManager.moveToWorkspace(member, workspaceID: workspaceManager.activeWorkspaceID)
            }
            return
        }
        let member = WorkspaceMember(
            authorizedWindow: authorized,
            logicalSnapshot: window,
            workspaceIDs: [workspaceManager.activeWorkspaceID]
        )
        workspaceManager.addToWorkspace(member, workspaceID: workspaceManager.activeWorkspaceID)
        persistAuthoritativeState()
        actionStatus = "Managing \(window.applicationName) on \(workspaceName(workspaceManager.activeWorkspaceID))."
    }

    func stopManagingWindow(_ window: WindowSnapshot) {
        guard let member = workspaceManager.member(for: window.runtimeIdentity) else {
            actionStatus = "This window is already unmanaged."
            return
        }
        if member.isParked {
            guard accessibilityGranted else {
                workspaceSwitchState = .degraded(message: "Accessibility permission is unavailable.")
                actionStatus = "Cannot recover the parked window until Accessibility permission is restored."
                return
            }
            let result = windowController.recover(member.authorizedWindow, requested: member.logicalSnapshot, displays: displays)
            guard result.status == .restoredExactly || result.status == .restoredWithAdjustment || result.status == .windowMissing else {
                actionStatus = "Stop Managing was not completed: \(result.message)"
                return
            }
        }
        workspaceManager.remove(window.runtimeIdentity)
        persistAuthoritativeState()
        actionStatus = "Stopped managing \(window.applicationName); the application and window remain open."
    }

    func assignWindow(_ window: WindowSnapshot, to workspaceID: WorkspaceID, move: Bool) {
        guard case let .success(authorized) = WindowAuthorization.authorize(window, policy: managementPolicy) else {
            actionStatus = "The window is excluded or no longer has a safe runtime identifier."
            return
        }
        let member = workspaceManager.member(for: authorized.runtimeIdentity)
            ?? WorkspaceMember(authorizedWindow: authorized, logicalSnapshot: window)
        if move {
            workspaceManager.moveToWorkspace(member, workspaceID: workspaceID)
            actionStatus = "Moved \(window.applicationName) to \(workspaceName(workspaceID))."
        } else {
            workspaceManager.addToWorkspace(member, workspaceID: workspaceID)
            actionStatus = "Added \(window.applicationName) to \(workspaceName(workspaceID)) without removing existing memberships."
        }
        persistAuthoritativeState()
    }

    func setWindowVisibleOnAllWorkspaces(_ window: WindowSnapshot, visible: Bool) {
        guard case let .success(authorized) = WindowAuthorization.authorize(window, policy: managementPolicy) else {
            actionStatus = "Select an eligible window explicitly before changing workspace visibility."
            return
        }
        let member = workspaceManager.member(for: authorized.runtimeIdentity)
            ?? WorkspaceMember(authorizedWindow: authorized, logicalSnapshot: window)
        workspaceManager.setVisibleOnAllWorkspaces(member, visible: visible)
        persistAuthoritativeState()
        actionStatus = visible ? "\(window.applicationName) will remain visible on all current and future workspaces." : "\(window.applicationName) is no longer sticky."
    }

    // MARK: - Recovery

    func recoverManagedWindows() {
        _ = performManagedWindowRecovery()
    }

    @discardableResult
    func performManagedWindowRecovery() -> Bool {
        guard accessibilityGranted else {
            workspaceSwitchState = .degraded(message: "Accessibility permission is unavailable.")
            actionStatus = "Recovery is paused until Accessibility permission is restored."
            return false
        }
        let members = workspaceManager.allMembers.filter(\.isParked)
        guard !members.isEmpty else {
            if workspaceTopologyChanged {
                refresh()
            }
            actionStatus = "No managed windows require recovery."
            return !workspaceTopologyChanged
        }
        workspaceSwitchState = .recovering
        let results = members.map { member -> WorkspaceWindowResult in
            let workspaceID = member.workspaceIDs.contains(workspaceManager.activeWorkspaceID)
                ? workspaceManager.activeWorkspaceID
                : (member.workspaceIDs.sorted { $0.rawValue < $1.rawValue }.first ?? workspaceManager.activeWorkspaceID)
            let restore = windowController.recover(member.authorizedWindow, requested: member.logicalSnapshot, displays: displays)
            if restore.status == .restoredExactly || restore.status == .restoredWithAdjustment {
                var updated = member
                updated.isParked = false
                updated.parkedFrame = nil
                workspaceManager.replaceMember(updated, in: workspaceID)
            }
            return workspaceEngine.map(restore, member: member, workspaceID: workspaceID, operation: .restore)
        }
        let metrics = WorkspaceSwitchMetrics(captureMilliseconds: 0, parkingMilliseconds: 0, restoreMilliseconds: 0, totalMilliseconds: 0, windowsProcessed: results.count)
        workspaceSwitchResult = WorkspaceSwitchResult(sourceWorkspaceID: nil, targetWorkspaceID: workspaceManager.activeWorkspaceID, results: results, metrics: metrics)
        workspaceTopologyChanged = results.contains { $0.outcome == .missing || $0.outcome == .failed || $0.outcome == .unsupported }
        workspaceSwitchState = workspaceTopologyChanged ? .degraded(message: "Recovery completed with partial results.") : .idle
        actionStatus = "Recovery completed: \(workspaceSwitchResult?.restoredCount ?? 0) exact, \(workspaceSwitchResult?.adjustedCount ?? 0) adjusted, \(workspaceSwitchResult?.failedCount ?? 0) failed."
        refresh()
        return !workspaceTopologyChanged
    }

    func recoverForTermination() {
        guard accessibilityGranted else { return }
        for member in workspaceManager.allMembers where member.isParked {
            _ = windowController.recover(member.authorizedWindow, requested: member.logicalSnapshot, displays: displays)
        }
    }

    // MARK: - Global Shortcuts

    func startGlobalShortcuts() {
        guard accessibilityGranted else {
            shortcutManager.stop()
            globalShortcutsEnabled = false
            return
        }
        shortcutManager.start(configuration: shortcutConfiguration) { [weak self] action in
            Task { @MainActor in self?.handleShortcut(action) }
        }
        globalShortcutsEnabled = shortcutManager.isRunning
    }

    func setGlobalShortcutsEnabled(_ enabled: Bool) {
        shortcutConfiguration.enabled = enabled
        persistAuthoritativeState()
        if enabled { startGlobalShortcuts() } else { shortcutManager.stop(); globalShortcutsEnabled = false }
    }

    private func handleShortcut(_ action: GlobalShortcutAction) {
        guard accessibilityGranted else { return }
        switch action {
        case let .desktop(index):
            guard workspaceManager.workspaceOrder.indices.contains(index) else { return }
            activateWorkspace(workspaceManager.workspaceOrder[index])
        case .next: activateNextWorkspace()
        case .previous: activatePreviousWorkspace()
        }
    }

    // MARK: - Helpers

    func workspaceName(_ id: WorkspaceID) -> String {
        workspaceManager.workspaces[id]?.name ?? id.rawValue
    }
}
