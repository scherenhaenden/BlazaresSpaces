import Foundation

nonisolated enum NativeSpaceMappingStoreResult: Equatable, Sendable {
    case loaded([NativeSpaceMapping])
    case missing
    case invalid(String)
    case ioFailure(String)
}

/// Separate, versioned mapping persistence keeps native runtime details out of
/// the window-state schema while remaining reconstructable and replaceable.
actor NativeSpaceMappingStore {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let mappings: [NativeSpaceMapping]
    }

    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.fileURL = base.appendingPathComponent("BlazaresSpaces", isDirectory: true)
                .appendingPathComponent("native-space-mappings.json")
        }
    }

    func load() -> NativeSpaceMappingStoreResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
            guard envelope.schemaVersion == 1 else { return .invalid("Unsupported native mapping schema") }
            guard Self.isValid(envelope.mappings) else { return .invalid("Duplicate or incomplete native mapping") }
            return .loaded(envelope.mappings)
        } catch {
            return .ioFailure(error.localizedDescription)
        }
    }

    func save(_ mappings: [NativeSpaceMapping]) -> NativeSpaceMappingStoreResult {
        guard Self.isValid(mappings) else { return .invalid("Duplicate virtual/display mapping or missing display identity") }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Envelope(schemaVersion: 1, mappings: mappings))
            try data.write(to: fileURL, options: .atomic)
            return .loaded(mappings)
        } catch {
            return .ioFailure(error.localizedDescription)
        }
    }

    private static func isValid(_ mappings: [NativeSpaceMapping]) -> Bool {
        let keys = mappings.map { $0.virtualSpaceID + "\u{1f}" + $0.displayIdentifier }
        return mappings.allSatisfy { !$0.virtualSpaceID.isEmpty && !$0.displayIdentifier.isEmpty }
            && Set(keys).count == keys.count
    }
}
