import CoreGraphics
import Foundation

/// Progress update during a scrolling capture operation.
public struct ScrollCaptureProgress {
    public let framesCapture: Int
    public let estimatedTotalFrames: Int?
    public let stitchedImage: CGImage?

    public init(framesCapture: Int, estimatedTotalFrames: Int?, stitchedImage: CGImage?) {
        self.framesCapture = framesCapture
        self.estimatedTotalFrames = estimatedTotalFrames
        self.stitchedImage = stitchedImage
    }

    public var estimatedProgress: Double? {
        guard let total = estimatedTotalFrames, total > 0 else { return nil }
        return Double(framesCapture) / Double(total)
    }
}

/// Result of a completed scrolling capture.
public struct ScrollCaptureResult {
    public let image: CGImage
    public let frameCount: Int
    public let windowID: CGWindowID
    public let timestamp: Date

    public init(image: CGImage, frameCount: Int, windowID: CGWindowID, timestamp: Date = Date()) {
        self.image = image
        self.frameCount = frameCount
        self.windowID = windowID
        self.timestamp = timestamp
    }
}

/// Abstracts scrolling capture functionality.
/// Current implementation: AccessibilityScrollCapture (local, uses AX API).
/// Future App Store implementation: StreamScrollCapture (SCStream + user-driven scroll).
public protocol ScrollCaptureProvider {
    /// Performs a scrolling capture of the given window.
    /// - Parameters:
    ///   - windowID: The window to scroll and capture.
    ///   - onProgress: Called with progress updates during capture.
    /// - Returns: The stitched result.
    func captureScrolling(
        windowID: CGWindowID,
        onProgress: @escaping (ScrollCaptureProgress) -> Void
    ) async throws -> ScrollCaptureResult

    /// Cancels an in-progress scrolling capture.
    func cancel()
}
