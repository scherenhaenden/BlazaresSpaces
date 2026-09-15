//
//  ContentView.swift
//  BlazaresSpaces
//
//  Created by Edward Flores on 15.09.26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = DiagnosticsViewModel()
    @Environment(\.openWindow) private var openWindow
    @State private var showWindowTitles = false
    @State private var workspaceNameDrafts: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if model.externalTestModeEnabled { externalTestModeSection }
                    workspaceSection
                    displaysSection
                    windowsSection
                    if let snapshot = model.desktopSnapshot { snapshotSection(snapshot) }
                    if let snapshot = model.capturedTestSet { selectedSetSnapshotSection(snapshot) }
                    if let report = model.restoreReport { restoreReportSection(report) }
                    if !model.issues.isEmpty { issuesSection }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 560)
        .task { model.refresh() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("BlazaresSpaces Inspector")
                    .font(.title.bold())
                Label(
                    "Accessibility: \(model.accessibilityGranted ? "Granted" : "Not Granted")",
                    systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(model.accessibilityGranted ? .green : .orange)
                .accessibilityIdentifier("accessibilityStatus")
                if !model.accessibilityGranted {
                    Text("Permission is required to inspect other applications' windows. Display inspection remains available.")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !model.accessibilityGranted {
                Button("Request Access") { model.requestAccessibilityAccess() }
                Button("Open Settings") { model.openAccessibilitySettings() }
            }
            Button("Window Control Lab") { openWindow(id: "window-control-lab") }
            Button("Capture Desktop Snapshot") { model.captureAllWindows() }
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var displaysSection: some View {
        GroupBox("Displays detected: \(model.displays.count)") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.displays) { display in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(display.name)\(display.isMain ? " (Main)" : "")").font(.headline)
                        Text("ID: \(display.id)")
                        Text("Frame: \(display.frame.diagnosticDescription)")
                        Text("Visible frame: \(display.visibleFrame.diagnosticDescription)")
                        Text("Scale: \(display.backingScale.formatted())×")
                    }
                    .fontDesign(.monospaced)
                    if display.id != model.displays.last?.id { Divider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .accessibilityIdentifier("displaysSection")
    }

    private var externalTestModeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("EXTERNAL WINDOW TEST MODE", systemImage: "exclamationmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("BlazaresSpaces may modify only the external window explicitly selected below. Discovery and Refresh remain read-only.")
                    .foregroundStyle(.secondary)

                if let selectedID = model.selectedTestWindowID {
                    if let selected = model.windows.first(where: { $0.runtimeIdentity == selectedID }) {
                        Text("Selected external test window: \(selected.applicationName) · PID \(selected.runtimeIdentity.processIdentifier) · \(selected.bundleIdentifier ?? "Bundle unavailable")")
                            .fontDesign(.monospaced)
                    } else {
                        Text("Selected external test window: PID \(selectedID.processIdentifier) · no longer discovered")
                            .fontDesign(.monospaced)
                    }
                    HStack {
                        Button("Capture Selected Window") { model.captureSelectedWindow() }
                        Button("Restore Selected Window") { model.restoreSelectedWindow() }
                    }
                }

                if !model.selectedTestSetIDs.isEmpty {
                    Text("Selected test set: \(model.selectedTestSetIDs.count) window(s)")
                    HStack {
                        Button("Capture Selected Test Set") { model.captureSelectedTestSet() }
                        Button("Restore Selected Test Set") { model.restoreSelectedTestSet() }
                    }
                }

                if let status = model.actionStatus {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .tint(.orange)
    }

    private var workspaceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("EXPERIMENTAL GLOBAL WORKSPACES", systemImage: "square.3.layers.3d")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Workspaces are logical and span all connected displays. Only windows explicitly selected in External Window Test Mode can be assigned or controlled; discovery remains read-only.")
                    .foregroundStyle(.secondary)
                HStack {
                    if !model.experimentalWorkspaceModeEnabled {
                        Button("Enter Experimental Workspace Mode") { model.enterExperimentalWorkspaceMode() }
                    } else {
                        Button("RECOVER MANAGED WINDOWS") { model.recoverManagedWindows() }
                        Button("Exit Experimental Mode & Recover Windows") { model.exitExperimentalWorkspaceMode() }
                    }
                    Button("Add Workspace") { model.addWorkspace() }
                }

                ForEach(model.workspaceIDs) { id in
                    let workspace = model.workspaceManager.workspace(for: id)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            TextField("Workspace name", text: Binding(
                                get: { workspaceNameDrafts[id.rawValue] ?? workspace.name },
                                set: { workspaceNameDrafts[id.rawValue] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.renameWorkspace(id, name: workspaceNameDrafts[id.rawValue] ?? workspace.name) }
                            if model.workspaceManager.activeWorkspaceID == id {
                                Label("Active", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button("Activate") { model.activateWorkspace(id) }
                            }
                            if model.workspaceIDs.count > 1 {
                                Button("Delete", role: .destructive) { model.deleteWorkspace(id) }
                            }
                        }
                        Text("Members: (workspace.members.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(workspace.members) { member in
                            Text("• (member.authorizedWindow.applicationName) · PID (member.authorizedWindow.processIdentifier)\(member.visibleOnAllWorkspaces ? " · all workspaces" : "")")
                                .font(.caption)
                                .fontDesign(.monospaced)
                        }
                    }
                    .padding(6)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                }

                if let result = model.workspaceSwitchResult {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last workspace operation: " + (result.sourceWorkspaceID?.rawValue ?? "recovery/entry") + " → " + result.targetWorkspaceID.rawValue)
                            .font(.callout.bold())
                        Text("Processed \(result.metrics.windowsProcessed) · captured \(result.capturedCount) · parked \(result.parkedCount) · restored \(result.restoredCount) · adjusted \(result.adjustedCount) · missing \(result.missingCount) · failed \(result.failedCount)")
                            .font(.caption)
                        Text(String(format: "Timing: total %.1f ms · capture %.1f ms · parking %.1f ms · restore %.1f ms", result.metrics.totalMilliseconds, result.metrics.captureMilliseconds, result.metrics.parkingMilliseconds, result.metrics.restoreMilliseconds))
                            .font(.caption)
                            .fontDesign(.monospaced)
                        ForEach(result.results) { item in
                            Text(item.applicationName + " · " + item.operation.displayName + " · " + item.outcome.displayName + ": " + item.message)
                                .font(.caption2)
                                .foregroundStyle(item.outcome == .failed || item.outcome == .missing ? .red : .secondary)
                        }
                    }
                    .padding(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .tint(.orange)
    }

    private var windowsSection: some View {
        GroupBox("Manageable windows: \(model.windows.count)") {
            VStack(alignment: .leading, spacing: 10) {
                if !model.accessibilityGranted {
                    Text("Grant Accessibility permission, then click Refresh.")
                        .foregroundStyle(.secondary)
                } else if model.windows.isEmpty {
                    Text("No manageable windows were found.").foregroundStyle(.secondary)
                }
                Toggle("Show window titles (may contain sensitive information)", isOn: $showWindowTitles)
                Text("Only windows exposing a usable AX runtime identifier can be explicitly selected for external mutation tests. All other discovered windows remain read-only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(model.windows) { window in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(window.applicationName).font(.headline)
                        if showWindowTitles {
                            Text(window.title?.isEmpty == false ? window.title! : "Untitled window")
                                .lineLimit(1)
                                .help(window.title ?? "")
                        }
                        Text("PID: \(window.runtimeIdentity.processIdentifier)  Bundle: \(window.bundleIdentifier ?? "Unavailable")")
                        Text("AX ID: \(window.runtimeIdentity.accessibilityIdentifier ?? "Unavailable")  Subrole: \(window.subrole ?? "Unavailable")")
                        Text("Frame: \(window.frame.diagnosticDescription)  Display: \(window.displayID.map(String.init) ?? "Unmapped")")
                        Text("Minimized: \(window.isMinimized.diagnosticDescription)  Fullscreen: \(window.isFullscreen.diagnosticDescription)")
                        if let exclusionReason = model.exclusionReason(for: window) {
                            Label("NEVER MANAGE — \(exclusionReason)", systemImage: "nosign")
                                .foregroundStyle(.red)
                        } else {
                            HStack {
                                Button(model.selectedTestWindowID == window.runtimeIdentity ? "Selected Test Window" : "Use as Capture/Restore Test Window") {
                                    model.selectTestWindow(window)
                                }
                                Toggle("Test set", isOn: Binding(
                                    get: { model.isSelectedInTestSet(window) },
                                    set: { model.setTestSetSelection(window, selected: $0) }
                                ))
                                .toggleStyle(.checkbox)
                            }
                            if model.isExplicitlyAuthorizedForWorkspace(window) {
                                HStack {
                                    Menu("Workspace membership") {
                                        ForEach(model.workspaceIDs) { workspaceID in
                                            Button("Move to \(model.workspaceName(workspaceID))") {
                                                model.assignWindow(window, to: workspaceID, move: true)
                                            }
                                            Button("Add to \(model.workspaceName(workspaceID))") {
                                                model.assignWindow(window, to: workspaceID, move: false)
                                            }
                                        }
                                        Button("Show on all workspaces") {
                                            model.setWindowVisibleOnAllWorkspaces(window, visible: true)
                                        }
                                        Button("Stop showing on all workspaces") {
                                            model.setWindowVisibleOnAllWorkspaces(window, visible: false)
                                        }
                                    }
                                    let memberships = model.workspaceMembership(for: window)
                                    Text(memberships.isEmpty ? "Unassigned" : memberships.map { model.workspaceName($0) }.sorted().joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .fontDesign(.monospaced)
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func snapshotSection(_ snapshot: WorkspaceSnapshot) -> some View {
        GroupBox("Last read-only desktop snapshot") {
            VStack(alignment: .leading, spacing: 5) {
                Text("Captured windows: \(snapshot.windows.count)")
                Text("Displays represented: \(snapshot.representedDisplayIDs.count)")
                Text("Captured: \(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                Text("No external windows were changed.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func selectedSetSnapshotSection(_ snapshot: WorkspaceSnapshot) -> some View {
        GroupBox("Selected test-set snapshot") {
            VStack(alignment: .leading, spacing: 5) {
                Text("Captured windows: \(snapshot.windows.count)")
                Text("Displays represented: \(snapshot.representedDisplayIDs.count)")
                Text("Read-only capture; no windows were changed.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func restoreReportSection(_ report: WindowRestoreReport) -> some View {
        GroupBox("Restore completed") {
            VStack(alignment: .leading, spacing: 7) {
                Text("\(report.requestedCount) windows requested · \(report.exactCount) exact · \(report.adjustedCount) adjusted · \(report.failedCount) failed · \(report.excludedCount) excluded")
                ForEach(report.results) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(result.applicationName) (PID \(result.processIdentifier)): \(result.status.displayName)")
                        Text(result.message).foregroundStyle(.secondary)
                        if let actualFrame = result.actualFrame {
                            Text("Requested: \(result.requestedFrame.diagnosticDescription) · Actual: \(actualFrame.diagnosticDescription)")
                                .fontDesign(.monospaced)
                        }
                    }
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var issuesSection: some View {
        GroupBox("Discovery issues: \(model.issues.count)") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(model.issues) { issue in
                    Text("\(issue.applicationName) (PID \(issue.processIdentifier)): \(issue.message)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

private extension CGRect {
    var diagnosticDescription: String {
        "x \(Int(minX)), y \(Int(minY)), w \(Int(width)), h \(Int(height))"
    }
}

private extension Optional where Wrapped == Bool {
    var diagnosticDescription: String {
        map { $0 ? "Yes" : "No" } ?? "Unavailable"
    }
}

#Preview {
    ContentView()
}
