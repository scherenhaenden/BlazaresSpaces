import SwiftUI

struct DailyDriverDashboardView: View {
    @EnvironmentObject private var model: DiagnosticsViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var workspaceNameDrafts: [String: String] = [:]
    @State private var showAdvancedDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    safetyBanner
                    desktopController
                    managedWindows
                    restoration
                    diagnostics
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 620)
        .task { model.refresh() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BlazaresSpaces")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("dailyDriverTitle")
                Text("Personal Daily Driver · 0.3.0")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Active desktop: \(model.workspaceName(model.workspaceManager.activeWorkspaceID))")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("activeDesktopStatus")
                Label(statusSummary, systemImage: statusSymbol)
                    .font(.callout)
                    .foregroundStyle(model.workspaceSwitchState.isDegraded ? .orange : .secondary)
            }

            Spacer()

            Button("Previous") { model.activatePreviousWorkspace() }
                .disabled(!model.experimentalWorkspaceModeEnabled)
            Button("Next") { model.activateNextWorkspace() }
                .disabled(!model.experimentalWorkspaceModeEnabled)
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var safetyBanner: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(model.accessibilityGranted ? .green : .orange)

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.accessibilityGranted ? "Ready for explicit window management" : "Accessibility permission required")
                        .font(.headline)
                        .accessibilityIdentifier("accessibilityStatus")
                    Text("Discovery remains read-only. Only explicitly managed windows may be moved, parked, restored or recovered. NEVER MANAGE exclusions stay untouched.")
                        .foregroundStyle(.secondary)
                    Text("State: \(model.workspaceSwitchState.displayName) · \(model.persistenceStatus.displayName)")
                        .font(.caption)
                        .foregroundStyle(model.workspaceSwitchState.isDegraded ? .red : .secondary)
                }

                Spacer()

                if !model.accessibilityGranted {
                    Button("Request Access") { model.requestAccessibilityAccess() }
                    Button("Open Settings") { model.openAccessibilitySettings() }
                }
            }
            .padding(8)
        }
    }

    private var desktopController: some View {
        GroupBox("Desktops") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if model.experimentalWorkspaceModeEnabled {
                        Button("Recover Managed Windows") { model.recoverManagedWindows() }
                            .buttonStyle(.borderedProminent)
                        Button("Exit & Recover") { model.exitExperimentalWorkspaceMode() }
                    } else {
                        Button("Enable Desktop Switching") { model.enterExperimentalWorkspaceMode() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.accessibilityGranted)
                            .accessibilityIdentifier("enableDesktopSwitchingButton")
                    }

                    Button("Add Desktop") { model.addWorkspace() }
                        .accessibilityIdentifier("addWorkspaceButton")

                    Spacer()

                    Toggle("Global shortcuts", isOn: Binding(
                        get: { model.globalShortcutsEnabled },
                        set: { model.setGlobalShortcutsEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .disabled(!model.accessibilityGranted)
                }

                if model.workspaceTopologyChanged {
                    Label("Display topology changed. Switching is paused until recovery/validation.", systemImage: "display.trianglebadge.exclamationmark")
                        .foregroundStyle(.orange)
                }

                if case let .degraded(message) = model.workspaceSwitchState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                ForEach(model.workspaceIDs) { id in
                    desktopRow(id)
                }

                if let status = model.actionStatus {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .accessibilityIdentifier("dailyDriverDesktopManager")
    }

    private func desktopRow(_ id: WorkspaceID) -> some View {
        let workspace = model.workspaceManager.workspace(for: id)
        let isActive = model.workspaceManager.activeWorkspaceID == id
        let otherIDs = model.workspaceIDs.filter { $0 != id }

        return HStack(spacing: 10) {
            Image(systemName: isActive ? "circle.inset.filled" : "circle")
                .foregroundStyle(isActive ? .green : .secondary)

            TextField("Desktop name", text: workspaceNameBinding(id, currentName: workspace.name))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)
                .onSubmit {
                    model.renameWorkspace(id, name: workspaceNameDrafts[id.rawValue] ?? workspace.name)
                }

            Text("\(workspace.members.count) managed")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if !isActive {
                Button("Activate") { model.activateWorkspace(id) }
                    .disabled(!model.experimentalWorkspaceModeEnabled)
            } else {
                Text("Active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Button("↑") { model.reorderWorkspace(id, by: -1) }
                .disabled(model.workspaceIDs.first == id)
            Button("↓") { model.reorderWorkspace(id, by: 1) }
                .disabled(model.workspaceIDs.last == id)

            if !otherIDs.isEmpty {
                Menu("Delete") {
                    ForEach(otherIDs) { destination in
                        Button("Delete and move exclusive windows to \(model.workspaceName(destination))", role: .destructive) {
                            model.deleteWorkspace(id, destination: destination)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(isActive ? Color.green.opacity(0.08) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var managedWindows: some View {
        GroupBox("Windows") {
            VStack(alignment: .leading, spacing: 10) {
                if !model.accessibilityGranted {
                    Text("Grant Accessibility permission and refresh to discover manageable windows.")
                        .foregroundStyle(.secondary)
                } else if model.windows.isEmpty {
                    Text("No windows discovered.")
                        .foregroundStyle(.secondary)
                }

                ForEach(model.windows) { window in
                    windowRow(window)
                }
            }
            .padding(8)
        }
        .accessibilityIdentifier("dailyDriverWindowsSection")
    }

    private func windowRow(_ window: WindowSnapshot) -> some View {
        let managed = model.isManaged(window)
        let memberships = model.workspaceMembership(for: window)
        let exclusion = model.exclusionReason(for: window)

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.applicationName)
                        .font(.headline)
                    Text("PID \(window.runtimeIdentity.processIdentifier) · \(window.bundleIdentifier ?? "Unknown bundle")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let exclusion {
                    Label("NEVER MANAGE", systemImage: "nosign")
                        .foregroundStyle(.red)
                        .help(exclusion)
                } else if managed && model.isWindowSticky(window) {
                    Label("Sticky · Managed", systemImage: "pin.fill")
                        .foregroundStyle(.blue)
                } else if managed {
                    Label("Managed", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Unmanaged")
                        .foregroundStyle(.secondary)
                }
            }

            if exclusion == nil {
                HStack {
                    if managed {
                        Menu("Move to Desktop") {
                            ForEach(model.workspaceIDs) { workspaceID in
                                Button(model.workspaceName(workspaceID)) {
                                    model.assignWindow(window, to: workspaceID, move: true)
                                }
                            }
                        }

                        Menu("Show on Desktop") {
                            ForEach(model.workspaceIDs) { workspaceID in
                                Button(model.workspaceName(workspaceID)) {
                                    model.assignWindow(window, to: workspaceID, move: false)
                                }
                            }
                        }

                        Button(model.isWindowSticky(window) ? "Remove from All Desktops" : "Show on All Desktops") {
                            model.setWindowVisibleOnAllWorkspaces(window, visible: !model.isWindowSticky(window))
                        }

                        Button("Stop Managing", role: .destructive) {
                            model.stopManagingWindow(window)
                        }
                    } else {
                        Button("Manage This Window") {
                            model.manageWindow(window)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Spacer()

                    if managed {
                        Text(memberships.isEmpty ? "No desktop membership" : memberships.map { model.workspaceName($0) }.sorted().joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var restoration: some View {
        GroupBox("Session Restoration") {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.persistenceStatus.displayName)
                    .font(.callout.weight(.semibold))

                if model.restorationItems.isEmpty {
                    Text("No restoration decisions are waiting for review.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Saved window associations are conservative: only high-confidence candidates can be confirmed; ambiguous matches are never guessed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(model.restorationItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.applicationName)
                                Text(item.match.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.canConfirm {
                                Button("Restore") { model.confirmRestoration(item) }
                            }
                        }
                    }
                }

                if case .corrupted = model.persistenceStatus {
                    Button("Reset Saved Configuration", role: .destructive) {
                        model.resetPersistedConfiguration()
                    }
                }
            }
            .padding(8)
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("Advanced Diagnostics", isExpanded: $showAdvancedDiagnostics) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Displays: \(model.displays.count) · Discovered windows: \(model.windows.count) · Discovery issues: \(model.issues.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Open Inspector") { openWindow(id: "inspector") }
                    Button("Window Control Lab") { openWindow(id: "window-control-lab") }
                    Button("Capture Read-Only Desktop Snapshot") { model.captureAllWindows() }
                }

                if let result = model.workspaceSwitchResult {
                    Text("Last switch: processed \(result.metrics.windowsProcessed), parked \(result.parkedCount), restored \(result.restoredCount), failed \(result.failedCount), total \(result.metrics.totalMilliseconds.formatted()) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func workspaceNameBinding(_ id: WorkspaceID, currentName: String) -> Binding<String> {
        Binding(
            get: { workspaceNameDrafts[id.rawValue] ?? currentName },
            set: { workspaceNameDrafts[id.rawValue] = $0 }
        )
    }

    private var statusSummary: String {
        switch model.workspaceSwitchState {
        case .idle: return model.experimentalWorkspaceModeEnabled ? "Desktop switching ready" : "Desktop switching disabled"
        case .switching: return "Switching desktops…"
        case .recovering: return "Recovering managed windows…"
        case .degraded: return "Desktop switching paused"
        }
    }

    private var statusSymbol: String {
        model.workspaceSwitchState.isDegraded ? "exclamationmark.triangle.fill" : "circle.fill"
    }
}
