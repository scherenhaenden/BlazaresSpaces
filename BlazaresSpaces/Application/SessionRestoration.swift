import Foundation

enum SessionPersistenceStatus: Equatable, Sendable {
    case loading
    case missing
    case loaded
    case corrupted(description: String)
    case unsupported(schemaVersion: Int)
    case ioFailure(description: String)

    var isSafeForExternalMutation: Bool {
        switch self {
        case .loading, .corrupted, .unsupported, .ioFailure: return false
        case .missing, .loaded: return true
        }
    }

    var displayName: String {
        switch self {
        case .loading: return "Loading saved configuration"
        case .missing: return "No saved configuration"
        case .loaded: return "Configuration loaded"
        case .corrupted: return "Saved configuration is corrupted"
        case let .unsupported(version): return "Unsupported saved schema V\(version)"
        case .ioFailure: return "Persistence unavailable"
        }
    }
}

enum RestorationMatchKind: Equatable, Sendable {
    case highConfidence(score: Int, evidence: [String])
    case probable(score: Int, evidence: [String])
    case ambiguous(candidateCount: Int)
    case missing

    var label: String {
        switch self {
        case .highConfidence: return "High confidence — confirmation required"
        case .probable: return "Probable — manual selection required"
        case .ambiguous: return "Ambiguous — no automatic choice"
        case .missing: return "Missing — will be reconsidered later"
        }
    }
}

struct RestorationReviewItem: Identifiable, Equatable, Sendable {
    let id: ManagedWindowID
    let applicationName: String
    let match: RestorationMatchKind
    let candidate: WindowSnapshot?

    var canConfirm: Bool {
        if case .highConfidence = match { return candidate != nil }
        return false
    }
}

struct SessionRestorationCoordinator: Sendable {
    let matcher: WindowMatcher

    init(matcher: WindowMatcher = WindowMatcher()) {
        self.matcher = matcher
    }

    func review(_ state: PersistedStateV1, windows: [WindowSnapshot]) -> [RestorationReviewItem] {
        let requests = state.managedWindows.map {
            PersistedWindowMatchRequest(id: $0.id, descriptor: $0.descriptor, logicalGeometry: $0.logicalGeometry)
        }
        let results = matcher.matchAll(requests, among: windows)
        return state.managedWindows.map { record in
            let result = results[record.id] ?? .missing
            switch result {
            case let .highConfidence(candidate):
                return RestorationReviewItem(id: record.id, applicationName: record.descriptor.applicationName, match: .highConfidence(score: candidate.score, evidence: candidate.evidence), candidate: candidate.window)
            case let .probable(candidate):
                return RestorationReviewItem(id: record.id, applicationName: record.descriptor.applicationName, match: .probable(score: candidate.score, evidence: candidate.evidence), candidate: candidate.window)
            case let .ambiguous(candidates):
                return RestorationReviewItem(id: record.id, applicationName: record.descriptor.applicationName, match: .ambiguous(candidateCount: candidates.count), candidate: nil)
            case .missing:
                return RestorationReviewItem(id: record.id, applicationName: record.descriptor.applicationName, match: .missing, candidate: nil)
            }
        }
    }
}

extension WorkspaceManager.Configuration {
    init(persisted state: PersistedStateV1) {
        let byID = Dictionary(uniqueKeysWithValues: state.workspaces.map { ($0.id, $0) })
        let orderedIDs = state.workspaceOrder.filter { byID[$0] != nil }
        let fallbackIDs = state.workspaces.map(\.id).filter { !orderedIDs.contains($0) }
        self.workspaces = (orderedIDs + fallbackIDs).compactMap { id in
            guard let workspace = byID[id] else { return nil }
            return .init(id: workspace.id, name: workspace.name)
        }
        self.activeWorkspaceID = state.activeWorkspaceID
    }
}

extension PersistedStateV1 {
    static func make(
        from manager: WorkspaceManager,
        shortcuts: GlobalShortcutConfiguration,
        displays: [DisplaySnapshot]
    ) -> PersistedStateV1 {
        let topology = DisplayTopologyMapper()
        let workspaces = manager.workspaceOrder.map { id in
            PersistedStateV1.Workspace(id: id.rawValue, name: manager.workspace(for: id).name)
        }
        let records = manager.allMembers.map { member in
            let display = member.logicalSnapshot.displayID.flatMap { id in displays.first(where: { $0.id == id }) }
            let geometry = display.map {
                topology.captureGeometry(frame: member.logicalSnapshot.frame, on: $0)
            } ?? LogicalWindowGeometry(absolute: WindowGeometryRect(member.logicalSnapshot.frame))
            let descriptor = PersistedWindowDescriptor(
                bundleIdentifier: member.logicalSnapshot.bundleIdentifier,
                applicationName: member.logicalSnapshot.applicationName,
                role: member.logicalSnapshot.role,
                subrole: member.logicalSnapshot.subrole
            )
            return PersistedStateV1.ManagedWindow(
                id: member.managedWindowID,
                descriptor: descriptor,
                workspaceIDs: Set(member.workspaceIDs.map(\.rawValue)),
                sticky: member.visibleOnAllWorkspaces,
                logicalGeometry: geometry,
                screenAssignments: member.screenAssignments.values.sorted { $0.workspaceID.rawValue < $1.workspaceID.rawValue }
            )
        }
        return PersistedStateV1(
            workspaces: workspaces,
            workspaceOrder: manager.workspaceOrder.map(\.rawValue),
            activeWorkspaceID: manager.activeWorkspaceID.rawValue,
            shortcuts: .init(
                modifierRawValue: shortcuts.modifierRawValue,
                desktopKeyCodes: shortcuts.desktopKeyCodes,
                nextKeyCode: shortcuts.nextKeyCode,
                previousKeyCode: shortcuts.previousKeyCode
            ),
            preferences: .init(requiresExplicitRestoreConfirmation: true),
            managedWindows: records
        )
    }
}

extension GlobalShortcutConfiguration {
    init(persisted value: PersistedStateV1.ShortcutConfiguration) {
        self.enabled = value.enabled
        self.modifierRawValue = value.modifierRawValue
        self.desktopKeyCodes = value.desktopKeyCodes
        self.nextKeyCode = value.nextKeyCode
        self.previousKeyCode = value.previousKeyCode
    }
}
