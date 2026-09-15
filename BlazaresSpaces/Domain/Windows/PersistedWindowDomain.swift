import CoreGraphics
import Foundation

/// Durable identity of a user-managed logical window record.
/// It is intentionally unrelated to a process or Accessibility session.
struct ManagedWindowID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    var id: UUID { rawValue }
}

/// A serialization-friendly frame value. Its meaning is made explicit by the
/// property that contains it (absolute or display-normalized geometry).
struct WindowGeometryRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ frame: CGRect) {
        self.init(
            x: Double(frame.origin.x),
            y: Double(frame.origin.y),
            width: Double(frame.size.width),
            height: Double(frame.size.height)
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Non-runtime display characteristics used to understand captured geometry.
/// No `CGDirectDisplayID` is stored because it is not a durable identity.
struct PersistedDisplayDescriptor: Codable, Equatable, Sendable {
    let name: String?
    let frameSize: WindowGeometryRect
    let visibleFrameSize: WindowGeometryRect
    let backingScale: Double
    let wasMain: Bool

    init(
        name: String?,
        frameSize: WindowGeometryRect,
        visibleFrameSize: WindowGeometryRect,
        backingScale: Double,
        wasMain: Bool
    ) {
        self.name = name
        self.frameSize = frameSize
        self.visibleFrameSize = visibleFrameSize
        self.backingScale = backingScale
        self.wasMain = wasMain
    }
}

/// Desired geometry, kept separate from both current runtime geometry and any
/// temporary off-screen parking frame.
struct LogicalWindowGeometry: Codable, Equatable, Sendable {
    let absolute: WindowGeometryRect
    let normalized: WindowGeometryRect?
    let display: PersistedDisplayDescriptor?

    init(
        absolute: WindowGeometryRect,
        normalized: WindowGeometryRect? = nil,
        display: PersistedDisplayDescriptor? = nil
    ) {
        self.absolute = absolute
        self.normalized = normalized
        self.display = display
    }
}

/// Privacy-safe signals that may survive an application restart. In
/// particular, this type cannot contain titles, PID, AX identifiers, display
/// runtime IDs, or parking state.
struct PersistedWindowDescriptor: Codable, Equatable, Sendable {
    let bundleIdentifier: String?
    let applicationName: String
    let role: String
    let subrole: String?
    let userAlias: String?

    init(
        bundleIdentifier: String?,
        applicationName: String,
        role: String,
        subrole: String?,
        userAlias: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.role = role
        self.subrole = subrole
        self.userAlias = userAlias
    }
}
