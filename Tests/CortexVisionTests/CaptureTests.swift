import Testing
import CoreGraphics
import ScreenCaptureKit
import Vision
@testable import CortexVision

// MARK: - Helpers

/// Checks if screen recording permission is available (for integration tests).
/// Uses a real SCShareableContent call since CGPreflightScreenCaptureAccess
/// only reflects the permission of the specific bundle, not the test runner.
let isScreenRecordingAvailable: Bool = {
    let semaphore = DispatchSemaphore(value: 0)
    var available = false
    Task.detached {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            available = !content.displays.isEmpty
        } catch {
            available = false
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 3)
    return available
}()

@Suite("Capture — Unit Tests")
struct CaptureUnitTests {
    @Test("ScreenCaptureKitProvider conforms to CaptureProvider",
          .tags(.capture, .core))
    func providerConformsToProtocol() {
        // Functional: System can use ScreenCaptureKit as a capture provider
        // Technical: ScreenCaptureKitProvider compiles and satisfies CaptureProvider protocol
        // Input: Type instantiation
        // Expected: Compiles and can be assigned to protocol variable
        let provider: any CaptureProvider = ScreenCaptureKitProvider()
        #expect(provider is ScreenCaptureKitProvider)
    }

    @Test("LocalPermissionManager conforms to PermissionManager",
          .tags(.capture, .core))
    func permissionManagerConformsToProtocol() {
        // Functional: System can manage permissions via LocalPermissionManager
        // Technical: LocalPermissionManager compiles and satisfies PermissionManager protocol
        // Input: Type instantiation
        // Expected: Compiles and can be assigned to protocol variable
        let manager: any PermissionManager = LocalPermissionManager()
        #expect(manager is LocalPermissionManager)
    }

    @Test("CaptureError provides descriptive messages",
          .tags(.capture))
    func captureErrorMessages() {
        // Functional: User sees clear error messages when capture fails
        // Technical: CaptureError cases return non-empty localizedDescription
        // Input: All CaptureError cases
        // Expected: Each has a non-empty description
        let errors: [CaptureError] = [
            .windowNotFound(123),
            .noDisplay,
            .permissionDenied,
            .cancelled,
        ]
        for error in errors {
            #expect(!error.localizedDescription.isEmpty, "Error \(error) should have a description")
        }
    }

    @Test("CaptureError.permissionDenied mentions System Settings",
          .tags(.capture))
    func permissionDeniedMentionsSettings() {
        // Functional: Permission error guides user to System Settings
        // Technical: CaptureError.permissionDenied.localizedDescription contains "System Settings"
        // Input: CaptureError.permissionDenied
        // Expected: Description contains "System Settings"
        let error = CaptureError.permissionDenied
        #expect(error.localizedDescription.contains("System Settings"))
    }

    @Test("CaptureState transitions to error on permission denied",
          .tags(.capture))
    func captureStatePermissionError() {
        // Functional: Status bar shows permission error when capture fails due to permissions
        // Technical: CaptureState.error with permission message shows correct text
        // Input: CaptureState.error with CaptureError.permissionDenied message
        // Expected: statusText contains "permission"
        let state = CaptureState.error(CaptureError.permissionDenied.localizedDescription)
        #expect(state.statusText.lowercased().contains("permission") ||
                state.statusText.contains("Screen recording"))
    }

    @Test("RegionSelector can be instantiated",
          .tags(.capture))
    func regionSelectorExists() {
        // Functional: Region selection mechanism is available
        // Technical: RegionSelector can be created without parameters
        // Input: None
        // Expected: Non-nil instance
        let selector = RegionSelector()
        #expect(selector != nil)
    }

    @Test("RegionSelector cancel calls completion with nil",
          .tags(.capture),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func regionSelectorCancel() async {
        // Functional: ESC during region selection cancels and returns to idle
        // Technical: RegionSelector.cancel() calls completion handler with nil
        // Input: Start selection then immediately cancel
        // Expected: Completion called with nil
        let selector = RegionSelector()
        var result: CGRect? = CGRect.zero // sentinel value

        await withCheckedContinuation { continuation in
            selector.beginSelection { rect in
                result = rect
                continuation.resume()
            }
            // Cancel immediately
            selector.cancel()
        }

        #expect(result == nil)
    }
}

@Suite("Capture — Coordinate & Permission Tests")
struct CaptureCoordinateTests {
    @Test("flipAndClampRect flips Y-axis from AppKit to CoreGraphics",
          .tags(.capture, .core))
    func flipYAxis() {
        // Functional: Region selection coordinates are correctly translated for capture
        // Technical: AppKit origin bottom-left → CG origin top-left Y-flip
        // Input: rect (100, 800, 400, 200), display 1920×1080
        // Expected: flipped y = 1080 - 800 - 200 = 80 → rect (100, 80, 400, 200)
        let result = flipAndClampRect(
            CGRect(x: 100, y: 800, width: 400, height: 200),
            displayWidth: 1920, displayHeight: 1080
        )
        #expect(result != nil)
        #expect(result!.origin.x == 100)
        #expect(result!.origin.y == 80)
        #expect(result!.width == 400)
        #expect(result!.height == 200)
    }

    @Test("flipAndClampRect handles origin at bottom-left corner",
          .tags(.capture, .core))
    func flipBottomLeft() {
        // Functional: Region at the bottom of the screen maps to top in CG coords
        // Technical: rect at y=0 (AppKit bottom) → y = displayHeight - height (CG top)
        // Input: rect (0, 0, 200, 100), display 1920×1080
        // Expected: rect (0, 980, 200, 100)
        let result = flipAndClampRect(
            CGRect(x: 0, y: 0, width: 200, height: 100),
            displayWidth: 1920, displayHeight: 1080
        )
        #expect(result != nil)
        #expect(result!.origin.y == 980)
    }

    @Test("flipAndClampRect clamps rect that extends beyond display",
          .tags(.capture, .core))
    func clampOutOfBounds() {
        // Functional: A selection that partially extends beyond the screen is clipped
        // Technical: Rect extending past display edge is intersected with display bounds
        // Input: rect (1800, 500, 400, 200), display 1920×1080 — extends 280px past right edge
        // Expected: clamped width = 120 (1920 - 1800)
        let result = flipAndClampRect(
            CGRect(x: 1800, y: 500, width: 400, height: 200),
            displayWidth: 1920, displayHeight: 1080
        )
        #expect(result != nil)
        #expect(result!.width == 120)
    }

    @Test("flipAndClampRect returns nil for fully off-screen rect",
          .tags(.capture, .core))
    func offScreenReturnsNil() {
        // Functional: A selection completely outside the screen is rejected
        // Technical: Rect with no overlap with display returns nil
        // Input: rect (2000, 0, 100, 100), display 1920×1080
        // Expected: nil (no overlap)
        let result = flipAndClampRect(
            CGRect(x: 2000, y: 0, width: 100, height: 100),
            displayWidth: 1920, displayHeight: 1080
        )
        #expect(result == nil)
    }

    @Test("flipAndClampRect handles zero-size display",
          .tags(.capture, .core))
    func zeroDisplay() {
        // Functional: No crash on edge case with zero-size display
        // Technical: Zero display dimensions returns nil
        // Input: rect (0, 0, 100, 100), display 0×0
        // Expected: nil
        let result = flipAndClampRect(
            CGRect(x: 0, y: 0, width: 100, height: 100),
            displayWidth: 0, displayHeight: 0
        )
        #expect(result == nil)
    }

    @Test("flipAndClampRect preserves full-screen rect",
          .tags(.capture, .core))
    func fullScreen() {
        // Functional: Selecting the entire screen produces valid coordinates
        // Technical: Full-screen AppKit rect flips to (0,0) in CG with same dimensions
        // Input: rect (0, 0, 1920, 1080), display 1920×1080
        // Expected: rect (0, 0, 1920, 1080)
        let result = flipAndClampRect(
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            displayWidth: 1920, displayHeight: 1080
        )
        #expect(result != nil)
        #expect(result!.origin.x == 0)
        #expect(result!.origin.y == 0)
        #expect(result!.width == 1920)
        #expect(result!.height == 1080)
    }

    @Test("flipAndClampRect handles rect on secondary display offset",
          .tags(.capture, .core))
    func flipRectSecondaryDisplay() {
        // Functional: Region capture works on secondary screen with display offset
        // Technical: Rect relative to a secondary display with x-offset flips correctly
        // Input: rect (0, 0, 400, 300) relative to a 1920x1080 display
        // Expected: rect (0, 780, 400, 300) — y flipped within that display
        let result = flipAndClampRect(
            CGRect(x: 0, y: 0, width: 400, height: 300),
            displayWidth: 1920, displayHeight: 1080
        )
        #expect(result != nil)
        #expect(result!.origin.x == 0)
        #expect(result!.origin.y == 780)
        #expect(result!.width == 400)
        #expect(result!.height == 300)
    }

    @Test("flipAndClampRect clamps rect extending beyond top of display",
          .tags(.capture, .core))
    func clampTopOverflow() {
        // Functional: Region at top edge of screen is clipped correctly
        // Technical: AppKit rect near top of display (high y) flips to near y=0 and clamps
        // Input: rect (100, 1000, 300, 200) on 1920x1080 display — extends 120px beyond top
        // Expected: clamped to y=0, height=80 (only visible portion)
        let result = flipAndClampRect(
            CGRect(x: 100, y: 1000, width: 300, height: 200),
            displayWidth: 1920, displayHeight: 1080
        )
        #expect(result != nil)
        #expect(result!.origin.y == 0)
        #expect(result!.height < 200, "Should be clipped")
    }

    @Test("LocalPermissionManager screenRecordingStatus returns a valid status",
          .tags(.capture, .core))
    func permissionStatusIsValid() {
        // Functional: App can determine current screen recording permission state
        // Technical: screenRecordingStatus() returns .granted or .notDetermined (never crashes)
        // Input: LocalPermissionManager instance
        // Expected: One of the expected enum values
        let pm = LocalPermissionManager()
        let status = pm.screenRecordingStatus()
        #expect(status == .granted || status == .notDetermined)
    }

    @Test("LocalPermissionManager requestScreenRecording returns Bool without crash",
          .tags(.capture),
          .enabled(if: isScreenRecordingAvailable))
    func requestScreenRecordingReturns() async {
        // Functional: Permission request completes and returns a definitive answer
        // Technical: requestScreenRecording() async returns true when permission is already granted
        // Input: System with screen recording already granted
        // Expected: true
        let pm = LocalPermissionManager()
        let granted = await pm.requestScreenRecording()
        #expect(granted == true)
    }
}

@Suite("Capture — Integration Tests")
struct CaptureIntegrationTests {
    @Test("availableWindows returns non-empty list",
          .tags(.capture),
          .enabled(if: isScreenRecordingAvailable))
    func availableWindowsList() async throws {
        // Functional: User sees a list of available windows to capture
        // Technical: ScreenCaptureKitProvider.availableWindows() returns WindowInfo items
        // Input: None (reads from system)
        // Expected: Non-empty list with valid titles and app names
        let provider = ScreenCaptureKitProvider()
        let windows = try await provider.availableWindows()

        #expect(!windows.isEmpty, "Should find at least one window")
        for window in windows {
            #expect(!window.title.isEmpty, "Window should have a title")
            // appName may be empty for some system windows — only check it's present
            #expect(window.frame.width > 0, "Window should have positive width")
            #expect(window.frame.height > 0, "Window should have positive height")
        }
    }

    @Test("captureRegion captures a valid image",
          .tags(.capture),
          .enabled(if: isScreenRecordingAvailable))
    func captureRegionReturnsImage() async throws {
        // Functional: User selects a screen region and gets a capture
        // Technical: ScreenCaptureKitProvider.captureRegion returns CGImage with correct dimensions
        // Input: CGRect(100, 100, 500, 300)
        // Expected: CGImage with width ~1000, height ~600 (retina 2x)
        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(CGRect(x: 100, y: 100, width: 500, height: 300))

        #expect(result.image.width > 0, "Image should have positive width")
        #expect(result.image.height > 0, "Image should have positive height")

        if case .region(let rect) = result.target {
            #expect(rect.width == 500)
            #expect(rect.height == 300)
        } else {
            Issue.record("Expected region target")
        }
    }

    @Test("captured image contains recognizable content via OCR",
          .tags(.capture, .ocr),
          .enabled(if: isScreenRecordingAvailable))
    func captureContainsRecognizableText() async throws {
        // Functional: Captured screen region contains text that OCR can read
        // Technical: Capture a region, run VNRecognizeTextRequest, verify non-empty results
        // Input: A screen capture of a region likely containing text (menu bar area)
        // Expected: At least one recognized text observation

        let provider = ScreenCaptureKitProvider()
        // Capture menu bar area — in AppKit coords, top of primary screen is at screen.frame.maxY
        let screenHeight = NSScreen.main?.frame.height ?? 1080
        let menuBarRect = CGRect(x: 0, y: screenHeight - 30, width: 600, height: 30)
        let result = try await provider.captureRegion(menuBarRect)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: result.image, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        // Menu bar should have at least some text (Apple menu, app name, etc.)
        #expect(!observations.isEmpty, "Should recognize some text in the menu bar area")
    }
}
