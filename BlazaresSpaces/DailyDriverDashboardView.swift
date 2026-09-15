import SwiftUI

struct DailyDriverDashboardView: View {
    @EnvironmentObject private var model: DiagnosticsViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var workspaceNameDrafts: [String: String] = [:]
    @State private var showAdvancedDiagnostics = false
    @State private var newExcludedApplication = ""
    @State private var newExcludedBundlePrefix = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    safetyBanner
                    safetyExclusions
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
                Text("Active Virtual Space: \(model.workspaceName(model.workspaceManager.activeWorkspaceID))")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("activeDesktopStatus")
                Label(statusSummary, systemImage: statusSymbol)
                    .font(.callout)
                    .foregroundStyle(model.workspaceSwitchState.isDegraded ? .orange : .secondary)
            }

            Spacer()

            Button("Previous") { model.activatePreviousWorkspace() }
                .disabled(model.isNativeActivationInProgress || (!model.experimentalWorkspaceModeEnabled && !model.experimentalNativeSpacesEnabled))
            Button("Next") { model.activateNextWorkspace() }
                .disabled(model.isNativeActivationInProgress || (!model.experimentalWorkspaceModeEnabled && !model.experimentalNativeSpacesEnabled))
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
        GroupBox("Virtual Spaces") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if model.experimentalWorkspaceModeEnabled {
                        Button("Recover Managed Windows") { model.recoverManagedWindows() }
                            .buttonStyle(.borderedProminent)
                        Button("Exit & Recover") { model.exitExperimentalWorkspaceMode() }
                    } else {
                        Button("Enable Virtual Space Switching") { model.enterExperimentalWorkspaceMode() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.accessibilityGranted)
                            .accessibilityIdentifier("enableDesktopSwitchingButton")
                    }

                    Button("Add Virtual Space") { model.addWorkspace() }
                        .accessibilityIdentifier("addWorkspaceButton")

                    Spacer()

                    Toggle("Global shortcuts", isOn: Binding(
                        get: { model.globalShortcutsEnabled },
                        set: { model.setGlobalShortcutsEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .disabled(!model.accessibilityGranted)

                    Toggle("Experimental native activation", isOn: Binding(
                        get: { model.experimentalNativeSpacesEnabled },
                        set: { model.setExperimentalNativeSpacesEnabled($0) }
                    ))
                    .toggleStyle(.switch)

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

                if model.isNativeActivationInProgress {
                    ProgressView("Native Space activation in progress…")
                        .controlSize(.small)
                }

                GroupBox("Native macOS Spaces") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Experimental native integration. Existing Spaces may be activated; creation, deletion and window movement are not automatic yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(model.nativeSpaceReadStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Refresh Native Spaces") { model.refreshNativeSpaceTopology() }
                        }
                        if let topology = model.nativeSpaceTopology {
                            let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
                            ForEach(Array(model.workspaceIDs.enumerated()), id: \.element) { offset, id in
                                let binding = bindings.first { $0.virtualSpacePosition == offset + 1 }
                                Text("\(offset + 1) \(model.workspaceName(id)): " + nativeBindingText(binding))
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                            }
                        } else {
                            Text("No native topology available. Virtual Spaces remain logical.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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

    private var safetyExclusions: some View {
        GroupBox("Safety exclusions") {
            VStack(alignment: .leading, spacing: 6) {
                Label("NEVER MANAGE", systemImage: "nosign")
                    .foregroundStyle(.red)
                Text("These applications are discovered for visibility only and can never be moved, parked, resized, hidden, or restored by BlazaresSpaces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.excludedApplicationNames, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Remove") {
                            model.updateManagementExclusions(
                                applicationNames: model.excludedApplicationNames.filter { $0 != name },
                                bundlePrefixes: model.excludedBundleIdentifierPrefixes
                            )
                        }
                    }
                }
                ForEach(model.excludedBundleIdentifierPrefixes, id: \.self) { prefix in
                    HStack {
                        Text("Bundle prefix: \(prefix)")
                        Spacer()
                        Button("Remove") {
                            model.updateManagementExclusions(
                                applicationNames: model.excludedApplicationNames,
                                bundlePrefixes: model.excludedBundleIdentifierPrefixes.filter { $0 != prefix }
                            )
                        }
                    }
                }
                HStack {
                    TextField("Application to exclude", text: $newExcludedApplication)
                    Button("Add") {
                        let value = newExcludedApplication.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        model.updateManagementExclusions(
                            applicationNames: model.excludedApplicationNames + [value],
                            bundlePrefixes: model.excludedBundleIdentifierPrefixes
                        )
                        newExcludedApplication = ""
                    }
                }
                HStack {
                    TextField("Bundle prefix to exclude", text: $newExcludedBundlePrefix)
                    Button("Add") {
                        let value = newExcludedBundlePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        model.updateManagementExclusions(
                            applicationNames: model.excludedApplicationNames,
                            bundlePrefixes: model.excludedBundleIdentifierPrefixes + [value]
                        )
                        newExcludedBundlePrefix = ""
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .accessibilityIdentifier("safetyExclusionsSection")
    }

    private func desktopRow(_ id: WorkspaceID) -> some View {
        let workspace = model.workspaceManager.workspace(for: id)
        let isActive = model.workspaceManager.activeWorkspaceID == id
        let otherIDs = model.workspaceIDs.filter { $0 != id }

        return HStack(spacing: 10) {
            Image(systemName: isActive ? "circle.inset.filled" : "circle")
                .foregroundStyle(isActive ? .green : .secondary)

            TextField("Virtual Space name", text: workspaceNameBinding(id, currentName: workspace.name))
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
                    .disabled(model.isNativeActivationInProgress || (!model.experimentalWorkspaceModeEnabled && !model.experimentalNativeSpacesEnabled))
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
                        Menu("Move to Virtual Space") {
                            ForEach(model.workspaceIDs) { workspaceID in
                                Button(model.workspaceName(workspaceID)) {
                                    model.assignWindow(window, to: workspaceID, move: true)
                                }
                            }
                        }

                        Menu("Show on Virtual Space") {
                            ForEach(model.workspaceIDs) { workspaceID in
                                Button(model.workspaceName(workspaceID)) {
                                    model.assignWindow(window, to: workspaceID, move: false)
                                }
                            }
                        }

                        Button(model.isWindowSticky(window) ? "Remove from All Virtual Spaces" : "Show on All Virtual Spaces") {
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
                        Text(memberships.isEmpty ? "No Virtual Space membership" : memberships.map { model.workspaceName($0) }.sorted().joined(separator: ", "))
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
                Text("Displays: \(model.displays.count) · Discovered windows: \(model.windows.count) · Discovery issues: \(model.issues.count)\(model.isDiscoveringWindows ? " · AX discovery in progress" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Open Inspector") { openWindow(id: "inspector") }
                    Button("Window Control Lab") { openWindow(id: "window-control-lab") }
                    Button("Capture Read-Only macOS Spaces Snapshot") { model.captureAllWindows() }
                }

                if let result = model.workspaceSwitchResult {
                    Text("Last switch: processed \(result.metrics.windowsProcessed), parked \(result.parkedCount), restored \(result.restoredCount), failed \(result.failedCount), total \(result.metrics.totalMilliseconds.formatted()) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !model.issues.isEmpty {
                    Text("Accessibility discovery details")
                        .font(.headline)
                    ForEach(model.issues) { issue in
                        Text("• \(issue.applicationName) (PID \(issue.processIdentifier)): \(issue.message)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }

                if !model.nativeSpaceOperationLog.isEmpty {
                    Text("Native Spaces operation log")
                        .font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(model.nativeSpaceOperationLog.enumerated()), id: \.offset) { _, entry in
                                Text(entry)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
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

    private func nativeBindingText(_ binding: NativeVirtualSpaceBinding?) -> String {
        guard let binding else { return "native Space unavailable" }
        return binding.spacesByDisplay.map { "\($0.key)=runtime \($0.value.runtimeID)" }
            .sorted().joined(separator: ", ")
    }

    private var statusSummary: String {
        switch model.workspaceSwitchState {
        case .idle: return model.experimentalWorkspaceModeEnabled ? "Virtual Space switching ready" : "Virtual Space switching disabled"
        case .switching: return "Switching Virtual Spaces…"
        case .recovering: return "Recovering managed windows…"
        case .degraded: return "Virtual Space switching paused"
        }
    }

    private var statusSymbol: String {
        model.workspaceSwitchState.isDegraded ? "exclamationmark.triangle.fill" : "circle.fill"
    }
}
