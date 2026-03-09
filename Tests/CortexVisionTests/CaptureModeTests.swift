import Testing
@testable import CortexVision

@Suite("CaptureMode")
struct CaptureModeTests {
    @Test("All capture modes have a non-empty label",
          .tags(.core))
    func allModesHaveLabel() {
        // Functional: Each capture mode displays a descriptive label in the toolbar
        // Technical: CaptureMode.allCases.label returns non-empty strings
        // Input: All CaptureMode cases
        // Expected: Each label is non-empty
        for mode in CaptureMode.allCases {
            #expect(!mode.label.isEmpty, "Mode \(mode.rawValue) should have a label")
        }
    }

    @Test("All capture modes have an SF Symbol",
          .tags(.core))
    func allModesHaveSystemImage() {
        // Functional: Each capture mode displays an icon in the toolbar
        // Technical: CaptureMode.allCases.systemImage returns valid SF Symbol names
        // Input: All CaptureMode cases
        // Expected: Each systemImage is non-empty
        for mode in CaptureMode.allCases {
            #expect(!mode.systemImage.isEmpty, "Mode \(mode.rawValue) should have a systemImage")
        }
    }

    @Test("There are exactly three capture modes",
          .tags(.core))
    func threeModes() {
        // Functional: The app offers three capture modes: window, region, scrolling
        // Technical: CaptureMode.allCases.count == 3
        // Input: CaptureMode.allCases
        // Expected: count is 3
        #expect(CaptureMode.allCases.count == 3)
    }

    @Test("Each mode has a unique identifier",
          .tags(.core))
    func uniqueIdentifiers() {
        // Functional: Toolbar can distinguish between modes for selection state
        // Technical: CaptureMode.id values are unique across all cases
        // Input: All CaptureMode cases
        // Expected: All id values are distinct
        let ids = CaptureMode.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
