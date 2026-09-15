import AppKit
import SwiftUI

struct CompactMenuBarView: View {
    @EnvironmentObject private var model: DiagnosticsViewModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(BlazaresSpacesAppDelegate.showDockIconDefaultsKey) private var showDockIcon = true

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "square.3.layers.3d")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("BlazaresSpaces").font(.headline)
                    Text(model.workspaceName(model.workspaceManager.activeWorkspaceID))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isNativeActivationInProgress {
                    ProgressView().controlSize(.small)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(model.workspaceIDs.enumerated()), id: \.element) { index, id in
                    let active = model.workspaceManager.activeWorkspaceID == id
                    Button {
                        model.activateWorkspace(id)
                    } label: {
                        HStack(spacing: 7) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 22, height: 22)
                                .background(active ? Color.accentColor : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(active ? .white : .primary)
                            Text(model.workspaceName(id))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if active { Image(systemName: "checkmark").font(.caption.bold()) }
                        }
                        .padding(7)
                        .background(active ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isNativeActivationInProgress || active)
                }
            }

            HStack {
                Button { model.activatePreviousWorkspace() } label: { Label("Previous", systemImage: "chevron.left") }
                Button { model.activateNextWorkspace() } label: { Label("Next", systemImage: "chevron.right") }
                Spacer()
                Button { model.refreshNativeSpaceTopology() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh native Spaces")
            }
            .disabled(model.isNativeActivationInProgress)

            Divider()

            Toggle("Native Space switching", isOn: Binding(
                get: { model.experimentalNativeSpacesEnabled },
                set: { model.setExperimentalNativeSpacesEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle("Global shortcuts", isOn: Binding(
                get: { model.globalShortcutsEnabled },
                set: { model.setGlobalShortcutsEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!model.accessibilityGranted)

            Toggle("Show icon in Dock", isOn: $showDockIcon)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: showDockIcon) { _, value in
                    BlazaresSpacesAppDelegate.applyDockVisibility(value)
                }

            Divider()

            HStack {
                Button("Open Dashboard") {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 330)
    }
}
