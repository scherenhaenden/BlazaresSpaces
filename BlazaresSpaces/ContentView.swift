//
//  ContentView.swift
//  BlazaresSpaces
//
//  Created by Edward Flores on 15.09.26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = DiagnosticsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    displaysSection
                    windowsSection
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

    private var windowsSection: some View {
        GroupBox("Manageable windows: \(model.windows.count)") {
            VStack(alignment: .leading, spacing: 10) {
                if !model.accessibilityGranted {
                    Text("Grant Accessibility permission, then click Refresh.")
                        .foregroundStyle(.secondary)
                } else if model.windows.isEmpty {
                    Text("No manageable windows were found.").foregroundStyle(.secondary)
                }
                ForEach(model.windows) { window in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(window.applicationName).font(.headline)
                        Text(window.title?.isEmpty == false ? window.title! : "Untitled window")
                            .lineLimit(1)
                            .help(window.title ?? "")
                        Text("PID: \(window.runtimeIdentity.processIdentifier)  Bundle: \(window.bundleIdentifier ?? "Unavailable")")
                        Text("AX ID: \(window.runtimeIdentity.accessibilityIdentifier ?? "Unavailable")  Subrole: \(window.subrole ?? "Unavailable")")
                        Text("Frame: \(window.frame.diagnosticDescription)  Display: \(window.displayID.map(String.init) ?? "Unmapped")")
                        Text("Minimized: \(window.isMinimized.diagnosticDescription)  Fullscreen: \(window.isFullscreen.diagnosticDescription)")
                    }
                    .fontDesign(.monospaced)
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
