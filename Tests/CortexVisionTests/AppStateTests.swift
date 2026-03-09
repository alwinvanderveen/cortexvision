import Testing
@testable import CortexVision

@Suite("CaptureState")
struct CaptureStateTests {
    @Test("Idle state shows no capture message",
          .tags(.core))
    func idleStatusText() {
        // Functional: Status bar shows "No capture" when app has not captured anything
        // Technical: CaptureState.idle.statusText returns "No capture"
        // Input: CaptureState.idle
        // Expected: "No capture"
        let state = CaptureState.idle
        #expect(state.statusText == "No capture")
    }

    @Test("Capturing state shows progress message",
          .tags(.core))
    func capturingStatusText() {
        // Functional: Status bar indicates capture is in progress
        // Technical: CaptureState.capturing.statusText contains "Capturing"
        // Input: CaptureState.capturing
        // Expected: "Capturing..."
        let state = CaptureState.capturing
        #expect(state.statusText == "Capturing...")
    }

    @Test("Captured state shows dimensions",
          .tags(.core))
    func capturedStatusText() {
        // Functional: After capture, status bar shows image dimensions
        // Technical: CaptureState.captured(width:height:).statusText contains dimensions
        // Input: CaptureState.captured(width: 1920, height: 1080)
        // Expected: "Captured 1920×1080"
        let state = CaptureState.captured(width: 1920, height: 1080)
        #expect(state.statusText.contains("1920"))
        #expect(state.statusText.contains("1080"))
    }

    @Test("Analyzed state shows word and figure count",
          .tags(.core))
    func analyzedStatusText() {
        // Functional: After analysis, status bar shows word and figure counts
        // Technical: CaptureState.analyzed.statusText contains counts
        // Input: CaptureState.analyzed(wordCount: 42, figureCount: 3)
        // Expected: Contains "42 words" and "3 figures"
        let state = CaptureState.analyzed(wordCount: 42, figureCount: 3)
        #expect(state.statusText.contains("42"))
        #expect(state.statusText.contains("3"))
    }

    @Test("Error state shows error message",
          .tags(.core))
    func errorStatusText() {
        // Functional: Status bar shows error description when something goes wrong
        // Technical: CaptureState.error.statusText contains the error message
        // Input: CaptureState.error("Permission denied")
        // Expected: Contains "Permission denied"
        let state = CaptureState.error("Permission denied")
        #expect(state.statusText.contains("Permission denied"))
    }
}
