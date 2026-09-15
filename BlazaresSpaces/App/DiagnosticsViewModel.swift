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

    private let permissionManager = AccessibilityPermissionManager()
    private let displayManager = DisplayManager()
    private let windowDiscovery = AXWindowDiscovery()
    private let managementPolicy = WindowManagementPolicy.developmentDefaults
    private let externalWindowController = AXExternalWindowController()
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
