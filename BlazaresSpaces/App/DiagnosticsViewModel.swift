import AppKit
import Combine
import Foundation
import OSLog

/// Presentation ViewModel for the BlazaresSpaces Inspector UI and MenuBar.
///
/// This layer contains NO business policy, NO switching algorithms, NO direct AX mutations,
/// and NO persistence I/O. It consumes application state from `WorkspaceApplicationService`
/// and manages local UI presentation state (such as inspection selections and test captures).
@MainActor
final class DiagnosticsViewModel: ObservableObject {
    // MARK: - Local UI Presentation State

    @Published private(set) var desktopSnapshot: WorkspaceSnapshot?
    @Published private(set) var selectedTestWindowID: WindowRuntimeIdentity?
    @Published private(set) var selectedTestSetIDs: Set<WindowRuntimeIdentity> = []
    @Published private(set) var capturedTestWindow: WindowSnapshot?
    @Published private(set) var capturedTestSet: WorkspaceSnapshot?
    @Published private var localRestoreReport: WindowRestoreReport?
    @Published private var localActionStatus: String?

    // MARK: - Injected Application Service

    let service: WorkspaceApplicationService

    private var cancellables = Set<AnyCancellable>()
    private var screenParametersObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var focusedApplicationObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BlazaresSpaces", category: "DiagnosticsUI")

    init(service: WorkspaceApplicationService? = nil) {
        let appService = service ?? WorkspaceApplicationService()
        self.service = appService

        // Forward changes from application service to SwiftUI views
        appService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak appService] _ in
            Task { @MainActor [weak appService] in
                appService?.handleDisplayTopologyChange()
            }
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak appService] _ in
            Task { @MainActor [weak appService] in
                appService?.recoverForTermination()
            }
        }

        focusedApplicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak appService] _ in
            Task { @MainActor [weak appService] in
                appService?.refreshFocusedWindow()
            }
        }
    }

    deinit {
        if let screenParametersObserver { NotificationCenter.default.removeObserver(screenParametersObserver) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        if let focusedApplicationObserver { NSWorkspace.shared.notificationCenter.removeObserver(focusedApplicationObserver) }
    }

    // MARK: - Forwarded Application State

    var accessibilityGranted: Bool { service.accessibilityGranted }
    var displays: [DisplaySnapshot] { service.displays }
    var windows: [WindowSnapshot] { service.windows }
    var issues: [WindowDiscoveryIssue] { service.issues }
    var lastRefresh: Date? { service.lastRefresh }
    var workspaceManager: WorkspaceManager { service.workspaceManager }
    var workspaceIDs: [WorkspaceID] { service.workspaceManager.workspaceIDs }
    var experimentalWorkspaceModeEnabled: Bool { service.experimentalWorkspaceModeEnabled }
    var workspaceSwitchResult: WorkspaceSwitchResult? { service.workspaceSwitchResult }
    var workspaceSwitchState: WorkspaceSwitchState { service.workspaceSwitchState }
    var workspaceTopologyChanged: Bool { service.workspaceTopologyChanged }
    var globalShortcutsEnabled: Bool { service.globalShortcutsEnabled }
    var shortcutConfiguration: GlobalShortcutConfiguration { service.shortcutConfiguration }
    var persistenceStatus: SessionPersistenceStatus { service.persistenceStatus }
    var restorationItems: [RestorationReviewItem] { service.restorationItems }
    var actionStatus: String? { localActionStatus ?? service.actionStatus }
    var restoreReport: WindowRestoreReport? { localRestoreReport ?? service.restoreReport }
    var excludedBundleIdentifierPrefixes: [String] { service.managementPolicy.excludedBundleIdentifierPrefixes }
    var excludedApplicationNames: [String] { service.managementPolicy.excludedApplicationNames }
    var focusedWindowState: WorkspaceApplicationService.FocusedWindowState { service.focusedWindowState }
    func updateManagementExclusions(applicationNames: [String], bundlePrefixes: [String]) {
        service.updateManagementExclusions(applicationNames: applicationNames, bundlePrefixes: bundlePrefixes)
    }

    func manageAndMoveFocusedWindow(to workspaceID: WorkspaceID) {
        _ = service.manageAndMoveFocusedWindow(to: workspaceID)
    }

    func manageAndShowFocusedWindow(on workspaceID: WorkspaceID) {
        _ = service.manageAndShowFocusedWindow(on: workspaceID)
    }

    func moveFocusedWindow(to workspaceID: WorkspaceID) {
        _ = service.moveFocusedWindow(to: workspaceID)
    }

    func showFocusedWindow(on workspaceID: WorkspaceID) {
        _ = service.showFocusedWindow(on: workspaceID)
    }

    func setFocusedWindowSticky(_ visible: Bool) {
        _ = service.setFocusedWindowSticky(visible)
    }

    var externalTestModeEnabled: Bool {
        selectedTestWindowID != nil || !selectedTestSetIDs.isEmpty
    }

    // MARK: - Application Intent Dispatch

    func refresh() {
        localActionStatus = nil
        service.refresh()
    }

    func requestAccessibilityAccess() {
        service.requestAccessibilityAccess()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func workspaceName(_ id: WorkspaceID) -> String {
        service.workspaceName(id)
    }

    func addWorkspace() {
        _ = service.addWorkspace()
    }

    func renameWorkspace(_ id: WorkspaceID, name: String) {
        _ = service.renameWorkspace(id, name: name)
    }

    func reorderWorkspace(_ id: WorkspaceID, by offset: Int) {
        _ = service.reorderWorkspace(id, by: offset)
    }

    func deleteWorkspace(_ id: WorkspaceID, destination: WorkspaceID?) {
        _ = service.deleteWorkspace(id, destination: destination)
    }

    func activateWorkspace(_ id: WorkspaceID) {
        service.activateWorkspace(id)
    }

    func activateNextWorkspace() {
        service.activateNextWorkspace()
    }

    func activatePreviousWorkspace() {
        service.activatePreviousWorkspace()
    }

    func enterExperimentalWorkspaceMode() {
        service.enterExperimentalWorkspaceMode()
    }

    func exitExperimentalWorkspaceMode() {
        service.exitExperimentalWorkspaceMode()
    }

    func recoverManagedWindows() {
        service.recoverManagedWindows()
    }

    func setGlobalShortcutsEnabled(_ enabled: Bool) {
        service.setGlobalShortcutsEnabled(enabled)
    }

    func isManaged(_ window: WindowSnapshot) -> Bool {
        service.isManaged(window)
    }

    func isWindowSticky(_ window: WindowSnapshot) -> Bool {
        workspaceManager.member(for: window.runtimeIdentity)?.visibleOnAllWorkspaces ?? false
    }

    func manageWindow(_ window: WindowSnapshot) {
        service.manageWindow(window)
    }

    func stopManagingWindow(_ window: WindowSnapshot) {
        service.stopManagingWindow(window)
    }

    func assignWindow(_ window: WindowSnapshot, to workspaceID: WorkspaceID, move: Bool) {
        service.assignWindow(window, to: workspaceID, move: move)
    }

    func setWindowVisibleOnAllWorkspaces(_ window: WindowSnapshot, visible: Bool) {
        service.setWindowVisibleOnAllWorkspaces(window, visible: visible)
    }

    func workspaceMembership(for window: WindowSnapshot) -> Set<WorkspaceID> {
        workspaceManager.workspaceContaining(window.runtimeIdentity)
    }

    func exclusionReason(for window: WindowSnapshot) -> String? {
        service.managementPolicy.exclusionReason(for: window)
    }

    func isExplicitlyAuthorizedForWorkspace(_ window: WindowSnapshot) -> Bool {
        selectedTestWindowID == window.runtimeIdentity
            || selectedTestSetIDs.contains(window.runtimeIdentity)
            || service.isManaged(window)
    }

    func confirmRestoration(_ item: RestorationReviewItem) {
        service.confirmRestoration(item)
    }

    func resetPersistedConfiguration() {
        service.resetPersistedConfiguration()
    }

    // MARK: - Inspector & Lab Test Set Selection

    func selectTestWindow(_ window: WindowSnapshot) {
        switch WindowAuthorization.authorize(window, policy: service.managementPolicy) {
        case let .failure(error):
            localActionStatus = error.localizedDescription
        case .success:
            selectedTestWindowID = window.runtimeIdentity
            capturedTestWindow = nil
            localRestoreReport = nil
            localActionStatus = "Selected \(window.applicationName) as the external capture/restore test window."
        }
    }

    func toggleTestSetSelection(_ window: WindowSnapshot) {
        setTestSetSelection(window, selected: !selectedTestSetIDs.contains(window.runtimeIdentity))
    }

    func setTestSetSelection(_ window: WindowSnapshot, selected: Bool) {
        switch WindowAuthorization.authorize(window, policy: service.managementPolicy) {
        case let .failure(error):
            localActionStatus = error.localizedDescription
        case .success:
            if selected {
                selectedTestSetIDs.insert(window.runtimeIdentity)
            } else {
                selectedTestSetIDs.remove(window.runtimeIdentity)
            }
            capturedTestSet = nil
            localRestoreReport = nil
            localActionStatus = "Test set contains \(selectedTestSetIDs.count) explicitly selected window(s)."
        }
    }

    func isSelectedInTestSet(_ window: WindowSnapshot) -> Bool {
        selectedTestSetIDs.contains(window.runtimeIdentity)
    }

    func captureAllWindows() {
        let currentDisplays = service.displayProvider.displays()
        let result = service.accessibilityGranted
            ? service.windowDiscovery.discover(displays: currentDisplays)
            : WindowDiscoveryResult(windows: [], issues: [])
        desktopSnapshot = WorkspaceSnapshot(capturedAt: Date(), displays: currentDisplays, windows: result.windows)
        localActionStatus = "Captured \(result.windows.count) window(s) across \(currentDisplays.count) display(s) read-only."
    }

    func captureSelectedWindow() {
        guard let selectedTestWindowID,
              let currentWindow = service.windows.first(where: { $0.runtimeIdentity == selectedTestWindowID }) else {
            localActionStatus = "Select one eligible external window first."
            return
        }
        guard case let .success(authorized) = WindowAuthorization.authorize(currentWindow, policy: service.managementPolicy) else {
            localActionStatus = "The selected window is no longer eligible for external testing."
            return
        }

        switch service.windowController.capture(authorized, displays: service.displays) {
        case let .success(snapshot):
            capturedTestWindow = snapshot
            localActionStatus = "Captured \(snapshot.applicationName) read-only."
        case let .failure(error):
            localActionStatus = "Capture failed: \(error.localizedDescription)"
        }
    }

    func restoreSelectedWindow() {
        guard let selectedTestWindowID,
              let capturedTestWindow,
              let currentWindow = service.windows.first(where: { $0.runtimeIdentity == selectedTestWindowID }) else {
            localActionStatus = "Select and capture one external window before restoring."
            return
        }
        guard case let .success(authorized) = WindowAuthorization.authorize(currentWindow, policy: service.managementPolicy) else {
            localActionStatus = "The selected window is no longer eligible for external testing."
            return
        }

        let result = service.windowController.restore(authorized, requested: capturedTestWindow)
        localRestoreReport = WindowRestoreReport(results: [result])
        localActionStatus = result.message
        service.refresh()
    }

    func captureSelectedTestSet() {
        let selectedIDs = Array(selectedTestSetIDs)
        guard !selectedIDs.isEmpty else {
            localActionStatus = "Select one or more eligible windows for the test set first."
            return
        }

        var snapshots: [WindowSnapshot] = []
        var failures: [String] = []
        for id in selectedIDs {
            guard let currentWindow = service.windows.first(where: { $0.runtimeIdentity == id }) else {
                failures.append("PID \(id.processIdentifier): window missing")
                continue
            }
            guard case let .success(authorized) = WindowAuthorization.authorize(currentWindow, policy: service.managementPolicy) else {
                failures.append("\(currentWindow.applicationName): no longer eligible")
                continue
            }
            switch service.windowController.capture(authorized, displays: service.displays) {
            case let .success(snapshot): snapshots.append(snapshot)
            case let .failure(error): failures.append("\(currentWindow.applicationName): \(error.localizedDescription)")
            }
        }

        capturedTestSet = WorkspaceSnapshot(capturedAt: Date(), displays: service.displays, windows: snapshots)
        localActionStatus = "Captured \(snapshots.count) selected window(s) read-only.\(failures.isEmpty ? "" : " Failures: \(failures.joined(separator: "; "))")"
    }

    func restoreSelectedTestSet() {
        guard let capturedTestSet, !capturedTestSet.windows.isEmpty else {
            localActionStatus = "Capture the selected test set before restoring it."
            return
        }

        let results = capturedTestSet.windows.map { snapshot -> WindowRestoreResult in
            guard let currentWindow = service.windows.first(where: { $0.runtimeIdentity == snapshot.runtimeIdentity }) else {
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
            guard case let .success(authorized) = WindowAuthorization.authorize(currentWindow, policy: service.managementPolicy) else {
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
            return service.windowController.restore(authorized, requested: snapshot)
        }

        localRestoreReport = WindowRestoreReport(results: results)
        localActionStatus = "Restore completed: \(localRestoreReport?.exactCount ?? 0) exact, \(localRestoreReport?.adjustedCount ?? 0) adjusted, \(localRestoreReport?.failedCount ?? 0) failed, \(localRestoreReport?.excludedCount ?? 0) excluded."
        service.refresh()
    }
}
