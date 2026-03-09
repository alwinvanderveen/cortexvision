import Testing
@testable import CortexVision

@Suite("CortexVision Core")
struct CortexVisionCoreTests {
    @Test("Application version is defined",
          .tags(.core))
    func versionIsDefined() {
        // Functional: Application reports a valid version string
        // Technical: CortexVision.version returns non-empty semantic version
        // Input: none
        // Expected: version string matching "X.Y.Z" format
        #expect(!CortexVision.version.isEmpty)
        #expect(CortexVision.version.contains("."))
    }
}

extension Tag {
    @Tag static var core: Self
    @Tag static var capture: Self
    @Tag static var ocr: Self
    @Tag static var figures: Self
    @Tag static var export: Self
    @Tag static var ui: Self
}
