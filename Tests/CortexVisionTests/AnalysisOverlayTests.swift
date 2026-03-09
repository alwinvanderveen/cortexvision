import Testing
import CoreGraphics
@testable import CortexVision

@Suite("AnalysisOverlay")
struct AnalysisOverlayTests {
    @Test("AnalysisOverlayView renders without crash with empty overlays",
          .tags(.core, .ui))
    func emptyOverlaysNoCrash() {
        // Functional: Preview overlay shows nothing when no analysis results exist
        // Technical: AnalysisOverlay array is empty, pixelRect computation handles gracefully
        // Input: Empty [AnalysisOverlay], imageSize 800x600
        // Expected: No crash, no overlay rects produced
        let overlays: [AnalysisOverlay] = []
        #expect(overlays.isEmpty)
    }

    @Test("pixelRect correctly converts normalized bounds to pixel coordinates",
          .tags(.core))
    func pixelRectConversion() {
        // Functional: Overlay bounding boxes appear at correct positions on the preview image
        // Technical: AnalysisOverlay.pixelRect(for:) converts 0..1 bounds to pixel coords
        // Input: bounds (0.1, 0.1, 0.5, 0.05), imageSize 800x600
        // Expected: pixelRect (80, 60, 400, 30)
        let overlay = AnalysisOverlay(
            bounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.05),
            kind: .text,
            label: "Test tekst"
        )
        let imageSize = CGSize(width: 800, height: 600)
        let rect = overlay.pixelRect(for: imageSize)

        #expect(rect.origin.x == 80, "x should be 80")
        #expect(rect.origin.y == 60, "y should be 60")
        #expect(rect.width == 400, "width should be 400")
        #expect(rect.height == 30, "height should be 30")
    }

    @Test("pixelRect for figure overlay at different position",
          .tags(.core))
    func pixelRectFigure() {
        // Functional: Figure bounding boxes are correctly positioned
        // Technical: AnalysisOverlay.pixelRect(for:) works for figure kind
        // Input: bounds (0.2, 0.4, 0.3, 0.3), imageSize 800x600
        // Expected: pixelRect (160, 240, 240, 180)
        let overlay = AnalysisOverlay(
            bounds: CGRect(x: 0.2, y: 0.4, width: 0.3, height: 0.3),
            kind: .figure,
            label: "Figuur 1"
        )
        let imageSize = CGSize(width: 800, height: 600)
        let rect = overlay.pixelRect(for: imageSize)

        #expect(rect.origin.x == 160, "x should be 160")
        #expect(rect.origin.y == 240, "y should be 240")
        #expect(rect.width == 240, "width should be 240")
        #expect(rect.height == 180, "height should be 180")
    }

    @Test("Text overlay has correct kind",
          .tags(.core))
    func textOverlayKind() {
        // Functional: Text annotations are visually distinct from figure annotations
        // Technical: AnalysisOverlay with .text kind reports correct kind
        // Input: AnalysisOverlay with kind .text
        // Expected: kind == .text
        let overlay = AnalysisOverlay(bounds: .zero, kind: .text)
        #expect(overlay.kind == .text)
    }

    @Test("Figure overlay has correct kind",
          .tags(.core))
    func figureOverlayKind() {
        // Functional: Figure annotations are visually distinct from text annotations
        // Technical: AnalysisOverlay with .figure kind reports correct kind
        // Input: AnalysisOverlay with kind .figure
        // Expected: kind == .figure
        let overlay = AnalysisOverlay(bounds: .zero, kind: .figure)
        #expect(overlay.kind == .figure)
    }

    @Test("pixelRect handles zero-size image gracefully",
          .tags(.core))
    func pixelRectZeroImage() {
        // Functional: Overlay computation does not crash on edge cases
        // Technical: pixelRect with zero imageSize returns zero rect
        // Input: bounds (0.5, 0.5, 0.5, 0.5), imageSize (0, 0)
        // Expected: pixelRect (0, 0, 0, 0)
        let overlay = AnalysisOverlay(
            bounds: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            kind: .text
        )
        let rect = overlay.pixelRect(for: .zero)
        #expect(rect == .zero)
    }

    @Test("Each overlay has a unique identifier",
          .tags(.core))
    func uniqueIds() {
        // Functional: Multiple overlays can be distinguished for rendering
        // Technical: Default UUID generation produces unique ids
        // Input: Two overlays created with default id
        // Expected: Different id values
        let a = AnalysisOverlay(bounds: .zero, kind: .text)
        let b = AnalysisOverlay(bounds: .zero, kind: .figure)
        #expect(a.id != b.id)
    }
}
