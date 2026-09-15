import SwiftUI

struct AccessibilityPermissionBanner: View {
    @EnvironmentObject private var model: DiagnosticsViewModel

    var body: some View {
        if !model.accessibilityGranted {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Bedienungshilfe erforderlich")
                        .font(.subheadline.weight(.semibold))
                    Text("BlazaresSpaces braucht Bedienungshilfe, um Fenster und globale Shortcuts zu steuern.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Zugriff anfordern") {
                    model.requestAccessibilityAccess()
                }
                .buttonStyle(.borderedProminent)

                Button("Einstellungen öffnen") {
                    model.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.08))
            .overlay(alignment: .bottom) {
                Divider()
            }
            .accessibilityIdentifier("accessibilityPermissionBanner")
            .task {
                // macOS does not notify the app when Accessibility permission is
                // granted in System Settings. While this banner is visible, poll
                // the permission state lightly so the banner disappears as soon
                // as the permission has been granted.
                while !Task.isCancelled && !model.accessibilityGranted {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { break }
                    model.refresh()
                }
            }
        }
    }
}
