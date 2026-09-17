import AppKit
import SwiftUI

struct BlazaresSpacesHomeView: View {
    @EnvironmentObject private var model: DiagnosticsViewModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(BlazaresSpacesAppDelegate.showDockIconDefaultsKey) private var showDockIcon = true
    @State private var dropTargetWorkspace: WorkspaceID?
    @State private var showingOverview = true

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 290)
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 600)
        .task { model.refresh() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)
                        .frame(width: 38, height: 38)
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 18, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("BlazaresSpaces")
                        .font(.headline)
                    Text("Virtual Spaces across displays")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("OVERVIEW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                Button {
                    showingOverview = true
                } label: {
                    Label("All Windows & Screens", systemImage: "rectangle.3.group")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(showingOverview ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)

                Text("VIRTUAL SPACES")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(model.workspaceIDs.enumerated()), id: \.element) { index, id in
                            workspaceSidebarButton(index: index, id: id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                sidebarAction("Previous", icon: "chevron.left") { model.activatePreviousWorkspace() }
                sidebarAction("Next", icon: "chevron.right") { model.activateNextWorkspace() }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(.thinMaterial)
    }

    private func workspaceSidebarButton(index: Int, id: WorkspaceID) -> some View {
        let active = model.workspaceManager.activeWorkspaceID == id
        let isDropTarget = dropTargetWorkspace == id

        return Button {
            showingOverview = false
            model.activateWorkspace(id)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(active ? Color.accentColor : Color.secondary.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Text("\(index + 1)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(active ? .white : .primary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.workspaceName(id))
                        .font(.system(size: 13, weight: active ? .semibold : .medium))
                        .lineLimit(1)
                    Text(isDropTarget ? "Drop window here" : (active ? "Current Virtual Space" : "Switch Virtual Space"))
                        .font(.caption2)
                        .foregroundStyle(isDropTarget ? Color.accentColor : .secondary)
                }

                Spacer()

                if isDropTarget {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Color.accentColor)
                } else if active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                isDropTarget ? Color.accentColor.opacity(0.18) : (active ? Color.accentColor.opacity(0.10) : Color.clear),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isDropTarget ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isNativeActivationInProgress)
        .dropDestination(for: String.self) { items, _ in
            guard let token = items.first,
                  let window = model.windows.first(where: { windowDragToken($0) == token }),
                  model.exclusionReason(for: window) == nil else { return false }
            model.assignWindow(window, to: id, move: true)
            return true
        } isTargeted: { targeted in
            if targeted {
                dropTargetWorkspace = id
            } else if dropTargetWorkspace == id {
                dropTargetWorkspace = nil
            }
        }
    }

    private func sidebarAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .disabled(model.isNativeActivationInProgress)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if showingOverview {
                        overview
                    } else {
                        quickSettings
                        hero
                        virtualSpaceDetail
                        detectedWindows
                    }
                    statusCard
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overview")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Everything discovered on this Mac, and where BlazaresSpaces can assign it.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                overviewMetric("Windows", value: model.windows.count, icon: "macwindow")
                overviewMetric("Screens", value: model.displays.count, icon: "display.2")
                overviewMetric("Virtual Spaces", value: model.workspaceIDs.count, icon: "square.3.layers.3d")
            }

            GroupBox("Connected screens") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.displays) { display in
                        Label(display.name + (display.isMain ? " · Main" : ""), systemImage: "display")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Native Spaces") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.nativeSpaceReadStatus).foregroundStyle(.secondary)
                    Text("Discovery: \(model.nativeSpaceCapabilities.discovery ? "AVAILABLE" : "UNAVAILABLE") · Focus: \(model.nativeSpaceCapabilities.focus ? "AVAILABLE" : "UNAVAILABLE")")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if let topology = model.nativeSpaceTopology {
                        ForEach(topology.displays, id: \.displayIdentifier) { display in
                            let displaySpaces = topology.spaces.filter { $0.displayIdentifier == display.displayIdentifier }
                            let ordinaryCount = displaySpaces.filter { $0.kind == .userDesktop }.count
                            let specialSpaces = displaySpaces.filter { $0.kind != .userDesktop }
                            VStack(alignment: .leading, spacing: 3) {
                                Label("\(display.displayIdentifier): \(ordinaryCount) ordinary Native Space(s)", systemImage: "square.stack.3d.up")
                                if !specialSpaces.isEmpty {
                                    Text("Excluded from Virtual Space mapping: " + specialSpaces.map(\.kind.diagnosticLabel).joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 25)
                                }
                            }
                        }
                    }
                    Text("Saved mappings: \(model.nativeSpaceMappings.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Ensure required Native Spaces") {
                        model.ensureRequiredNativeSpaces()
                    }
                    .disabled(model.isNativeReconciliationInProgress || !model.nativeSpaceCapabilities.create)
                    Text(model.nativeSpaceCapabilities.create
                         ? "Creates and verifies missing Spaces one at a time."
                         : "Creation is unavailable for the current runtime configuration.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            detectedWindows
        }
    }

    private func overviewMetric(_ title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Workspace")
                .font(.headline)
            Spacer()

            if model.isNativeActivationInProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh windows and native Spaces")

            Button {
                openWindow(id: "inspector")
            } label: {
                Image(systemName: "wrench.and.screwdriver")
            }
            .help("Open Inspector")
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Virtual Space")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 58, height: 58)
                    Image(systemName: "rectangle.3.group.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.workspaceName(model.workspaceManager.activeWorkspaceID))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(model.experimentalNativeSpacesEnabled ? "Native macOS Spaces · global multi-display" : "Logical workspace mode")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        model.activatePreviousWorkspace()
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.activateNextWorkspace()
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .disabled(model.isNativeActivationInProgress)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }

    private var quickSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick settings")
                .font(.headline)

            HStack(spacing: 10) {
                settingCard(
                    title: "Native Spaces",
                    subtitle: "Real macOS Spaces",
                    icon: "rectangle.3.group",
                    isOn: Binding(
                        get: { model.experimentalNativeSpacesEnabled },
                        set: { model.setExperimentalNativeSpacesEnabled($0) }
                    )
                )

                settingCard(
                    title: "Global shortcuts",
                    subtitle: "Keyboard switching",
                    icon: "keyboard",
                    isOn: Binding(
                        get: { model.globalShortcutsEnabled },
                        set: { model.setGlobalShortcutsEnabled($0) }
                    )
                )

                settingCard(
                    title: "Show in Dock",
                    subtitle: "Keep Dock icon",
                    icon: "dock.rectangle",
                    isOn: Binding(
                        get: { showDockIcon },
                        set: { value in
                            showDockIcon = value
                            BlazaresSpacesAppDelegate.applyDockVisibility(value)
                        }
                    )
                )
            }
        }
    }

    private func settingCard(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
    }

    private var detectedWindows: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Detected windows")
                        .font(.title3.weight(.semibold))
                    Text("Drag a window onto a Virtual Space in the sidebar to change membership. Screen placement is configured separately below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.windows.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
            }

            if !model.accessibilityGranted {
                Label("Bedienungshilfe is required to discover and manage windows.", systemImage: "hand.raised.fill")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            } else if model.isDiscoveringWindows && model.windows.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Discovering windows…")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            } else if model.windows.isEmpty {
                Text("No manageable windows detected.")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(windowsGroupedByScreen.enumerated()), id: \.offset) { _, group in
                        GroupBox(group.title) {
                            LazyVStack(spacing: 8) {
                                ForEach(group.windows) { window in
                                    detectedWindowRow(window)
                                }
                            }
                            .padding(6)
                        }
                    }
                }
            }
        }
    }

    private var virtualSpaceDetail: some View {
        let workspaceID = model.workspaceManager.activeWorkspaceID
        let workspace = model.workspaceManager.workspace(for: workspaceID)
        let groups = workspaceMembersGroupedByScreen(workspace.members, workspaceID: workspaceID)
        return GroupBox("\(workspace.name) · membership & Screen placement") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Membership (Level 1) controls which Virtual Space contains a window. Screen placement (Level 2) only chooses its connected display; changing it does not change membership.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if workspace.members.isEmpty {
                    Text("No managed windows assigned yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(group.members) { member in
                                HStack {
                                    Label(member.authorizedWindow.applicationName, systemImage: "macwindow")
                                    Spacer()
                                    Text(member.screenAssignments[workspaceID]?.displayName ?? "No screen preference")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Menu("Move to Screen") {
                                        ForEach(model.displays) { display in
                                            Button(display.name) {
                                                if let window = model.windows.first(where: { $0.runtimeIdentity == member.id }) {
                                                    model.assignWindow(window, toScreen: display, in: workspaceID)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Discovery is grouped by the currently observed Screen, independently
    /// from Virtual Space membership (which may be many-to-many).
    private var windowsGroupedByScreen: [(title: String, windows: [WindowSnapshot])] {
        var groups: [(title: String, windows: [WindowSnapshot])] = model.displays.map { display in
            (title: "Screen · \(display.name)", windows: [])
        }
        var unassigned: [WindowSnapshot] = []

        for window in model.windows {
            guard let display = screen(for: window),
                  let index = model.displays.firstIndex(where: { $0.id == display.id }) else {
                unassigned.append(window)
                continue
            }
            groups[index].windows.append(window)
        }

        if !unassigned.isEmpty {
            groups.append((title: "Screen · Unassigned", windows: unassigned))
        }
        return groups.filter { !$0.windows.isEmpty }
    }

    private func screen(for window: WindowSnapshot) -> DisplaySnapshot? {
        if let displayID = window.displayID,
           let display = model.displays.first(where: { $0.id == displayID }) {
            return display
        }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        return model.displays.min { lhs, rhs in
            let left = CGPoint(x: lhs.frame.midX, y: lhs.frame.midY)
            let right = CGPoint(x: rhs.frame.midX, y: rhs.frame.midY)
            return hypot(left.x - center.x, left.y - center.y) < hypot(right.x - center.x, right.y - center.y)
        }
    }

    private func workspaceMembersGroupedByScreen(
        _ members: [WorkspaceMember],
        workspaceID: WorkspaceID
    ) -> [(title: String, members: [WorkspaceMember])] {
        var groups: [(title: String, members: [WorkspaceMember])] = model.displays.map { display in
            (title: "Screen · \(display.name)", members: [])
        }
        var unassigned: [WorkspaceMember] = []
        for member in members {
            guard let assignment = member.screenAssignments[workspaceID],
                  let index = model.displays.firstIndex(where: { $0.id == assignment.displayID }) else {
                unassigned.append(member)
                continue
            }
            groups[index].members.append(member)
        }
        if !unassigned.isEmpty {
            groups.append((title: "Screen · Unassigned", members: unassigned))
        }
        return groups.filter { !$0.members.isEmpty }
    }

    private func detectedWindowRow(_ window: WindowSnapshot) -> some View {
        let exclusion = model.exclusionReason(for: window)
        let memberships = model.workspaceMembership(for: window)
        let managed = model.isManaged(window)

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: 42, height: 42)
                Image(systemName: "macwindow")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(window.applicationName)
                        .font(.subheadline.weight(.semibold))
                    if managed {
                        Text("Managed")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    if exclusion != nil {
                        Text("NEVER MANAGE")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                Text(window.title?.isEmpty == false ? window.title! : (window.bundleIdentifier ?? "Window"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !memberships.isEmpty {
                    Text(memberships.map { model.workspaceName($0) }.sorted().joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if exclusion == nil {
                Menu {
                    ForEach(model.workspaceIDs) { workspaceID in
                        Button("Move to \(model.workspaceName(workspaceID))") {
                            model.assignWindow(window, to: workspaceID, move: true)
                        }
                    }
                } label: {
                    Label("Move", systemImage: "arrow.right")
                }
                .menuStyle(.borderlessButton)

                Menu {
                    ForEach(model.workspaceIDs) { workspaceID in
                        Button("Add to \(model.workspaceName(workspaceID))") {
                            model.assignWindow(window, to: workspaceID, move: false)
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
            }

            Image(systemName: exclusion == nil ? "line.3.horizontal" : "lock.fill")
                .foregroundStyle(.tertiary)
                .help(exclusion == nil ? "Drag this window onto a Virtual Space in the sidebar" : (exclusion ?? "Excluded"))
        }
        .padding(12)
        .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        }
        .draggable(exclusion == nil ? windowDragToken(window) : "")
    }

    private func windowDragToken(_ window: WindowSnapshot) -> String {
        let identity = window.runtimeIdentity
        return "window|\(identity.processIdentifier)|\(identity.accessibilityIdentifier ?? "")|\(identity.enumerationIndex)"
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.workspaceSwitchState.isDegraded ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(model.workspaceSwitchState.isDegraded ? .orange : .green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.workspaceSwitchState.isDegraded ? "Needs attention" : "System ready")
                    .font(.subheadline.weight(.semibold))
                Text(model.actionStatus ?? model.nativeSpaceReadStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
