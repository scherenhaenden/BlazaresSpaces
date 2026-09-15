import AppKit
import Combine
import OSLog

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var displays: [DisplaySnapshot] = []
    @Published private(set) var windows: [WindowSnapshot] = []
    @Published private(set) var issues: [WindowDiscoveryIssue] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var desktopSnapshot: WorkspaceSnapshot?
    @Published private(set) var selectedTestWindowID: WindowRuntimeIdentity?
    @Published private(set) var selectedTestSetIDs: Set<WindowRuntimeIdentity> = []
    @Published private(set) var capturedTestWindow: WindowSnapshot?
    @Published private(set) var capturedTestSet: WorkspaceSnapshot?
    @Published private(set) var restoreReport: WindowRestoreReport?
    @Published private(set) var actionStatus: String?
    @Published private(set) var workspaceManager = WorkspaceManager()
    @Published private(set) var experimentalWorkspaceModeEnabled = false
    @Published private(set) var workspaceSwitchResult: WorkspaceSwitchResult?
    @Published private(set) var workspaceSwitchState: WorkspaceSwitchState = .idle
    @Published private(set) var workspaceTopologyChanged = false
    @Published private(set) var globalShortcutsEnabled = false
    @Published private(set) var shortcutConfiguration = GlobalShortcutConfiguration()
    @Published private(set) var persistenceStatus: SessionPersistenceStatus = .loading
    @Published private(set) var restorationItems: [RestorationReviewItem] = []

    private let permissionManager = AccessibilityPermissionManager()
    private let displayManager = DisplayManager()
    private let windowDiscovery = AXWindowDiscovery()
    private let managementPolicy = WindowManagementPolicy.developmentDefaults
    private let externalWindowController = AXExternalWindowController()
    private let workspaceEngine = WorkspaceSwitchEngine()
    private let workspaceConfigurationStore = WorkspaceConfigurationStore()
    private let shortcutConfigurationStore = GlobalShortcutConfigurationStore()
    private let shortcutManager = GlobalShortcutManager()
    private let stateStore = AtomicJSONWorkspaceStateStore()
    private let restorationCoordinator = SessionRestorationCoordinator()
    private var persistedState: PersistedStateV1?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BlazaresSpaces", category: "Diagnostics")
    private var switchQueue = WorkspaceSwitchRequestQueue()
    private var screenParametersObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?

    init() {
        if let configuration = workspaceConfigurationStore.load() {
            workspaceManager.apply(configuration: configuration)
        }
        shortcutConfiguration = shortcutConfigurationStore.load()
        Task { @MainActor [weak self] in
            await self?.loadPersistedState()
        }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDisplayTopologyChange()
            }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recoverForTermination()
            }
        }
    }

    deinit {
        if let screenParametersObserver { NotificationCenter.default.removeObserver(screenParametersObserver) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    func refresh() {
        let previousDisplays = displays
        accessibilityGranted = permissionManager.isTrusted
        displays = displayManager.displays()

        if !previousDisplays.isEmpty && previousDisplays != displays {
            workspaceTopologyChanged = true
            workspaceSwitchState = .degraded(message: "Display topology changed; switching is paused until recovery or refresh validation.")
            actionStatus = "Display topology changed. Review the topology and use Recover Managed Windows before switching again."
        }

        if accessibilityGranted {
            let result = windowDiscovery.discover(displays: displays)
            windows = result.windows
            issues = result.issues
            evaluateRestoration()
        } else {
            windows = []
            issues = []
            shortcutManager.stop()
            globalShortcutsEnabled = false
            if experimentalWorkspaceModeEnabled {
                workspaceSwitchState = .degraded(message: "Accessibility permission is unavailable.")
                actionStatus = "Accessibility permission is unavailable; AX mutations are paused. Re-enable it in System Settings."
            }
        }
        if accessibilityGranted && !globalShortcutsEnabled { startGlobalShortcuts() }
        lastRefresh = Date()
    }

    private func loadPersistedState() async {
        switch await stateStore.load() {
        case .missing:
            persistenceStatus = .missing
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

    private func evaluateRestoration() {
        guard let persistedState else { return }
        restorationItems = restorationCoordinator.review(persistedState, windows: windows)
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
                actionStatus = "Could not reset saved configuration: \(error)"
            }
        }
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
            workspaceIDs: Set(record.workspaceIDs.map(WorkspaceID.init)),
            visibleOnAllWorkspaces: record.sticky
        )
        workspaceManager.replaceMember(member, in: workspaceManager.activeWorkspaceID)
        let result = externalWindowController.restore(authorized, requested: snapshot)
        restoreReport = WindowRestoreReport(results: [result])
        if result.status == .restoredExactly || result.status == .restoredWithAdjustment {
            restorationItems.removeAll { $0.id == item.id }
            persistWorkspaceConfiguration()
            actionStatus = "Restored and re-associated \(candidate.applicationName) after explicit confirmation."
        } else {
            actionStatus = "Association was confirmed, but physical restoration was not completed: \(result.message)"
        }
    }

    func requestAccessibilityAccess() {
        logger.info("Requesting Accessibility access")
        accessibilityGranted = permissionManager.requestAccess()
        if accessibilityGranted {
            refresh()
        }
    }

    /// Captures all currently discovered external windows without changing any window.
    func captureAllWindows() {
        let currentDisplays = displayManager.displays()
        let result = accessibilityGranted
            ? windowDiscovery.discover(displays: currentDisplays)
            : WindowDiscoveryResult(windows: [], issues: [])
        displays = currentDisplays
        windows = result.windows
        issues = result.issues
        desktopSnapshot = WorkspaceSnapshot(capturedAt: Date(), displays: currentDisplays, windows: result.windows)
        lastRefresh = Date()
    }

    var externalTestModeEnabled: Bool {
        selectedTestWindowID != nil || !selectedTestSetIDs.isEmpty
    }

    func exclusionReason(for window: WindowSnapshot) -> String? {
        managementPolicy.exclusionReason(for: window)
    }

    func isSelectedInTestSet(_ window: WindowSnapshot) -> Bool {
        selectedTestSetIDs.contains(window.runtimeIdentity)
    }

    func selectTestWindow(_ window: WindowSnapshot) {
        switch WindowAuthorization.authorize(window, policy: managementPolicy) {
        case let .failure(error):
            actionStatus = error.localizedDescription
        case .success:
            selectedTestWindowID = window.runtimeIdentity
            capturedTestWindow = nil
            restoreReport = nil
            actionStatus = "Selected \(window.applicationName) as the external capture/restore test window."
        }
    }

    func toggleTestSetSelection(_ window: WindowSnapshot) {
        setTestSetSelection(window, selected: !selectedTestSetIDs.contains(window.runtimeIdentity))
    }

    func setTestSetSelection(_ window: WindowSnapshot, selected: Bool) {
        switch WindowAuthorization.authorize(window, policy: managementPolicy) {
        case let .failure(error):
            actionStatus = error.localizedDescription
        case .success:
            if selected {
                selectedTestSetIDs.insert(window.runtimeIdentity)
            } else {
                selectedTestSetIDs.remove(window.runtimeIdentity)
            }
            capturedTestSet = nil
            restoreReport = nil
            actionStatus = "Test set contains \(selectedTestSetIDs.count) explicitly selected window(s)."
        }
    }

    var workspaceIDs: [WorkspaceID] { workspaceManager.workspaceIDs }

    func workspaceName(_ id: WorkspaceID) -> String {
        workspaceManager.workspace(for: id).name
    }

    func isExplicitlyAuthorizedForWorkspace(_ window: WindowSnapshot) -> Bool {
        selectedTestWindowID == window.runtimeIdentity
            || selectedTestSetIDs.contains(window.runtimeIdentity)
            || workspaceManager.member(for: window.runtimeIdentity) != nil
    }

    func isManaged(_ window: WindowSnapshot) -> Bool {
        workspaceManager.member(for: window.runtimeIdentity) != nil
    }

    func manageWindow(_ window: WindowSnapshot) {
        guard case let .success(authorized) = WindowAuthorization.authorize(window, policy: managementPolicy) else {
            actionStatus = "This window is excluded or lacks a safe runtime identifier."
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
        persistWorkspaceConfiguration()
        actionStatus = "Managing \(window.applicationName) on \(workspaceName(workspaceManager.activeWorkspaceID))."
    }

    func workspaceMembership(for window: WindowSnapshot) -> Set<WorkspaceID> {
        workspaceManager.workspaceContaining(window.runtimeIdentity)
    }

    func assignWindow(_ window: WindowSnapshot, to workspaceID: WorkspaceID, move: Bool) {
        guard isExplicitlyAuthorizedForWorkspace(window) else {
            actionStatus = "Select this window explicitly in External Window Test Mode before assigning it."
            return
        }
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
        persistWorkspaceConfiguration()
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
            let result = externalWindowController.recover(member.authorizedWindow, requested: member.logicalSnapshot, displays: displays)
            guard result.status == .restoredExactly || result.status == .restoredWithAdjustment || result.status == .windowMissing else {
                actionStatus = "Stop Managing was not completed: (result.message)"
                return
            }
        }
        workspaceManager.remove(window.runtimeIdentity)
        persistWorkspaceConfiguration()
        actionStatus = "Stopped managing \(window.applicationName); the application and window remain open."
    }

    func setWindowVisibleOnAllWorkspaces(_ window: WindowSnapshot, visible: Bool) {
        guard isExplicitlyAuthorizedForWorkspace(window),
              case let .success(authorized) = WindowAuthorization.authorize(window, policy: managementPolicy) else {
            actionStatus = "Select an eligible window explicitly before changing workspace visibility."
            return
        }
        let member = workspaceManager.member(for: authorized.runtimeIdentity)
            ?? WorkspaceMember(authorizedWindow: authorized, logicalSnapshot: window)
        workspaceManager.setVisibleOnAllWorkspaces(member, visible: visible)
        persistWorkspaceConfiguration()
        actionStatus = visible ? "\(window.applicationName) will remain visible on all current and future workspaces." : "\(window.applicationName) is no longer sticky."
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
        persistWorkspaceConfiguration()
        workspaceSwitchResult = execution.result
        actionStatus = execution.result.isDegraded
            ? "Switched to \(workspaceName(targetID)) with recoverable partial results; inspect the report below."
            : "Switched to \(workspaceName(targetID))."
        let pending = switchQueue.finish(degradedMessage: execution.result.isDegraded ? "The last switch completed with partial results." : nil)
        workspaceSwitchState = switchQueue.state
        if let pending { performSwitch(to: pending) }
    }

    func addWorkspace() {
        let id = workspaceManager.addWorkspace()
        persistWorkspaceConfiguration()
        actionStatus = "Created \(workspaceName(id))."
    }

    func activateWorkspace(_ id: WorkspaceID) {
        guard workspaceManager.workspaceIDs.contains(id) else {
            actionStatus = "That desktop no longer exists."
            return
        }
        if experimentalWorkspaceModeEnabled { switchWorkspace(to: id) }
        else {
            _ = workspaceManager.activate(id)
            persistWorkspaceConfiguration()
            actionStatus = "Activated \(workspaceName(id)) in the logical desktop model."
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

    func renameWorkspace(_ id: WorkspaceID, name: String) {
        let renamed = workspaceManager.renameWorkspace(id, name: name)
        if renamed { persistWorkspaceConfiguration() }
        actionStatus = renamed ? "Renamed desktop." : "Desktop name cannot be empty."
    }

    func reorderWorkspace(_ id: WorkspaceID, by offset: Int) {
        if workspaceManager.moveWorkspace(id, by: offset) {
            persistWorkspaceConfiguration()
            actionStatus = "Desktop order updated."
        }
    }

    func deleteWorkspace(_ id: WorkspaceID, destination: WorkspaceID?) {
        let deleted = workspaceManager.deleteWorkspace(id, moveExclusiveMembersTo: destination)
        if deleted { persistWorkspaceConfiguration() }
        actionStatus = deleted
            ? "Deleted the logical desktop; windows were not closed or destroyed."
            : "Choose an explicit replacement desktop for exclusive members or the active desktop."
    }

    func recoverManagedWindows() {
        _ = performManagedWindowRecovery()
    }

    @discardableResult
    private func performManagedWindowRecovery() -> Bool {
        guard accessibilityGranted else {
            workspaceSwitchState = .degraded(message: "Accessibility permission is unavailable.")
            actionStatus = "Recovery is paused until Accessibility permission is restored."
            return false
        }
        let members = workspaceManager.allMembers.filter(\.isParked)
        guard !members.isEmpty else {
            actionStatus = "No managed windows require recovery."
            return true
        }
        workspaceSwitchState = .recovering
        let results = members.map { member -> WorkspaceWindowResult in
            let workspaceID = member.workspaceIDs.contains(workspaceManager.activeWorkspaceID)
                ? workspaceManager.activeWorkspaceID
                : (member.workspaceIDs.sorted { $0.rawValue < $1.rawValue }.first ?? workspaceManager.activeWorkspaceID)
            let restore = externalWindowController.recover(member.authorizedWindow, requested: member.logicalSnapshot, displays: displays)
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

    func exitExperimentalWorkspaceMode() {
        guard experimentalWorkspaceModeEnabled else { return }
        guard performManagedWindowRecovery() else {
            actionStatus = "Desktop switching remains enabled because one or more parked windows could not be recovered."
            return
        }
        experimentalWorkspaceModeEnabled = false
        actionStatus = "Desktop switching exited after explicit recovery."
    }

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
        shortcutConfigurationStore.save(shortcutConfiguration)
        persistWorkspaceConfiguration()
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

    private func handleDisplayTopologyChange() {
        workspaceTopologyChanged = true
        workspaceSwitchState = .degraded(message: "Display topology changed.")
        refresh()
    }

    private func persistWorkspaceConfiguration() {
        workspaceConfigurationStore.save(workspaceManager.configuration)
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

    private func recoverForTermination() {
        guard accessibilityGranted else { return }
        for member in workspaceManager.allMembers where member.isParked {
            _ = externalWindowController.recover(member.authorizedWindow, requested: member.logicalSnapshot, displays: displays)
        }
    }

    func captureSelectedWindow() {
        guard let selectedTestWindowID,
              let currentWindow = windows.first(where: { $0.runtimeIdentity == selectedTestWindowID }) else {
            actionStatus = "Select one eligible external window first."
            return
        }
        guard case let .success(authorized) = WindowAuthorization.authorize(currentWindow, policy: managementPolicy) else {
            actionStatus = "The selected window is no longer eligible for external testing."
            return
        }

        switch externalWindowController.capture(authorized, displays: displays) {
        case let .success(snapshot):
            capturedTestWindow = snapshot
            actionStatus = "Captured \(snapshot.applicationName) read-only."
        case let .failure(error):
            actionStatus = "Capture failed: \(error.localizedDescription)"
        }
    }

    func restoreSelectedWindow() {
        guard let selectedTestWindowID,
              let capturedTestWindow,
              let currentWindow = windows.first(where: { $0.runtimeIdentity == selectedTestWindowID }) else {
            actionStatus = "Select and capture one external window before restoring."
            return
        }
        guard case let .success(authorized) = WindowAuthorization.authorize(currentWindow, policy: managementPolicy) else {
            actionStatus = "The selected window is no longer eligible for external testing."
            return
        }

        let result = externalWindowController.restore(authorized, requested: capturedTestWindow)
        restoreReport = WindowRestoreReport(results: [result])
        actionStatus = result.message
        refresh()
    }

    func captureSelectedTestSet() {
        let selectedIDs = Array(selectedTestSetIDs)
        guard !selectedIDs.isEmpty else {
            actionStatus = "Select one or more eligible windows for the test set first."
            return
        }

        var snapshots: [WindowSnapshot] = []
        var failures: [String] = []
        for id in selectedIDs {
            guard let currentWindow = windows.first(where: { $0.runtimeIdentity == id }) else {
                failures.append("PID \(id.processIdentifier): window missing")
                continue
            }
            guard case let .success(authorized) = WindowAuthorization.authorize(currentWindow, policy: managementPolicy) else {
                failures.append("\(currentWindow.applicationName): no longer eligible")
                continue
            }
            switch externalWindowController.capture(authorized, displays: displays) {
            case let .success(snapshot): snapshots.append(snapshot)
            case let .failure(error): failures.append("\(currentWindow.applicationName): \(error.localizedDescription)")
            }
        }

        capturedTestSet = WorkspaceSnapshot(capturedAt: Date(), displays: displays, windows: snapshots)
        actionStatus = "Captured \(snapshots.count) selected window(s) read-only.\(failures.isEmpty ? "" : " Failures: \(failures.joined(separator: "; "))")"
    }

    func restoreSelectedTestSet() {
        guard let capturedTestSet, !capturedTestSet.windows.isEmpty else {
            actionStatus = "Capture the selected test set before restoring it."
            return
        }

        let results = capturedTestSet.windows.map { snapshot -> WindowRestoreResult in
            guard let currentWindow = windows.first(where: { $0.runtimeIdentity == snapshot.runtimeIdentity }) else {
                return WindowRestoreResult(
                    id: snapshot.runtimeIdentity,
                    applicationName: snapshot.applicationName,
                    processIdentifier: snapshot.runtimeIdentity.processIdentifier,
                    requestedFrame: snapshot.frame,
                    actualFrame: nil,
                    status: .windowMissing,
                    message: "The exact selected runtime window is no longer present."
                )
            }
            guard case let .success(authorized) = WindowAuthorization.authorize(currentWindow, policy: managementPolicy) else {
                return WindowRestoreResult(
                    id: snapshot.runtimeIdentity,
                    applicationName: snapshot.applicationName,
                    processIdentifier: snapshot.runtimeIdentity.processIdentifier,
                    requestedFrame: snapshot.frame,
                    actualFrame: nil,
                    status: .excluded,
                    message: "Window is excluded or no longer authorized."
                )
            }
            return externalWindowController.restore(authorized, requested: snapshot)
        }

        restoreReport = WindowRestoreReport(results: results)
        actionStatus = "Restore completed: \(restoreReport?.exactCount ?? 0) exact, \(restoreReport?.adjustedCount ?? 0) adjusted, \(restoreReport?.failedCount ?? 0) failed, \(restoreReport?.excludedCount ?? 0) excluded."
        refresh()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
