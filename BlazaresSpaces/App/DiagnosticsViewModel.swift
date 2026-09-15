import AppKit
import Combine
import OSLog

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var displays: [DisplaySnapshot] = []
    @Published private(set) var windows: [WindowSnapshot] = []
    @Published private(set) var issues: [WindowDiscoveryIssue] = []
    @Published private(set) var lastRefresh: Date?

    private let permissionManager = AccessibilityPermissionManager()
    private let displayManager = DisplayManager()
    private let windowDiscovery = AXWindowDiscovery()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BlazaresSpaces", category: "Diagnostics")

    func refresh() {
        accessibilityGranted = permissionManager.isTrusted
        displays = displayManager.displays()

        if accessibilityGranted {
            let result = windowDiscovery.discover(displays: displays)
            windows = result.windows
            issues = result.issues
        } else {
            windows = []
            issues = []
        }
        lastRefresh = Date()
    }

    func requestAccessibilityAccess() {
        logger.info("Requesting Accessibility access")
        accessibilityGranted = permissionManager.requestAccess()
        if accessibilityGranted {
            refresh()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

