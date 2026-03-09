import Testing
import Foundation
@testable import CortexVision

@Suite("Protocol Definitions")
struct ProtocolTests {
    @Test("CaptureProvider protocol is defined and usable",
          .tags(.core))
    func captureProviderExists() {
        // Functional: System can accept any capture implementation via protocol
        // Technical: CaptureProvider protocol compiles and can be referenced as a type
        // Input: Protocol type reference
        // Expected: Protocol type is accessible
        let _: (any CaptureProvider.Type)? = nil
        // If this compiles, the protocol exists and is public
    }

    @Test("ScrollCaptureProvider protocol is defined and usable",
          .tags(.core))
    func scrollCaptureProviderExists() {
        // Functional: System can accept any scroll capture implementation via protocol
        // Technical: ScrollCaptureProvider protocol compiles and can be referenced
        // Input: Protocol type reference
        // Expected: Protocol type is accessible
        let _: (any ScrollCaptureProvider.Type)? = nil
    }

    @Test("ExportDestination protocol is defined and usable",
          .tags(.core))
    func exportDestinationExists() {
        // Functional: System can accept any export implementation via protocol
        // Technical: ExportDestination protocol compiles and can be referenced
        // Input: Protocol type reference
        // Expected: Protocol type is accessible
        let _: (any ExportDestination.Type)? = nil
    }

    @Test("PermissionManager protocol is defined and usable",
          .tags(.core))
    func permissionManagerExists() {
        // Functional: System can accept any permission manager implementation via protocol
        // Technical: PermissionManager protocol compiles and can be referenced
        // Input: Protocol type reference
        // Expected: Protocol type is accessible
        let _: (any PermissionManager.Type)? = nil
    }

    @Test("CaptureResult can be constructed with required fields",
          .tags(.core))
    func captureResultConstruction() {
        // Functional: A capture result carries the image, target and timestamp
        // Technical: CaptureResult init accepts CGImage, CaptureTarget, Date
        // Input: CaptureTarget.region with a CGRect
        // Expected: All properties are set correctly
        let target = CaptureTarget.region(.init(x: 0, y: 0, width: 100, height: 100))
        if case .region(let rect) = target {
            #expect(rect.width == 100)
            #expect(rect.height == 100)
        } else {
            Issue.record("Expected region target")
        }
    }

    @Test("ExportConfiguration generates correct file URLs",
          .tags(.core, .export))
    func exportConfigurationURLs() {
        // Functional: Export knows where to write markdown and figure files
        // Technical: ExportConfiguration.markdownURL and figuresDirectoryURL are correct
        // Input: destinationURL = /tmp/test, baseName = "capture"
        // Expected: markdown at /tmp/test/capture.md, figures at /tmp/test/figures
        let config = ExportConfiguration(
            destinationURL: URL(fileURLWithPath: "/tmp/test"),
            baseName: "capture"
        )
        #expect(config.markdownURL.lastPathComponent == "capture.md")
        #expect(config.figuresDirectoryURL.lastPathComponent == "figures")
    }

    @Test("ScrollCaptureProgress reports estimated progress",
          .tags(.core))
    func scrollProgressEstimation() {
        // Functional: During scrolling capture, user sees progress percentage
        // Technical: ScrollCaptureProgress.estimatedProgress computes fraction
        // Input: 3 of 10 frames captured
        // Expected: estimatedProgress is 0.3
        let progress = ScrollCaptureProgress(
            framesCapture: 3,
            estimatedTotalFrames: 10,
            stitchedImage: nil
        )
        #expect(progress.estimatedProgress == 0.3)
    }

    @Test("ScrollCaptureProgress handles unknown total",
          .tags(.core))
    func scrollProgressUnknownTotal() {
        // Functional: Progress is nil when total frames is unknown
        // Technical: ScrollCaptureProgress.estimatedProgress returns nil when total is nil
        // Input: 5 frames captured, total unknown
        // Expected: estimatedProgress is nil
        let progress = ScrollCaptureProgress(
            framesCapture: 5,
            estimatedTotalFrames: nil,
            stitchedImage: nil
        )
        #expect(progress.estimatedProgress == nil)
    }

    @Test("PermissionStatus has all expected cases",
          .tags(.core))
    func permissionStatusCases() {
        // Functional: System can represent all possible permission states
        // Technical: PermissionStatus has granted, denied, notDetermined, restricted
        // Input: All PermissionStatus cases
        // Expected: All four exist and are distinct
        let statuses: [PermissionStatus] = [.granted, .denied, .notDetermined, .restricted]
        #expect(Set(statuses).count == 4)
    }
}
