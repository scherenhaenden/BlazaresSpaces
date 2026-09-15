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
            Button("Previous Desktop") { model.activatePreviousWorkspace() }
            Button("Recover Managed Windows") { model.recoverManagedWindows() }
            Divider()
            Button("Open BlazaresSpaces") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        .padding(10)
        .frame(width: 240)
    }
}
