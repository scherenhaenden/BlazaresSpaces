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

    private let permissionManager = AccessibilityPermissionManager()
    private let displayManager = DisplayManager()
    private let windowDiscovery = AXWindowDiscovery()
    private let managementPolicy = WindowManagementPolicy.developmentDefaults
    private let externalWindowController = AXExternalWindowController()
    private let workspaceEngine = WorkspaceSwitchEngine()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BlazaresSpaces", category: "Diagnostics")

    func refresh() {
        accessibilityGranted = permissionManager.isTrusted
        displays = displayManager.displays()

        if accessibilityGranted {
            let result = windowDiscovery.discover(displays: displays)
            windows = result.windows
            issues = result.issues
        } else {
            windows = []
            issues = []
        }
        lastRefresh = Date()
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
        selectedTestWindowID == window.runtimeIdentity || selectedTestSetIDs.contains(window.runtimeIdentity)
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
        actionStatus = visible ? "\(window.applicationName) will remain visible on all current and future workspaces." : "\(window.applicationName) is no longer sticky."
    }

    func enterExperimentalWorkspaceMode() {
        guard !workspaceManager.allMembers.isEmpty else {
            actionStatus = "Assign at least one explicitly authorized window before entering Experimental Workspace Mode."
            return
        }
        let inactive = workspaceManager.workspace(for: workspaceManager.workspaceIDs.dropFirst().first ?? .workspace2)
        let execution = workspaceEngine.parkInactiveWorkspace(inactive, displays: displays)
        workspaceManager.replaceWorkspace(execution.targetWorkspace)
        experimentalWorkspaceModeEnabled = true
        _ = workspaceManager.activate(.workspace1)
        workspaceSwitchResult = execution.result
        actionStatus = "Experimental Workspace Mode enabled. Only explicitly assigned windows are controlled."
    }

    func switchWorkspace(to targetID: WorkspaceID) {
        guard experimentalWorkspaceModeEnabled else {
            actionStatus = "Enter Experimental Workspace Mode before switching workspaces."
            return
        }
        let sourceID = workspaceManager.activeWorkspaceID
        guard sourceID != targetID else { return }
        let execution = workspaceEngine.switchWorkspace(
            from: workspaceManager.workspace(for: sourceID),
            to: workspaceManager.workspace(for: targetID),
            displays: displays
        )
        if let source = execution.sourceWorkspace { workspaceManager.replaceWorkspace(source) }
        workspaceManager.replaceWorkspace(execution.targetWorkspace)
        _ = workspaceManager.activate(targetID)
        workspaceSwitchResult = execution.result
        actionStatus = execution.result.isDegraded
            ? "Switched to \(workspaceName(targetID)) with recoverable partial results; inspect the report below."
            : "Switched to \(workspaceName(targetID))."
    }

    func addWorkspace() {
        let id = workspaceManager.addWorkspace()
        actionStatus = "Created \(workspaceName(id))."
    }

    func activateWorkspace(_ id: WorkspaceID) {
        guard workspaceManager.workspaceIDs.contains(id) else {
            actionStatus = "That workspace no longer exists."
            return
        }
        if experimentalWorkspaceModeEnabled {
            switchWorkspace(to: id)
        } else {
            _ = workspaceManager.activate(id)
            actionStatus = "Activated \(workspaceName(id)) in the logical workspace model."
        }
    }

    func renameWorkspace(_ id: WorkspaceID, name: String) {
        actionStatus = workspaceManager.renameWorkspace(id, name: name)
            ? "Renamed workspace."
            : "Workspace name cannot be empty."
    }

    func deleteWorkspace(_ id: WorkspaceID) {
        guard let destination = workspaceManager.workspaceIDs.first(where: { $0 != id }) else { return }
        actionStatus = workspaceManager.deleteWorkspace(id, moveExclusiveMembersTo: destination)
            ? "Deleted the logical workspace; windows were not closed or destroyed."
            : "Workspace deletion requires an explicit destination for exclusive members."
    }

    func recoverManagedWindows() {
        let members = workspaceManager.allMembers
        guard !members.isEmpty else {
            actionStatus = "No managed windows require recovery."
            return
        }
        let results = members.map { member -> WorkspaceWindowResult in
            let workspaceID = member.workspaceIDs.contains(workspaceManager.activeWorkspaceID)
                ? workspaceManager.activeWorkspaceID
                : (member.workspaceIDs.sorted { $0.rawValue < $1.rawValue }.first ?? workspaceManager.activeWorkspaceID)
            let restore = externalWindowController.restore(member.authorizedWindow, requested: member.logicalSnapshot)
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
        actionStatus = "Recovery completed: \(workspaceSwitchResult?.restoredCount ?? 0) exact, \(workspaceSwitchResult?.adjustedCount ?? 0) adjusted, \(workspaceSwitchResult?.failedCount ?? 0) failed."
        refresh()
    }

    func exitExperimentalWorkspaceMode() {
        guard experimentalWorkspaceModeEnabled else { return }
        recoverManagedWindows()
        experimentalWorkspaceModeEnabled = false
        actionStatus = "Experimental Workspace Mode exited after explicit recovery."
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
