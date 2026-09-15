import SwiftUI

struct WindowControlLabView: View {
    @StateObject private var model = WindowControlLabViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("BlazaresSpaces · Window Control Lab", systemImage: "testtube.2")
                .font(.title2.bold())
            Text("This window exists exclusively for safe window-management experiments. It is the only window this iteration can move or resize.")
                .foregroundStyle(.secondary)
            GroupBox("Test controls") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("Capture Frame") { model.captureFrame() }
                        Button("Move Test Window") { model.moveTestWindow() }
                        Button("Resize Test Window") { model.resizeTestWindow() }
                        Button("Restore Captured Frame") { model.restoreCapturedFrame() }
                    }
                    Button("Refresh Geometry") { model.refresh() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            GroupBox("Geometry") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current: \(model.currentFrame.map(\.diagnosticDescription) ?? "Unavailable")")
                    Text("Captured: \(model.capturedFrame.map(\.diagnosticDescription) ?? "None")")
                }
                .fontDesign(.monospaced)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 300)
        .task { model.refresh() }
    }
}

private extension CGRect {
    var diagnosticDescription: String {
        "x \(Int(minX)), y \(Int(minY)), w \(Int(width)), h \(Int(height))"
    }
}
