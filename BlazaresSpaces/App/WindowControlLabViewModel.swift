import Combine
import CoreGraphics
import Foundation

@MainActor
final class WindowControlLabViewModel: ObservableObject {
    @Published private(set) var currentFrame: CGRect?
    @Published private(set) var capturedFrame: CGRect?
    @Published private(set) var status = "Open this window only for safe geometry experiments."

    private let controller = AXWindowController()

    func refresh() {
        switch controller.captureFrame() {
        case let .success(frame): currentFrame = frame
        case let .failure(error): status = error.localizedDescription
        }
    }

    func captureFrame() {
        switch controller.captureFrame() {
        case let .success(frame):
            capturedFrame = frame
            currentFrame = frame
            status = "Captured the test window frame."
        case let .failure(error): status = error.localizedDescription
        }
    }

    func moveTestWindow() {
        guard let frame = currentFrame ?? controller.captureFrame().value else {
            status = "Capture the test window first or wait for it to become available."
            return
        }
        let position = CGPoint(x: frame.minX + 50, y: frame.minY + 50)
        switch controller.setPosition(position) {
        case .success:
            status = "Moved the test window by 50 points."
            refresh()
        case let .failure(error): status = error.localizedDescription
        }
    }

    func resizeTestWindow() {
        guard let frame = currentFrame ?? controller.captureFrame().value else {
            status = "Capture the test window first or wait for it to become available."
            return
        }
        let size = CGSize(width: min(frame.width + 80, 1_200), height: min(frame.height + 40, 900))
        switch controller.setSize(size) {
        case .success:
            status = "Resized the test window by 80 × 40 points."
            refresh()
        case let .failure(error): status = error.localizedDescription
        }
    }

    func restoreCapturedFrame() {
        guard let capturedFrame else {
            status = "Capture a frame before restoring."
            return
        }
        switch controller.restore(frame: capturedFrame) {
        case .success:
            status = "Restored the captured test window frame."
            refresh()
        case let .failure(error): status = error.localizedDescription
        }
    }
}

private extension Result where Success == CGRect, Failure == WindowControlError {
    var value: CGRect? {
        if case let .success(frame) = self { return frame }
        return nil
    }
}
