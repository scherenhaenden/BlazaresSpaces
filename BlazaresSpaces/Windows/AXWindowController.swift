import ApplicationServices
import CoreGraphics
import Foundation

enum WindowControlError: LocalizedError, Equatable {
    case targetNotFound
    case attributeUnavailable(String)
    case operationFailed(operation: String, axError: AXError)

    var errorDescription: String? {
        switch self {
        case .targetNotFound:
            return "The BlazaresSpaces Window Control Lab window was not found."
        case let .attributeUnavailable(attribute):
            return "The window did not expose the \(attribute) attribute."
        case let .operationFailed(operation, axError):
            return "\(operation) failed (AX error \(axError.rawValue))."
        }
    }
}

/// Controls one explicitly identified window owned by this process. It contains
/// no workspace or hiding semantics and cannot target another application's PID.
struct AXWindowController {
    private let processIdentifier: pid_t
    private let targetTitle: String

    init() {
        processIdentifier = ProcessInfo.processInfo.processIdentifier
        targetTitle = WindowControlLabConstants.title
    }

    func captureFrame() -> Result<CGRect, WindowControlError> {
        guard let element = targetElement() else { return .failure(.targetNotFound) }
        return readFrame(of: element)
    }

    @discardableResult
    func setPosition(_ position: CGPoint) -> Result<Void, WindowControlError> {
        guard let element = targetElement() else { return .failure(.targetNotFound) }
        var position = position
        let value = withUnsafePointer(to: &position) { AXValueCreate(.cgPoint, $0) }
        guard let value else { return .failure(.attributeUnavailable(kAXPositionAttribute)) }
        let error = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        return error == .success ? .success(()) : .failure(.operationFailed(operation: "Move test window", axError: error))
    }

    @discardableResult
    func setSize(_ size: CGSize) -> Result<Void, WindowControlError> {
        guard let element = targetElement() else { return .failure(.targetNotFound) }
        var size = size
        let value = withUnsafePointer(to: &size) { AXValueCreate(.cgSize, $0) }
        guard let value else { return .failure(.attributeUnavailable(kAXSizeAttribute)) }
        let error = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        return error == .success ? .success(()) : .failure(.operationFailed(operation: "Resize test window", axError: error))
    }

    func restore(frame: CGRect) -> Result<Void, WindowControlError> {
        switch setSize(frame.size) {
        case .failure(let error): return .failure(error)
        case .success: break
        }
        return setPosition(frame.origin)
    }

    private func targetElement() -> AXUIElement? {
        let application = AXUIElementCreateApplication(processIdentifier)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let elements = rawWindows as? [AXUIElement] else { return nil }

        return elements.first { element in
            var rawTitle: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &rawTitle) == .success else { return false }
            return (rawTitle as? String) == targetTitle
        }
    }

    private func readFrame(of element: AXUIElement) -> Result<CGRect, WindowControlError> {
        guard let position = pointAttribute(kAXPositionAttribute, of: element) else {
            return .failure(.attributeUnavailable(kAXPositionAttribute))
        }
        guard let size = sizeAttribute(kAXSizeAttribute, of: element) else {
            return .failure(.attributeUnavailable(kAXSizeAttribute))
        }
        return .success(CGRect(origin: position, size: size))
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

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

enum WindowControlLabConstants {
    static let title = "Window Control Lab"
}
