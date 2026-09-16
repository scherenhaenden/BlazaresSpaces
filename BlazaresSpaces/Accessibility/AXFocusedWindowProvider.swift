import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Read-only focused-window adapter. The application layer retains the last
/// valid external snapshot so opening the menu bar does not lose the target.
struct AXFocusedWindowProvider: FocusedWindowProviding {
    func focusedWindow(displays: [DisplaySnapshot]) -> FocusedWindowObservation? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ownPID,
              application.activationPolicy == .regular,
              !application.isTerminated else { return nil }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var rawWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &rawWindow
        ) == .success,
        rawWindow != nil,
        let frame = frame(of: rawWindow as! AXUIElement) else { return nil }
        let element = rawWindow as! AXUIElement
        guard stringAttribute(kAXRoleAttribute, of: element) == kAXWindowRole else { return nil }

        let name = application.localizedName ?? application.bundleIdentifier ?? "Unknown application"
        let identity = WindowRuntimeIdentity(
            processIdentifier: application.processIdentifier,
            accessibilityIdentifier: stringAttribute(kAXIdentifierAttribute, of: element),
            enumerationIndex: enumerationIndex(of: element, for: application.processIdentifier)
        )
        guard identity.enumerationIndex >= 0 else { return nil }
        let snapshot = WindowSnapshot(
            runtimeIdentity: identity,
            applicationName: name,
            bundleIdentifier: application.bundleIdentifier,
            title: stringAttribute(kAXTitleAttribute, of: element),
            role: stringAttribute(kAXRoleAttribute, of: element) ?? kAXWindowRole,
            subrole: stringAttribute(kAXSubroleAttribute, of: element),
            frame: frame,
            isMinimized: boolAttribute(kAXMinimizedAttribute, of: element),
            isFullscreen: boolAttribute("AXFullScreen", of: element),
            displayID: DisplayMapper.displayID(for: frame, among: displays)
        )
        return FocusedWindowObservation(runtimeIdentity: identity, snapshot: snapshot)
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        attribute(name, of: element) as? String
    }

    private func boolAttribute(_ name: String, of element: AXUIElement) -> Bool? {
        attribute(name, of: element) as? Bool
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionRaw = attribute(kAXPositionAttribute, of: element),
              let sizeRaw = attribute(kAXSizeAttribute, of: element) else { return nil }
        let position = positionRaw as! AXValue
        let size = sizeRaw as! AXValue
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetType(position) == .cgPoint,
              AXValueGetType(size) == .cgSize,
              AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(size, .cgSize, &dimensions),
              dimensions.width > 1, dimensions.height > 1 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func enumerationIndex(of element: AXUIElement, for pid: pid_t) -> Int {
        let appElement = AXUIElementCreateApplication(pid)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement] else { return -1 }
        return windows.firstIndex { candidate in
            CFEqual(candidate, element)
        } ?? -1
    }
}
