import CoreGraphics
import Foundation

enum WorkspaceWindowOperation: Equatable, Sendable {
    case capture
    case park
    case restore

    var displayName: String {
        switch self {
        case .capture: return "Capture"
        case .park: return "Park"
        case .restore: return "Restore"
        }
    }
}

enum WorkspaceWindowOutcome: Equatable, Sendable {
    case captured
    case parked
    case restoredExactly
    case adjusted
    case missing
    case changed
    case excluded
    case unsupported
    case permissionDenied
    case failed

    var displayName: String {
        switch self {
        case .captured: return "Captured"
        case .parked: return "Parked"
        case .restoredExactly: return "Restored exactly"
        case .adjusted: return "Adjusted"
        case .missing: return "Missing"
        case .changed: return "Changed"
        case .excluded: return "Excluded"
        case .unsupported: return "Unsupported"
        case .permissionDenied: return "Permission denied"
        case .failed: return "Failed"
        }
    }
}

struct WorkspaceWindowResult: Identifiable, Equatable, Sendable {
    let id: WindowRuntimeIdentity
    let applicationName: String
    let processIdentifier: pid_t
    let workspaceID: WorkspaceID
    let operation: WorkspaceWindowOperation
    let requestedFrame: CGRect?
    let actualFrame: CGRect?
    let outcome: WorkspaceWindowOutcome
    let message: String
}

struct WorkspaceSwitchMetrics: Equatable, Sendable {
    let captureMilliseconds: Double
    let parkingMilliseconds: Double
    let restoreMilliseconds: Double
    let totalMilliseconds: Double
    let windowsProcessed: Int
}

struct WorkspaceSwitchResult: Equatable, Sendable {
    let sourceWorkspaceID: WorkspaceID?
    let targetWorkspaceID: WorkspaceID
    let results: [WorkspaceWindowResult]
    let metrics: WorkspaceSwitchMetrics

    var capturedCount: Int { results.filter { $0.outcome == .captured }.count }
    var parkedCount: Int { results.filter { $0.outcome == .parked }.count }
    var restoredCount: Int { results.filter { $0.outcome == .restoredExactly }.count }
    var adjustedCount: Int { results.filter { $0.outcome == .adjusted }.count }
    var missingCount: Int { results.filter { $0.outcome == .missing }.count }
    var excludedCount: Int { results.filter { $0.outcome == .excluded }.count }
    var failedCount: Int {
        results.filter { [.changed, .unsupported, .permissionDenied, .failed].contains($0.outcome) }.count
    }
    var isDegraded: Bool { missingCount > 0 || failedCount > 0 || adjustedCount > 0 }
}
