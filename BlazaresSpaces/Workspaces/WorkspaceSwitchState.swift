import Foundation

enum WorkspaceSwitchState: Equatable, Sendable {
    case idle
    case switching(target: WorkspaceID)
    case recovering
    case degraded(message: String)

    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .switching: return "Switching"
        case .recovering: return "Recovering"
        case .degraded: return "Degraded"
        }
    }

    var isDegraded: Bool {
        if case .degraded = self { return true }
        return false
    }
}

/// Pure latest-target queue used to serialize rapid shortcut/menu requests.
struct WorkspaceSwitchRequestQueue: Equatable, Sendable {
    private(set) var state: WorkspaceSwitchState = .idle
    private(set) var pendingTarget: WorkspaceID?

    mutating func request(_ target: WorkspaceID) -> WorkspaceID? {
        switch state {
        case .switching:
            pendingTarget = target
            return nil
        default:
            state = .switching(target: target)
            return target
        }
    }

    mutating func finish(completedTarget: WorkspaceID? = nil, degradedMessage: String? = nil) -> WorkspaceID? {
        if degradedMessage == nil, let pendingTarget, pendingTarget != completedTarget {
            self.pendingTarget = nil
            state = .switching(target: pendingTarget)
            return pendingTarget
        }
        self.pendingTarget = nil
        state = degradedMessage.map { .degraded(message: $0) } ?? .idle
        return nil
    }

    mutating func beginRecovery() { state = .recovering }
    mutating func reset() { state = .idle; pendingTarget = nil }
}
