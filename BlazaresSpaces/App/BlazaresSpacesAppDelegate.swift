import AppKit

final class BlazaresSpacesAppDelegate: NSObject, NSApplicationDelegate {
    static let showDockIconDefaultsKey = "showDockIcon"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        let showDockIcon: Bool
        if defaults.object(forKey: Self.showDockIconDefaultsKey) == nil {
            showDockIcon = true
            defaults.set(true, forKey: Self.showDockIconDefaultsKey)
        } else {
            showDockIcon = defaults.bool(forKey: Self.showDockIconDefaultsKey)
        }
        applyDockVisibility(showDockIcon)
    }

    static func applyDockVisibility(_ showDockIcon: Bool) {
        NSApplication.shared.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    private func applyDockVisibility(_ showDockIcon: Bool) {
        Self.applyDockVisibility(showDockIcon)
    }
}
