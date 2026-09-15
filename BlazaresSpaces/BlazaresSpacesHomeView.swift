import AppKit
import SwiftUI

struct BlazaresSpacesHomeView: View {
    @EnvironmentObject private var model: DiagnosticsViewModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(BlazaresSpacesAppDelegate.showDockIconDefaultsKey) private var showDockIcon = true

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        } detail: {
            detail
        }
        .frame(minWidth: 860, minHeight: 560)
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
                    Text("Global desktops")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(model.workspaceIDs.enumerated()), id: \.element) { index, id in
                        workspaceSidebarButton(index: index, id: id)
                    }
                }
                .padding(10)
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
        return Button {
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
                    Text(active ? "Current desktop" : "Switch desktop")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(active ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(model.isNativeActivationInProgress)
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
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    workspaceGrid
                    quickSettings
                    statusCard
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Desktops")
                .font(.headline)
            Spacer()

            if model.isNativeActivationInProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                model.refreshNativeSpaceTopology()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh native Spaces")

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
            Text("Current desktop")
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

    private var workspaceGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Switch desktop")
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(Array(model.workspaceIDs.enumerated()), id: \.element) { index, id in
                    workspaceCard(index: index, id: id)
                }
            }
        }
    }

    private func workspaceCard(index: Int, id: WorkspaceID) -> some View {
        let active = model.workspaceManager.activeWorkspaceID == id
        return Button {
            model.activateWorkspace(id)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(index + 1)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(active ? .white : .primary)
                        .frame(width: 38, height: 38)
                        .background(active ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    Spacer()
                    Image(systemName: active ? "checkmark.circle.fill" : "arrow.right.circle")
                        .font(.title3)
                        .foregroundStyle(active ? Color.accentColor : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.workspaceName(id))
                        .font(.headline)
                        .lineLimit(1)
                    Text(active ? "Active on all displays" : "Switch all displays")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .background(active ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(active ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isNativeActivationInProgress)
    }

    private var quickSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick settings")
                .font(.title3.weight(.semibold))

            HStack(spacing: 12) {
                settingCard(
                    title: "Native Spaces",
                    subtitle: "Switch real macOS desktops",
                    icon: "rectangle.3.group",
                    isOn: Binding(
                        get: { model.experimentalNativeSpacesEnabled },
                        set: { model.setExperimentalNativeSpacesEnabled($0) }
                    )
                )

                settingCard(
                    title: "Global shortcuts",
                    subtitle: "Keyboard desktop switching",
                    icon: "keyboard",
                    isOn: Binding(
                        get: { model.globalShortcutsEnabled },
                        set: { model.setGlobalShortcutsEnabled($0) }
                    )
                )

                settingCard(
                    title: "Show in Dock",
                    subtitle: "Keep an app icon in the Dock",
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
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
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
