import Foundation

/// Persists only safe user configuration. Runtime AX identities, window frames,
/// and workspace memberships are intentionally never serialized.
struct WorkspaceConfigurationStore {
    private let defaults: UserDefaults
    private let key = "BlazaresSpaces.workspace.configuration.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WorkspaceManager.Configuration? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WorkspaceManager.Configuration.self, from: data)
    }

    func save(_ configuration: WorkspaceManager.Configuration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }
}
