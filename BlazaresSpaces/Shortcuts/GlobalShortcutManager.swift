import AppKit
import Foundation

enum GlobalShortcutAction: Equatable, Sendable {
    case desktop(index: Int)
    case next
    case previous
}

struct GlobalShortcutConfiguration: Codable, Equatable, Sendable {
    var enabled = true
    var modifierRawValue: UInt = NSEvent.ModifierFlags([.control, .option]).rawValue
    var desktopKeyCodes: [Int] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    var nextKeyCode = 124
    var previousKeyCode = 123

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }
}

@MainActor
final class GlobalShortcutManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private(set) var isRunning = false

    func start(configuration: GlobalShortcutConfiguration, handler: @escaping (GlobalShortcutAction) -> Void) {
        stop()
        guard configuration.enabled else { return }

        let callback: (NSEvent) -> NSEvent? = { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == configuration.modifiers else { return event }
            let action: GlobalShortcutAction?
            if let index = configuration.desktopKeyCodes.firstIndex(of: Int(event.keyCode)) {
                action = .desktop(index: index)
            } else if Int(event.keyCode) == configuration.nextKeyCode {
                action = .next
            } else if Int(event.keyCode) == configuration.previousKeyCode {
                action = .previous
            } else {
                action = nil
            }
            guard let action else { return event }
            handler(action)
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = callback(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: callback)
        isRunning = true
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isRunning = false
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}

struct GlobalShortcutConfigurationStore {
    private let defaults: UserDefaults
    private let key = "BlazaresSpaces.global.shortcuts.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> GlobalShortcutConfiguration {
        guard let data = defaults.data(forKey: key),
              let configuration = try? JSONDecoder().decode(GlobalShortcutConfiguration.self, from: data) else {
            return GlobalShortcutConfiguration()
        }
        return configuration
    }

    func save(_ configuration: GlobalShortcutConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }
}
