import Foundation

enum WorkspaceStateLoadResult: Equatable, Sendable {
    case missing
    case loaded(PersistedStateV1)
    case unsupported(schemaVersion: Int)
    case corrupted(file: URL, description: String)
    case ioFailure(description: String)
}

enum WorkspaceStateSaveResult: Equatable, Sendable {
    case saved(file: URL)
    case validationFailed([PersistedStateValidationIssue])
    case refusedToOverwriteExistingState(description: String)
    case ioFailure(description: String)
}

struct WorkspacePersistenceError: Error, Equatable, Sendable {
    let message: String
}

protocol WorkspaceStatePersisting: Sendable {
    func load() async -> WorkspaceStateLoadResult
    func save(_ state: PersistedStateV1) async -> WorkspaceStateSaveResult
    func reset() async -> Result<Void, WorkspacePersistenceError>
}

/// Serialized, version-aware JSON persistence. A malformed or unsupported file
/// is left untouched; callers must explicitly resolve it before another save.
actor AtomicJSONWorkspaceStateStore: WorkspaceStatePersisting {
    let fileURL: URL
    let lastValidBackupURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let migrator: PersistedStateMigrator
    private let validator: PersistedStateValidator

    init(
        fileURL: URL = AtomicJSONWorkspaceStateStore.defaultFileURL()
    ) {
        self.fileURL = fileURL
        self.lastValidBackupURL = fileURL.deletingLastPathComponent().appendingPathComponent("state.last-valid.json")
        self.fileManager = .default
        self.encoder = JSONEncoder()
        self.migrator = PersistedStateMigrator()
        self.validator = PersistedStateValidator()
    }

    func load() async -> WorkspaceStateLoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .missing }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .ioFailure(description: error.localizedDescription)
        }
        return map(migrator.decode(data))
    }

    func save(_ state: PersistedStateV1) async -> WorkspaceStateSaveResult {
        let validationIssues = validator.validate(state)
        guard validationIssues.isEmpty else { return .validationFailed(validationIssues) }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: fileURL.path) {
                let currentData = try Data(contentsOf: fileURL)
                switch migrator.decode(currentData) {
                case .loaded:
                    try currentData.write(to: lastValidBackupURL, options: .atomic)
                case let .unsupported(version):
                    return .refusedToOverwriteExistingState(
                        description: "Existing state uses unsupported schema V\(version) and was preserved."
                    )
                case let .corrupted(description):
                    return .refusedToOverwriteExistingState(
                        description: "Existing corrupted state was preserved: \(description)"
                    )
                }
            }

            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(PersistedStateEnvelope(state: state))
            try data.write(to: fileURL, options: .atomic)
            return .saved(file: fileURL)
        } catch {
            return .ioFailure(description: error.localizedDescription)
        }
    }

    /// Explicit user action: remove the active state while retaining the last
    /// valid/corrupt file for diagnosis whenever possible.
    func reset() async -> Result<Void, WorkspacePersistenceError> {
        do {
            guard fileManager.fileExists(atPath: fileURL.path) else { return .success(()) }
            let quarantine = fileURL.deletingLastPathComponent().appendingPathComponent("state.reset-backup.json")
            if fileManager.fileExists(atPath: quarantine.path) { try fileManager.removeItem(at: quarantine) }
            try fileManager.moveItem(at: fileURL, to: quarantine)
            return .success(())
        } catch {
            return .failure(WorkspacePersistenceError(message: error.localizedDescription))
        }
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("BlazaresSpaces", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    private func map(_ result: PersistedStateDecodeResult) -> WorkspaceStateLoadResult {
        switch result {
        case let .loaded(state): return .loaded(state)
        case let .unsupported(version): return .unsupported(schemaVersion: version)
        case let .corrupted(description): return .corrupted(file: fileURL, description: description)
        }
    }
}
