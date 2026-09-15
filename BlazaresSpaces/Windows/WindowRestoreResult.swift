import CoreGraphics
import ApplicationServices
import Foundation

enum WindowRestoreStatus: Equatable, Sendable {
    case restoredExactly
    case restoredWithAdjustment
    case windowMissing
    case windowChanged
    case excluded
    case unsupported
    case permissionDenied
    case failed

    var displayName: String {
        switch self {
        case .restoredExactly: return "Restored exactly"
        case .restoredWithAdjustment: return "Restored with adjustment"
        case .windowMissing: return "Window missing"
        case .windowChanged: return "Window changed"
        case .excluded: return "Excluded"
        case .unsupported: return "Unsupported"
        case .permissionDenied: return "Permission denied"
        case .failed: return "Failed"
        }
    }
}

struct WindowRestoreResult: Identifiable, Equatable, Sendable {
    let id: WindowRuntimeIdentity
    let applicationName: String
    let processIdentifier: pid_t
    let requestedFrame: CGRect
    let actualFrame: CGRect?
    let status: WindowRestoreStatus
    let message: String
}

struct WindowRestoreReport: Equatable, Sendable {
    let results: [WindowRestoreResult]

    var requestedCount: Int { results.count }
    var exactCount: Int { results.filter { $0.status == .restoredExactly }.count }
    var adjustedCount: Int { results.filter { $0.status == .restoredWithAdjustment }.count }
    var failedCount: Int {
        results.filter {
            ![.restoredExactly, .restoredWithAdjustment, .excluded].contains($0.status)
        }.count
    }
    var excludedCount: Int { results.filter { $0.status == .excluded }.count }
}

enum WindowFrameComparison {
    static func isWithinTolerance(requested: CGRect, actual: CGRect, tolerance: CGFloat) -> Bool {
        abs(actual.minX - requested.minX) <= tolerance
            && abs(actual.minY - requested.minY) <= tolerance
            && abs(actual.width - requested.width) <= tolerance
            && abs(actual.height - requested.height) <= tolerance
    }
}

enum ExternalWindowOperationError: LocalizedError, Equatable {
    case windowMissing
    case windowChanged
    case unsupported(String)
    case permissionDenied
    case axFailure(operation: String, axError: AXError)

    var errorDescription: String? {
        switch self {
        case .windowMissing: return "The selected window is no longer available."
        case .windowChanged: return "The selected runtime window identity no longer matches."
        case let .unsupported(message): return message
        case .permissionDenied: return "Accessibility permission denied the requested operation."
        case let .axFailure(operation, axError): return "\(operation) failed (AX error \(axError.rawValue))."
        }
    }
}
