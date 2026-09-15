import ApplicationServices

struct AccessibilityPermissionManager {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

