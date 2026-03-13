import CoreGraphics
import Foundation

/// Represents a region to capture: either a specific window or a custom screen region.
public enum CaptureTarget {
    case window(windowID: CGWindowID, title: String, appName: String)
    case region(CGRect)
}

/// Result of a capture operation.
public struct CaptureResult {
    public let image: CGImage
    public let target: CaptureTarget
    public let timestamp: Date

    public init(image: CGImage, target: CaptureTarget, timestamp: Date = Date()) {
        self.image = image
        self.target = target
        self.timestamp = timestamp
    }
}

/// Provides available windows for capture selection.
public struct WindowInfo: Identifiable, Hashable {
    public let id: CGWindowID
    public let title: String
    public let appName: String
    public let appIcon: CGImage?
    public let frame: CGRect

    public init(id: CGWindowID, title: String, appName: String, appIcon: CGImage?, frame: CGRect) {
        self.id = id
        self.title = title
        self.appName = appName
        self.appIcon = appIcon
        self.frame = frame
    }

    public static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Abstracts screen and window capture functionality.
/// Current implementation: ScreenCaptureKit (local).
/// Future App Store implementation: same (sandbox-compatible with entitlement).
public protocol CaptureProvider: Sendable {
    /// Lists all available windows that can be captured.
    func availableWindows() async throws -> [WindowInfo]

    /// Captures a specific window by its ID.
    func captureWindow(id: CGWindowID) async throws -> CaptureResult

    /// Captures a specific screen region.
    func captureRegion(_ rect: CGRect) async throws -> CaptureResult
}
