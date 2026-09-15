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
            Button("Open BlazaresSpaces") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        .padding(10)
        .frame(width: 240)
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
