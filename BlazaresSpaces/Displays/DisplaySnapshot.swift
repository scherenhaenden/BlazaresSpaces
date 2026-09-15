import CoreGraphics

struct DisplaySnapshot: Identifiable, Equatable, Sendable {
    let id: CGDirectDisplayID
    let name: String
    /// Global CoreGraphics/Accessibility coordinates (origin at the top-left of the main display).
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScale: CGFloat
    let isMain: Bool
}

