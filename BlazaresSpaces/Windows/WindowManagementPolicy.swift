import Foundation

/// Conservative policy used before a window can enter the explicit external
/// test set. Discovery remains read-only regardless of this policy.
struct WindowManagementPolicy: Equatable, Sendable {
    var excludedBundleIdentifierPrefixes: [String]
    var excludedApplicationNames: [String]

    static let developmentDefaults = WindowManagementPolicy(
        excludedBundleIdentifierPrefixes: ["com.citrix."],
        excludedApplicationNames: ["Citrix Workspace", "Citrix Viewer"]
    )

    func exclusionReason(for window: WindowSnapshot) -> String? {
        if let bundleIdentifier = window.bundleIdentifier,
           excludedBundleIdentifierPrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) {
            return "Bundle identifier is excluded by policy."
        }

        if excludedApplicationNames.contains(where: { $0.caseInsensitiveCompare(window.applicationName) == .orderedSame }) {
            return "Application is excluded by policy."
        }

        return nil
    }
}

struct AuthorizedExternalWindow: Equatable, Sendable {
    let snapshot: WindowSnapshot

    var applicationName: String { snapshot.applicationName }
    var processIdentifier: pid_t { snapshot.runtimeIdentity.processIdentifier }
    var runtimeIdentity: WindowRuntimeIdentity { snapshot.runtimeIdentity }

    fileprivate init(snapshot: WindowSnapshot) {
        self.snapshot = snapshot
    }
}

enum WindowAuthorizationError: LocalizedError, Equatable {
    case excluded(String)
    case missingRuntimeIdentifier

    var errorDescription: String? {
        switch self {
        case let .excluded(reason): return "Window is excluded: \(reason)"
        case .missingRuntimeIdentifier: return "This window has no usable AX runtime identifier and cannot be safely selected for mutation."
        }
    }
}

enum WindowAuthorization {
    static func authorize(
        _ window: WindowSnapshot,
        policy: WindowManagementPolicy
    ) -> Result<AuthorizedExternalWindow, WindowAuthorizationError> {
        if let reason = policy.exclusionReason(for: window) {
            return .failure(.excluded(reason))
        }
        guard window.runtimeIdentity.processIdentifier > 0,
              window.runtimeIdentity.enumerationIndex >= 0 else {
            return .failure(.missingRuntimeIdentifier)
        }
        return .success(AuthorizedExternalWindow(snapshot: window))
    }
}
