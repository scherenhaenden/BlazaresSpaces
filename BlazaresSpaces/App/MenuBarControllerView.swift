import AppKit
import SwiftUI

struct MenuBarControllerView: View {
    @EnvironmentObject private var model: DiagnosticsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Desktop")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.workspaceName(model.workspaceManager.activeWorkspaceID))
                .font(.headline)
                .accessibilityIdentifier("menuBarActiveDesktop")
            Label(menuStateText, systemImage: menuStateSymbol)
                .font(.caption)
                .foregroundStyle(model.workspaceSwitchState.isDegraded ? .orange : .secondary)
                .help(menuStateHelp)
            Divider()
            ForEach(model.workspaceIDs) { id in
                Button {
                    model.activateWorkspace(id)
                } label: {
                    HStack {
                        Image(systemName: model.workspaceManager.activeWorkspaceID == id ? "checkmark.circle.fill" : "circle")
                        Text(model.workspaceName(id))
                        Spacer()
                    }
                }
            }
            Divider()
            Button("Next Desktop") { model.activateNextWorkspace() }
                .disabled(model.workspaceSwitchState.isDegraded && model.workspaceTopologyChanged)
            Button("Previous Desktop") { model.activatePreviousWorkspace() }
                .disabled(model.workspaceSwitchState.isDegraded && model.workspaceTopologyChanged)
            Button("Recover Managed Windows") { model.recoverManagedWindows() }
                .disabled(!model.accessibilityGranted)
            if model.experimentalWorkspaceModeEnabled {
                Button("Exit & Recover") { model.exitExperimentalWorkspaceMode() }
            } else {
                Button("Enable Desktop Switching") { model.enterExperimentalWorkspaceMode() }
                    .disabled(!model.accessibilityGranted)
            }
            Toggle("Global shortcuts", isOn: Binding(
                get: { model.globalShortcutsEnabled },
                set: { model.setGlobalShortcutsEnabled($0) }
            ))
            .disabled(!model.accessibilityGranted)
            Divider()
            currentWindowSection
            Divider()
            Button("Open BlazaresSpaces") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        .padding(10)
        .frame(width: 240)
    }

    @ViewBuilder
    private var currentWindowSection: some View {
        Text("Current Window")
            .font(.caption)
            .foregroundStyle(.secondary)

        if let window = currentExternalWindow {
            let managed = model.isManaged(window)
            let sticky = model.isWindowSticky(window)
            let exclusion = model.exclusionReason(for: window)

            Label(windowDisplayName(window), systemImage: managed ? "checkmark.square" : "square")
                .lineLimit(1)
                .help(windowHelp(window, managed: managed, sticky: sticky, exclusion: exclusion))

            if let exclusion {
                Label("NEVER MANAGE", systemImage: "nosign")
                    .foregroundStyle(.secondary)
                    .help(exclusion)
            } else if managed {
                Text(sticky ? "Managed · Sticky" : "Managed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                managedWindowActions(window)
            } else {
                Text("Unmanaged")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                unmanagedWindowActions(window)
            }
        } else {
            Label("No external window", systemImage: "macwindow")
                .foregroundStyle(.secondary)
                .help("Bring an external application window to the front, then reopen this menu.")
        }
    }

    @ViewBuilder
    private func managedWindowActions(_ window: WindowSnapshot) -> some View {
        Menu("Move") {
            workspaceActionButtons(for: window, move: true)
        }
        Menu("Show") {
            workspaceActionButtons(for: window, move: false)
        }
        Toggle("Show on All Desktops", isOn: Binding(
            get: { model.isWindowSticky(window) },
            set: { model.setWindowVisibleOnAllWorkspaces(window, visible: $0) }
        ))
    }

    @ViewBuilder
    private func unmanagedWindowActions(_ window: WindowSnapshot) -> some View {
        Menu("Manage & Move") {
            manageAndWorkspaceActionButtons(for: window, move: true)
        }
        Menu("Manage & Show") {
            manageAndWorkspaceActionButtons(for: window, move: false)
        }
    }

    @ViewBuilder
    private func workspaceActionButtons(for window: WindowSnapshot, move: Bool) -> some View {
        ForEach(model.workspaceIDs) { workspaceID in
            Button(model.workspaceName(workspaceID)) {
                if move {
                    model.moveFocusedWindow(to: workspaceID)
                } else {
                    model.showFocusedWindow(on: workspaceID)
                }
            }
        }
    }

    @ViewBuilder
    private func manageAndWorkspaceActionButtons(for window: WindowSnapshot, move: Bool) -> some View {
        ForEach(model.workspaceIDs) { workspaceID in
            Button(model.workspaceName(workspaceID)) {
                if move {
                    model.manageAndMoveFocusedWindow(to: workspaceID)
                } else {
                    model.manageAndShowFocusedWindow(on: workspaceID)
                }
            }
        }
    }

    private var currentExternalWindow: WindowSnapshot? {
        switch model.focusedWindowState {
        case let .unmanaged(window), let .managed(window, _, _), let .excluded(window, _):
            return window
        default:
            return nil
        }
    }

    private func windowDisplayName(_ window: WindowSnapshot) -> String {
        if let title = window.title, !title.isEmpty { return "\(window.applicationName): \(title)" }
        return window.applicationName
    }

    private func windowHelp(
        _ window: WindowSnapshot,
        managed: Bool,
        sticky: Bool,
        exclusion: String?
    ) -> String {
        if let exclusion { return exclusion }
        if managed { return sticky ? "Managed and visible on all desktops." : "Managed window." }
        return "Unmanaged external window. Choose a workspace to manage it."
    }

    private var menuStateText: String {
        switch model.workspaceSwitchState {
        case .idle: return model.experimentalWorkspaceModeEnabled ? "Switching ready" : "Switching disabled"
        case .switching: return "Switching…"
        case .recovering: return "Recovering managed windows…"
        case .degraded: return "Degraded — review required"
        }
    }

    private var menuStateSymbol: String {
        model.workspaceSwitchState.isDegraded ? "exclamationmark.triangle.fill" : "circle.fill"
    }

    private var menuStateHelp: String {
        if case let .degraded(message) = model.workspaceSwitchState { return message }
        return menuStateText
    }
}
