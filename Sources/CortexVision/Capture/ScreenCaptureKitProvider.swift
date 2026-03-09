import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Production implementation of CaptureProvider using ScreenCaptureKit.
public final class ScreenCaptureKitProvider: CaptureProvider {
    public init() {}

    public func availableWindows() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        return content.windows.compactMap { window in
            guard let app = window.owningApplication,
                  !window.title.isNilOrEmpty,
                  window.frame.width > 50,
                  window.frame.height > 50 else {
                return nil
            }

            let appIcon = runningApplication(pid: app.processID)?.icon?.cgImage(
                forProposedRect: nil, context: nil, hints: nil
            )

            return WindowInfo(
                id: window.windowID,
                title: window.title ?? app.applicationName,
                appName: app.applicationName,
                appIcon: appIcon,
                frame: window.frame
            )
        }
    }

    public func captureWindow(id: CGWindowID) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw CaptureError.windowNotFound(id)
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2  // Retina
        config.height = Int(window.frame.height) * 2
        config.captureResolution = .best
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return CaptureResult(
            image: image,
            target: .window(windowID: id, title: window.title ?? "", appName: window.owningApplication?.applicationName ?? "")
        )
    }

    public func captureRegion(_ rect: CGRect) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard !content.displays.isEmpty else {
            throw CaptureError.noDisplay
        }

        // rect is in AppKit screen coordinates (points, origin bottom-left of primary).
        // Find the NSScreen that contains the selection, then match it to an SCDisplay.
        let rectCenter = NSPoint(x: rect.midX, y: rect.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(rectCenter) })
                ?? NSScreen.main else {
            throw CaptureError.noDisplay
        }

        // Match NSScreen to SCDisplay by comparing frame dimensions
        let display = content.displays.first(where: {
            abs(CGFloat($0.width) - screen.frame.width) < 2 &&
            abs(CGFloat($0.height) - screen.frame.height) < 2
        }) ?? content.displays.first(where: {
            // Fallback: match by display ID if available
            $0.displayID == screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        }) ?? content.displays.first!

        // Convert AppKit screen coordinates to CG coordinates for this screen.
        // AppKit: origin at bottom-left of primary screen, y increases upward.
        // CG/SCKit sourceRect: origin at top-left of the display, y increases downward.
        let screenFrame = screen.frame

        // Make rect relative to this screen
        let localX = rect.origin.x - screenFrame.origin.x
        let localAppKitY = rect.origin.y - screenFrame.origin.y

        // Flip Y within this screen's height (AppKit bottom-up → CG top-down)
        let localCGY = screenFrame.height - localAppKitY - rect.height

        let sourceRect = CGRect(
            x: max(0, localX),
            y: max(0, localCGY),
            width: rect.width,
            height: rect.height
        ).intersection(CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height))

        guard !sourceRect.isNull, sourceRect.width > 0, sourceRect.height > 0 else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = Int(sourceRect.width) * 2
        config.height = Int(sourceRect.height) * 2
        config.captureResolution = .best
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return CaptureResult(
            image: image,
            target: .region(rect)
        )
    }
}

/// Errors specific to capture operations.
public enum CaptureError: Error, LocalizedError {
    case windowNotFound(CGWindowID)
    case noDisplay
    case permissionDenied
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .windowNotFound(let id):
            return "Window with ID \(id) not found"
        case .noDisplay:
            return "No display available for capture"
        case .permissionDenied:
            return "Screen recording permission is required. Open System Settings > Privacy & Security > Screen Recording to grant access."
        case .cancelled:
            return "Capture was cancelled"
        }
    }
}

// MARK: - Coordinate Conversion

/// Converts a rect from AppKit screen coordinates (origin bottom-left)
/// to ScreenCaptureKit/CoreGraphics coordinates (origin top-left),
/// clamped to the given display bounds.
///
/// Returns `nil` if the resulting rect has zero or negative area (fully off-screen).
public func flipAndClampRect(_ appKitRect: CGRect, displayWidth: CGFloat, displayHeight: CGFloat) -> CGRect? {
    let flipped = CGRect(
        x: appKitRect.origin.x,
        y: displayHeight - appKitRect.origin.y - appKitRect.height,
        width: appKitRect.width,
        height: appKitRect.height
    )
    let clamped = flipped.intersection(
        CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
    )
    guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else {
        return nil
    }
    return clamped
}

// MARK: - Helpers

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let value): return value.isEmpty
        }
    }
}

private func runningApplication(pid: pid_t) -> NSRunningApplication? {
    NSRunningApplication(processIdentifier: pid)
}
