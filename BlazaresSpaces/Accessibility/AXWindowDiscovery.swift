import AppKit
import ApplicationServices
import OSLog

struct AXWindowDiscovery {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BlazaresSpaces", category: "WindowDiscovery")

    func discover(displays: [DisplaySnapshot]) -> WindowDiscoveryResult {
        var windows: [WindowSnapshot] = []
        var issues: [WindowDiscoveryIssue] = []
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for application in NSWorkspace.shared.runningApplications
        where application.processIdentifier != ownPID && application.activationPolicy == .regular && !application.isTerminated {
            let name = application.localizedName ?? application.bundleIdentifier ?? "Unknown application"
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            var rawWindows: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawWindows)

            guard result == .success else {
                if result != .noValue && result != .attributeUnsupported {
                    issues.append(.init(
                        applicationName: name,
                        processIdentifier: application.processIdentifier,
                        message: "Could not read windows (AX error \(result.rawValue))."
                    ))
                }
                continue
            }
            guard let elements = rawWindows as? [AXUIElement] else { continue }

            for (index, element) in elements.enumerated() {
                guard stringAttribute(kAXRoleAttribute, of: element) == kAXWindowRole,
                      let position = pointAttribute(kAXPositionAttribute, of: element),
                      let size = sizeAttribute(kAXSizeAttribute, of: element),
                      size.width > 1, size.height > 1 else {
                    continue
                }

                let frame = CGRect(origin: position, size: size)
                let identity = WindowRuntimeIdentity(
                    processIdentifier: application.processIdentifier,
                    accessibilityIdentifier: stringAttribute(kAXIdentifierAttribute, of: element),
                    enumerationIndex: index
                )
                windows.append(WindowSnapshot(
                    runtimeIdentity: identity,
                    applicationName: name,
                    bundleIdentifier: application.bundleIdentifier,
                    title: stringAttribute(kAXTitleAttribute, of: element),
                    role: kAXWindowRole,
                    subrole: stringAttribute(kAXSubroleAttribute, of: element),
                    frame: frame,
                    isMinimized: boolAttribute(kAXMinimizedAttribute, of: element),
                    // AppKit does not publish a Swift constant for this standard AX attribute.
                    isFullscreen: boolAttribute("AXFullScreen", of: element),
                    displayID: DisplayMapper.displayID(for: frame, among: displays)
                ))
            }
        }

        logger.info("Found \(windows.count, privacy: .public) manageable window(s); \(issues.count, privacy: .public) discovery issue(s)")
        return WindowDiscoveryResult(
            windows: windows.sorted { ($0.applicationName, $0.frame.minX, $0.frame.minY) < ($1.applicationName, $1.frame.minX, $1.frame.minY) },
            issues: issues
        )
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

    private func pointAttribute(_ name: String, of element: AXUIElement) -> CGPoint? {
        guard let rawValue = attribute(name, of: element), CFGetTypeID(rawValue) == AXValueGetTypeID() else { return nil }
        let value = rawValue as! AXValue
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func sizeAttribute(_ name: String, of element: AXUIElement) -> CGSize? {
        guard let rawValue = attribute(name, of: element), CFGetTypeID(rawValue) == AXValueGetTypeID() else { return nil }
        let value = rawValue as! AXValue
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }
}

extension AXWindowDiscovery: WindowDiscovering {}
