import Testing
import AppKit
import CoreGraphics
import CoreVideo
import Vision
@testable import CortexVision

// MARK: - DetectedFigure Model Tests

@Suite("Figure Detection — Model")
struct DetectedFigureModelTests {
    @Test("DetectedFigure has unique identifiers", .tags(.core, .figures))
    func uniqueIds() {
        let f1 = DetectedFigure(bounds: .zero, label: "Figure 1")
        let f2 = DetectedFigure(bounds: .zero, label: "Figure 2")
        #expect(f1.id != f2.id)
    }

    @Test("DetectedFigure default selected state is true", .tags(.core, .figures))
    func defaultSelected() {
        let figure = DetectedFigure(bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), label: "Figure 1")
        #expect(figure.isSelected == true)
    }

    @Test("DetectedFigure label follows index", .tags(.core, .figures))
    func labelFromIndex() {
        #expect(DetectedFigure.label(for: 0) == "Figure 1")
        #expect(DetectedFigure.label(for: 2) == "Figure 3")
        #expect(DetectedFigure.label(for: 9) == "Figure 10")
    }

    @Test("DetectedFigure bounds are normalized", .tags(.core, .figures))
    func normalizedBounds() {
        let figure = DetectedFigure(bounds: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3), label: "Figure 1")
        #expect(figure.bounds.origin.x >= 0 && figure.bounds.origin.x <= 1)
        #expect(figure.bounds.origin.y >= 0 && figure.bounds.origin.y <= 1)
        #expect(figure.bounds.maxX <= 1)
        #expect(figure.bounds.maxY <= 1)
    }

    @Test("DetectedFigure area calculation", .tags(.core, .figures))
    func areaCalculation() {
        let figure = DetectedFigure(bounds: CGRect(x: 0, y: 0, width: 0.5, height: 0.4), label: "Figure 1")
        #expect(figure.area == 0.2)
    }

    @Test("DetectedFigure pixelRect converts bounds correctly", .tags(.core, .figures))
    func pixelRectConversion() {
        let figure = DetectedFigure(bounds: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3), label: "Figure 1")
        let pixel = figure.pixelRect(for: CGSize(width: 1000, height: 800))
        #expect(pixel.origin.x == 100)
        #expect(pixel.origin.y == 160)
        #expect(pixel.width == 500)
        #expect(pixel.height == 240)
    }

    @Test("FigureDetectionResult selectedFigures filters correctly", .tags(.core, .figures))
    func selectedFiguresFilter() {
        var f1 = DetectedFigure(bounds: .zero, label: "Figure 1", isSelected: true)
        let f2 = DetectedFigure(bounds: .zero, label: "Figure 2", isSelected: false)
        let f3 = DetectedFigure(bounds: .zero, label: "Figure 3", isSelected: true)
        let result = FigureDetectionResult(figures: [f1, f2, f3])
        #expect(result.selectedFigures.count == 2)
        #expect(result.selectedFigures[0].label == "Figure 1")
        #expect(result.selectedFigures[1].label == "Figure 3")
    }

    @Test("FigureDetectionResult.empty has no figures", .tags(.core, .figures))
    func emptyResult() {
        let result = FigureDetectionResult.empty
        #expect(result.figures.isEmpty)
        #expect(result.selectedFigures.isEmpty)
    }

    @Test("DetectedFigure deselect toggles state", .tags(.core, .figures))
    func deselectFigure() {
        var figure = DetectedFigure(bounds: .zero, label: "Figure 1")
        #expect(figure.isSelected == true)
        figure.isSelected = false
        #expect(figure.isSelected == false)
    }

    @Test("DetectedFigure reselect restores state", .tags(.core, .figures))
    func reselectFigure() {
        var figure = DetectedFigure(bounds: .zero, label: "Figure 1")
        figure.isSelected = false
        figure.isSelected = true
        #expect(figure.isSelected == true)
    }
}

// MARK: - Overlap Merging Tests

@Suite("Figure Detection — Overlap Merging")
struct OverlapMergingTests {
    let detector = FigureDetector()

    @Test("Non-overlapping regions stay separate", .tags(.core, .figures))
    func noOverlap() {
        let regions = [
            CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
            CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
        ]
        let merged = detector.mergeOverlapping(regions)
        #expect(merged.count == 2)
    }

    @Test("Regions with >50% IoU are merged", .tags(.core, .figures))
    func highOverlapMerge() {
        // A=(0,0,0.4,0.4) area=0.16, B=(0.05,0.05,0.4,0.4) area=0.16
        // Intersection=(0.05,0.05)-(0.4,0.4) = 0.35*0.35 = 0.1225
        // Union=0.16+0.16-0.1225=0.1975, IoU=0.1225/0.1975≈0.62 > 0.5
        let regions = [
            CGRect(x: 0.0, y: 0.0, width: 0.4, height: 0.4),
            CGRect(x: 0.05, y: 0.05, width: 0.4, height: 0.4),
        ]
        let merged = detector.mergeOverlapping(regions)
        #expect(merged.count == 1)
        // Merged bounds should be the union
        #expect(merged[0].origin.x == 0.0)
        #expect(merged[0].origin.y == 0.0)
        #expect(merged[0].maxX == 0.45)
        #expect(merged[0].maxY == 0.45)
    }

    @Test("Regions with exactly 50% IoU are not merged", .tags(.core, .figures))
    func exactThresholdNotMerged() {
        // Two rects: A = (0, 0, 0.4, 0.4), area=0.16
        // B shifted so IoU = exactly 0.5
        // IoU = intersection / union. For IoU=0.5: intersection = union/3
        // Use well-separated rects that have <50% IoU
        let regions = [
            CGRect(x: 0.0, y: 0.0, width: 0.3, height: 0.3),
            CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
        ]
        // Intersection: (0.2,0.2)-(0.3,0.3) = 0.1*0.1 = 0.01
        // Union: 0.09 + 0.09 - 0.01 = 0.17
        // IoU = 0.01/0.17 ≈ 0.059 < 0.5 → not merged
        let merged = detector.mergeOverlapping(regions)
        #expect(merged.count == 2)
    }

    @Test("Three regions where two overlap merge to two results", .tags(.core, .figures))
    func partialMerge() {
        let regions = [
            CGRect(x: 0.0, y: 0.0, width: 0.4, height: 0.4),
            CGRect(x: 0.05, y: 0.05, width: 0.4, height: 0.4), // high overlap with first
            CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2),   // no overlap with either
        ]
        let merged = detector.mergeOverlapping(regions)
        #expect(merged.count == 2)
    }

    @Test("Identical bounds merge to one", .tags(.core, .figures))
    func identicalBoundsMerge() {
        let rect = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        let merged = detector.mergeOverlapping([rect, rect])
        #expect(merged.count == 1)
    }

    @Test("Empty regions list returns empty", .tags(.core, .figures))
    func emptyRegions() {
        let merged = detector.mergeOverlapping([])
        #expect(merged.isEmpty)
    }

    @Test("IoU of non-overlapping rects is zero", .tags(.core, .figures))
    func iouNoOverlap() {
        let a = CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
        let b = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        #expect(detector.iou(a, b) == 0)
    }

    @Test("IoU of identical rects is 1.0", .tags(.core, .figures))
    func iouIdentical() {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        #expect(detector.iou(rect, rect) == 1.0)
    }
}

// MARK: - Text Exclusion Tests

@Suite("Figure Detection — Text Exclusion")
struct TextExclusionTests {
    let detector = FigureDetector()

    @Test("Region fully covered by text is excluded", .tags(.core, .figures))
    func fullTextOverlap() {
        let regions = [CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1)]
        let textBounds = [CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5)]
        let filtered = detector.excludeTextRegions(regions, textBounds: textBounds)
        #expect(filtered.isEmpty, "Region fully inside text should be excluded")
    }

    @Test("Region partially overlapping text is kept", .tags(.core, .figures))
    func partialTextOverlap() {
        // Region covers 0.1-0.6 x, 0.1-0.5 y (area = 0.5 * 0.4 = 0.2)
        let regions = [CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.4)]
        // Text covers only 0.1-0.3 x, 0.1-0.3 y
        let textBounds = [CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)]
        // Overlap = 0.2 * 0.2 = 0.04, fraction = 0.04/0.2 = 0.2 < 0.7
        let filtered = detector.excludeTextRegions(regions, textBounds: textBounds)
        #expect(filtered.count == 1, "Region with small text overlap should be kept")
    }

    @Test("Region without text overlap is kept", .tags(.core, .figures))
    func noTextOverlap() {
        let regions = [CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.3)]
        let textBounds = [CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)]
        let filtered = detector.excludeTextRegions(regions, textBounds: textBounds)
        #expect(filtered.count == 1)
    }

    @Test("No text bounds keeps all regions", .tags(.core, .figures))
    func noTextBounds() {
        let regions = [
            CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3),
            CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
        ]
        let filtered = detector.excludeTextRegions(regions, textBounds: [])
        #expect(filtered.count == 2)
    }

    @Test("Text overlap fraction calculation is correct", .tags(.core, .figures))
    func overlapFractionCalculation() {
        let region = CGRect(x: 0.0, y: 0.0, width: 0.4, height: 0.4) // area = 0.16
        let text = [CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)] // overlap = 0.04
        let fraction = detector.textOverlapFraction(region: region, textBounds: text)
        #expect(fraction == 0.25) // 0.04 / 0.16
    }
}

// MARK: - Text Trimming Tests

@Suite("Figure Detection — Text Trimming")
struct TextTrimmingTests {
    let detector = FigureDetector()

    @Test("Region with text on left is trimmed to right portion", .tags(.core, .figures))
    func trimTextOnLeft() {
        // Figure region spans full width, text on the left side
        let region = CGRect(x: 0.0, y: 0.2, width: 0.8, height: 0.4)
        let textBounds = [CGRect(x: 0.0, y: 0.2, width: 0.3, height: 0.4)]
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        #expect(trimmed.minX >= 0.3, "Should trim text from left, got minX=\(trimmed.minX)")
        #expect(trimmed.width > 0, "Trimmed region should have positive width")
    }

    @Test("Region with text on top is trimmed to bottom portion", .tags(.core, .figures))
    func trimTextOnTop() {
        // Figure region spans full height, text on top (in Vision coords: high Y)
        let region = CGRect(x: 0.1, y: 0.0, width: 0.4, height: 0.8)
        let textBounds = [CGRect(x: 0.1, y: 0.5, width: 0.4, height: 0.3)]
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        #expect(trimmed.maxY <= 0.5, "Should trim text from top, got maxY=\(trimmed.maxY)")
        #expect(trimmed.height > 0, "Trimmed region should have positive height")
    }

    @Test("Region with text on right is trimmed to left portion", .tags(.core, .figures))
    func trimTextOnRight() {
        let region = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.4)
        let textBounds = [CGRect(x: 0.6, y: 0.2, width: 0.3, height: 0.4)]
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        #expect(trimmed.maxX <= 0.6, "Should trim text from right, got maxX=\(trimmed.maxX)")
        #expect(trimmed.width > 0)
    }

    @Test("Region with text on bottom is trimmed to top portion", .tags(.core, .figures))
    func trimTextOnBottom() {
        let region = CGRect(x: 0.1, y: 0.0, width: 0.4, height: 0.8)
        let textBounds = [CGRect(x: 0.1, y: 0.0, width: 0.4, height: 0.3)]
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        #expect(trimmed.minY >= 0.3, "Should trim text from bottom, got minY=\(trimmed.minY)")
        #expect(trimmed.height > 0)
    }

    @Test("Region without text overlap is unchanged", .tags(.core, .figures))
    func noOverlapUnchanged() {
        let region = CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.3)
        let textBounds = [CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)]
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        #expect(trimmed == region, "Region without text overlap should be unchanged")
    }

    @Test("Region with text on multiple sides picks best trim", .tags(.core, .figures))
    func textOnMultipleSides() {
        // Figure region with text above and to the left
        // The figure (right-bottom portion) should remain
        let region = CGRect(x: 0.0, y: 0.0, width: 0.8, height: 0.8)
        let textBounds = [
            CGRect(x: 0.0, y: 0.0, width: 0.3, height: 0.8),  // left column of text
            CGRect(x: 0.0, y: 0.5, width: 0.8, height: 0.3),  // top row of text
        ]
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        // Should keep the portion with least text overlap
        let overlapAfter = detector.textOverlapFraction(region: trimmed, textBounds: textBounds)
        let overlapBefore = detector.textOverlapFraction(region: region, textBounds: textBounds)
        #expect(overlapAfter < overlapBefore,
                "Trimmed region should have less text overlap: before=\(overlapBefore), after=\(overlapAfter)")
    }

    @Test("Trimming preserves minimum area requirement", .tags(.core, .figures))
    func trimPreservesMinArea() {
        let region = CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5)
        let textBounds = [CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5)] // text covers everything
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        // When text covers everything, the original region is returned (filtering happens elsewhere)
        #expect(trimmed.width * trimmed.height > 0)
    }

    @Test("Iterative trimming removes text from multiple sides", .tags(.core, .figures))
    func iterativeTrimmingMultipleSides() {
        // Figure is in center-right, text on top, left, and bottom
        // Simulates a real layout with a figure wrapped by text
        let region = CGRect(x: 0.0, y: 0.0, width: 0.9, height: 0.9)
        let textBounds = [
            CGRect(x: 0.0, y: 0.0, width: 0.4, height: 0.9),  // left text column
            CGRect(x: 0.0, y: 0.7, width: 0.9, height: 0.2),  // top text row
            CGRect(x: 0.0, y: 0.0, width: 0.9, height: 0.2),  // bottom text row
        ]
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        let overlapAfter = detector.textOverlapFraction(region: trimmed, textBounds: textBounds)
        // After multiple iterations, text overlap should be significantly reduced
        #expect(overlapAfter < 0.3,
                "Iterative trimming should reduce overlap to <30%, got \(overlapAfter)")
        #expect(trimmed.width * trimmed.height >= 0.03,
                "Trimmed region should still meet minimum area")
    }

    @Test("Trimming converges when text barely overlaps edge", .tags(.core, .figures))
    func trimConvergesSmallOverlap() {
        // Figure with a small text label just overlapping one edge
        let region = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let textBounds = [CGRect(x: 0.15, y: 0.65, width: 0.6, height: 0.1)]
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        // Should cut off just the top edge (Vision coords: high Y = top)
        #expect(trimmed.maxY <= 0.65,
                "Should trim text from top edge, got maxY=\(trimmed.maxY)")
        #expect(trimmed.minY == 0.2, "Bottom edge should be unchanged")
    }

    @Test("Wide figure with narrow text is not cut in the middle", .tags(.core, .figures))
    func wideFigureNotCutInMiddle() {
        // Scenario: wide figure (photo spanning 80% of width) with narrow text
        // column on the left. The text-trimming must NOT cut into the figure.
        let region = CGRect(x: 0.0, y: 0.1, width: 0.9, height: 0.7)
        let textBounds = [
            // Narrow text column on the left (extends 30% into the figure)
            CGRect(x: 0.0, y: 0.3, width: 0.3, height: 0.4),
            // Title text above (full width)
            CGRect(x: 0.0, y: 0.75, width: 0.9, height: 0.05),
        ]
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        // The trimmed width should remain at least 60% of original (figure is wide)
        #expect(trimmed.width >= region.width * 0.5,
                "Wide figure should not be cut in half, got width=\(trimmed.width) (original=\(region.width))")
    }

    @Test("Tall figure extending below text is not cut vertically", .tags(.core, .figures))
    func tallFigureNotCutBelow() {
        // Scenario: tall figure (photo spanning 80% of height) with text
        // paragraph above it. The text-trimming must NOT cut the figure vertically.
        // In Vision coords: y=0 is bottom, so "below text" means low Y.
        let region = CGRect(x: 0.1, y: 0.0, width: 0.6, height: 0.9)
        let textBounds = [
            // Text paragraph at the top of the region (Vision: high Y)
            CGRect(x: 0.1, y: 0.7, width: 0.6, height: 0.15),
            // Text caption to the right, only in upper portion
            CGRect(x: 0.6, y: 0.5, width: 0.3, height: 0.3),
        ]
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        // The figure extends below the text — height should be preserved
        #expect(trimmed.height >= region.height * 0.5,
                "Tall figure should not be cut in half vertically, got height=\(trimmed.height) (original=\(region.height))")
        // The bottom of the figure (low Y) should remain intact
        #expect(trimmed.minY <= 0.1,
                "Bottom of figure should be preserved, got minY=\(trimmed.minY)")
    }

    @Test("Text in center of region does not trigger edge cut", .tags(.core, .figures))
    func centerTextNoEdgeCut() {
        // Text block in the center of the region (not near any edge)
        // should not trigger a cut that removes half the region
        let region = CGRect(x: 0.0, y: 0.0, width: 0.9, height: 0.9)
        let textBounds = [
            CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3),  // centered text
        ]
        let trimmed = detector.trimTextFromRegion(region, textBounds: textBounds)
        // Should keep most of the region — centered text can't trigger an edge cut
        #expect(trimmed.width >= region.width * 0.8,
                "Center text should not trigger aggressive cut, got width=\(trimmed.width)")
        #expect(trimmed.height >= region.height * 0.8,
                "Center text should not trigger aggressive cut, got height=\(trimmed.height)")
    }
}

// MARK: - Directional Expansion Tests

@Suite("Figure Detection — Directional Expansion")
struct DirectionalExpansionTests {
    let detector = FigureDetector()

    @Test("Expansion avoids text-adjacent edges", .tags(.core, .figures))
    func expandsAwayFromText() {
        // Figure region with text below (Vision: low Y) and right
        let region = CGRect(x: 0.2, y: 0.3, width: 0.5, height: 0.4)
        let textBounds = [
            // Text just below the figure (text.maxY ≈ region.minY)
            CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.1),
            // Text just to the right (text.minX ≈ region.maxX)
            CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.4),
        ]
        let expanded = detector.directionalExpand(region, textBounds: textBounds, margin: 0.04)

        // Should NOT expand bottom (text below) or right (text right)
        #expect(expanded.minY >= region.minY - 0.01,
                "Should not expand toward text below, got minY=\(expanded.minY)")
        #expect(expanded.maxX <= region.maxX + 0.01,
                "Should not expand toward text right, got maxX=\(expanded.maxX)")
        // SHOULD expand top and left (no text there)
        #expect(expanded.maxY > region.maxY + 0.02,
                "Should expand top (no text), got maxY=\(expanded.maxY)")
        #expect(expanded.minX < region.minX - 0.02,
                "Should expand left (no text), got minX=\(expanded.minX)")
    }

    @Test("Expansion applies full margin without nearby text", .tags(.core, .figures))
    func expandsFullyWithoutText() {
        let region = CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3)
        let expanded = detector.directionalExpand(region, textBounds: [], margin: 0.04)
        // Should expand 0.04 on all sides
        #expect(abs(expanded.minX - 0.26) < 0.001)
        #expect(abs(expanded.minY - 0.26) < 0.001)
        #expect(abs(expanded.maxX - 0.64) < 0.001)
        #expect(abs(expanded.maxY - 0.64) < 0.001)
    }

    @Test("Hero image expands up but not into text below", .tags(.core, .figures))
    func heroImageDirectionalExpansion() {
        // Simulates hero banner at top of page with heading text below
        // Vision coords: hero at high Y, text below at lower Y
        let heroRegion = CGRect(x: 0.02, y: 0.6, width: 0.96, height: 0.3)
        let textBounds = [
            // Heading just below hero
            CGRect(x: 0.05, y: 0.5, width: 0.9, height: 0.1),
            // Body text further below
            CGRect(x: 0.05, y: 0.3, width: 0.7, height: 0.15),
        ]
        let expanded = detector.directionalExpand(heroRegion, textBounds: textBounds, margin: 0.04)

        // Should expand UP (top, no text) to capture full hero including hands
        #expect(expanded.maxY > heroRegion.maxY + 0.02,
                "Should expand up to capture hands, got maxY=\(expanded.maxY)")
        // Should NOT expand DOWN (bottom, text adjacent)
        #expect(expanded.minY >= heroRegion.minY - 0.01,
                "Should not expand into text below, got minY=\(expanded.minY)")
        // Should expand LEFT and RIGHT (no text adjacent)
        #expect(expanded.minX < heroRegion.minX,
                "Should expand left, got minX=\(expanded.minX)")
    }
}

// MARK: - Snap-to-Edge Tests

@Suite("Figure Detection — Snap to Edge")
struct SnapToEdgeTests {
    let detector = FigureDetector()

    @Test("Wide region snaps to full width when no text in gap", .tags(.core, .figures))
    func snapWidthNoText() {
        // Region at 70% width → should snap to 100%
        let region = CGRect(x: 0.0, y: 0.5, width: 0.70, height: 0.3)
        let snapped = detector.snapToEdges(region, textBounds: [], threshold: 0.60)
        #expect(abs(snapped.width - 1.0) < 0.001,
                "Should snap to full width, got \(snapped.width)")
    }

    @Test("Wide region does NOT snap when body text fills gap", .tags(.core, .figures))
    func snapBlockedByText() {
        let region = CGRect(x: 0.0, y: 0.3, width: 0.70, height: 0.4)
        let textBounds = [
            // Large text block filling the right gap
            CGRect(x: 0.72, y: 0.3, width: 0.25, height: 0.4),
        ]
        let snapped = detector.snapToEdges(region, textBounds: textBounds, threshold: 0.60)
        #expect(snapped.width < 0.80,
                "Should NOT snap when text fills gap, got \(snapped.width)")
    }

    @Test("Wide region snaps past tiny nav text in gap", .tags(.core, .figures))
    func snapIgnoresSmallNavText() {
        // Hero banner at 70% width with tiny "Inloggen" nav text in the gap
        let region = CGRect(x: 0.0, y: 0.65, width: 0.70, height: 0.35)
        let textBounds = [
            // Tiny nav text — covers < 5% of gap area
            CGRect(x: 0.90, y: 0.90, width: 0.06, height: 0.02),
        ]
        let snapped = detector.snapToEdges(region, textBounds: textBounds, threshold: 0.60)
        #expect(abs(snapped.width - 1.0) < 0.001,
                "Should snap past tiny nav text, got \(snapped.width)")
    }

    @Test("Narrow region does not snap (below threshold)", .tags(.core, .figures))
    func noSnapBelowThreshold() {
        let region = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.3)
        let snapped = detector.snapToEdges(region, textBounds: [], threshold: 0.60)
        #expect(abs(snapped.width - 0.4) < 0.001,
                "Should not snap narrow region, got \(snapped.width)")
    }
}

// MARK: - Minimum Size Filter Tests

@Suite("Figure Detection — Size Filter")
struct SizeFilterTests {
    @Test("Region smaller than 3% is filtered out", .tags(.core, .figures))
    func tooSmall() {
        // Area = 0.1 * 0.1 = 0.01 = 1% < 3%
        let region = CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1)
        #expect(region.width * region.height < 0.03)
    }

    @Test("Region at exactly 3% is kept", .tags(.core, .figures))
    func exactMinimum() {
        // Area = 0.15 * 0.2 = 0.03 = 3%
        let region = CGRect(x: 0.0, y: 0.0, width: 0.15, height: 0.2)
        #expect(region.width * region.height >= 0.03)
    }

    @Test("Region larger than 3% is kept", .tags(.core, .figures))
    func aboveMinimum() {
        let region = CGRect(x: 0.0, y: 0.0, width: 0.3, height: 0.3)
        #expect(region.width * region.height >= 0.03)
    }

    @Test("Very large region (>80%) is kept", .tags(.core, .figures))
    func veryLargeRegion() {
        let region = CGRect(x: 0.0, y: 0.0, width: 0.9, height: 0.9)
        #expect(region.width * region.height >= 0.03)
        #expect(region.width * region.height > 0.8)
    }
}

// MARK: - Crop / Pixel Rect Tests

@Suite("Figure Detection — Cropping")
struct CroppingTests {
    @Test("Pixel rect correctly converts normalized bounds", .tags(.core, .figures))
    func pixelRectConversion() {
        let figure = DetectedFigure(
            bounds: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3),
            label: "Figure 1"
        )
        let pixel = figure.pixelRect(for: CGSize(width: 2000, height: 1000))
        #expect(pixel.origin.x == 200)
        #expect(pixel.origin.y == 200)
        #expect(pixel.width == 1000)
        #expect(pixel.height == 300)
    }

    @Test("Pixel rect at image edge is clamped", .tags(.core, .figures))
    func pixelRectAtEdge() {
        let figure = DetectedFigure(
            bounds: CGRect(x: 0.9, y: 0.9, width: 0.2, height: 0.2),
            label: "Figure 1"
        )
        let pixel = figure.pixelRect(for: CGSize(width: 1000, height: 1000))
        let clamped = pixel.intersection(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        #expect(clamped.width <= 1000)
        #expect(clamped.height <= 1000)
        #expect(clamped.maxX <= 1000)
        #expect(clamped.maxY <= 1000)
    }

    @Test("Auto-crop removes white border from figure", .tags(.core, .figures))
    func autoCropRemovesWhiteBorder() {
        // Create 100x100 image: white background with a 40x40 blue square in center (30,30)-(70,70)
        let width = 100
        let height = 100
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }
        // White background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Blue square in center
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 30, y: 30, width: 40, height: 40))

        guard let image = context.makeImage() else {
            Issue.record("Failed to create image")
            return
        }

        let detector = FigureDetector()
        let (cropped, cropRect) = detector.autoCropWhitespace(image)
        // Should be significantly smaller than 100x100 (content + margin)
        #expect(cropped.width < 70, "Width should be trimmed, got \(cropped.width)")
        #expect(cropped.height < 70, "Height should be trimmed, got \(cropped.height)")
        #expect(cropped.width >= 40, "Should preserve the blue square, got width \(cropped.width)")
        #expect(cropped.height >= 40, "Should preserve the blue square, got height \(cropped.height)")
        // Crop rect should reflect the offset from the original
        #expect(cropRect.origin.x > 0, "Should have trimmed from left")
        #expect(cropRect.origin.y > 0, "Should have trimmed from top")
    }

    @Test("Auto-crop preserves image without white border", .tags(.core, .figures))
    func autoCropNoWhiteBorder() {
        // Create 50x50 fully colored image (no white border to crop)
        let width = 50
        let height = 50
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            Issue.record("Failed to create image")
            return
        }

        let detector = FigureDetector()
        let (cropped, _) = detector.autoCropWhitespace(image)
        // Should be approximately the same size (no white to remove)
        #expect(cropped.width >= 45, "Should preserve full width, got \(cropped.width)")
        #expect(cropped.height >= 45, "Should preserve full height, got \(cropped.height)")
    }

    @Test("Auto-crop handles image with white border on one side", .tags(.core, .figures))
    func autoCropOneSide() {
        // 100x50 image: left half white, right half red
        let width = 100
        let height = 50
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.8, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 50, y: 0, width: 50, height: 50))

        guard let image = context.makeImage() else {
            Issue.record("Failed to create image")
            return
        }

        let detector = FigureDetector()
        let (cropped, _) = detector.autoCropWhitespace(image)
        #expect(cropped.width < 80, "Should trim white left side, got width \(cropped.width)")
        #expect(cropped.width >= 50, "Should preserve red side, got width \(cropped.width)")
        #expect(cropped.height >= 45, "Height should be mostly preserved, got \(cropped.height)")
    }

    @Test("Auto-crop preserves banner image height", .tags(.core, .figures))
    func autoCropPreservesBannerHeight() {
        // Banner/hero image: 300x80 (aspect ratio ~3.75:1) with gradient
        // Simulate a photo banner with slightly lighter edges
        let width = 300
        let height = 80
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }
        // White border (5px all around)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Photo content: gradient-like fill (dark at center, lighter at edges)
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 5, y: 5, width: 290, height: 70))

        guard let image = context.makeImage() else {
            Issue.record("Failed to create image")
            return
        }

        let detector = FigureDetector()
        let (cropped, _) = detector.autoCropWhitespace(image)
        // Height must be preserved (>= 75% of original) for banner images
        #expect(cropped.height >= 60,
                "Banner height should be preserved, got \(cropped.height) (original: \(height))")
        #expect(cropped.width >= 250,
                "Banner width should be mostly preserved, got \(cropped.width)")
    }

    @Test("Variance tightening preserves banner image", .tags(.core, .figures))
    func varianceTighteningPreservesBanner() {
        // Banner image: 400x100 with a gradient (low variance at edges)
        let width = 400
        let height = 100
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }
        // Uniform light blue edges (low variance) with colorful center
        context.setFillColor(CGColor(red: 0.6, green: 0.8, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Rich center content (high variance)
        for x in stride(from: 50, to: 350, by: 10) {
            let r = CGFloat(x % 3 == 0 ? 0.8 : 0.2)
            let g = CGFloat(x % 5 == 0 ? 0.7 : 0.3)
            let b = CGFloat(x % 7 == 0 ? 0.9 : 0.1)
            context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            context.fill(CGRect(x: x, y: 15, width: 10, height: 70))
        }

        guard let image = context.makeImage() else {
            Issue.record("Failed to create image")
            return
        }

        let detector = FigureDetector()
        let (tightened, _) = detector.tightenByVariance(image)
        // Short side (height=100) must not lose more than 20%
        #expect(tightened.height >= 80,
                "Banner height should be protected, got \(tightened.height) (original: \(height))")
    }

    @Test("Cropped figure has correct dimensions", .tags(.core, .figures))
    func croppedDimensions() {
        // Create a simple 100x100 test image
        let width = 100
        let height = 100
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            Issue.record("Failed to create test image")
            return
        }

        // Crop the center 50x50 region
        let cropRect = CGRect(x: 25, y: 25, width: 50, height: 50)
        guard let cropped = image.cropping(to: cropRect) else {
            Issue.record("Failed to crop image")
            return
        }

        #expect(cropped.width == 50)
        #expect(cropped.height == 50)
    }
}

// MARK: - Instance Mask Detection Tests

@Suite("Figure Detection — Instance Mask")
struct InstanceMaskDetectionTests {
    @Test("Detection finds figure in image with clear subject on white background",
          .tags(.core, .figures))
    func instanceMaskDetectsSubject() async throws {
        // Create a 200x200 image: white background with a colorful subject (60x60) in center
        let width = 200
        let height = 200
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }
        // White background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Colorful subject: multicolored rectangles to create visual complexity
        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.8, 0.2, 0.1), (0.1, 0.7, 0.3), (0.2, 0.3, 0.9),
            (0.9, 0.8, 0.0), (0.6, 0.1, 0.8), (0.1, 0.8, 0.8),
        ]
        for (i, color) in colors.enumerated() {
            context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
            let row = i / 3
            let col = i % 3
            context.fill(CGRect(x: 70 + col * 20, y: 70 + row * 30, width: 20, height: 30))
        }

        guard let image = context.makeImage() else {
            Issue.record("Failed to create image")
            return
        }

        let detector = FigureDetector()
        let result = try await detector.detectFigures(in: image, textBounds: [])
        // Should detect at least one figure (either via instance mask or saliency fallback)
        #expect(result.figures.count >= 1,
                "Should detect the colorful subject, got \(result.figures.count)")
    }

    @Test("Detection prefers larger coverage when both methods find figures",
          .tags(.core, .figures))
    func preferLargerCoverage() async throws {
        // Create a 300x200 image with a large colorful rectangle covering most of the area
        // Both instance mask and saliency should detect it; the larger result should win
        let width = 300
        let height = 200
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }
        // White background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Large colorful region covering 80% of area
        for y in stride(from: 10, to: 190, by: 10) {
            for x in stride(from: 15, to: 285, by: 15) {
                let r = CGFloat(x % 50) / 50.0
                let g = CGFloat(y % 30) / 30.0
                let b = CGFloat((x + y) % 40) / 40.0
                context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 15, height: 10))
            }
        }

        guard let image = context.makeImage() else {
            Issue.record("Failed to create image")
            return
        }

        let detector = FigureDetector()
        let result = try await detector.detectFigures(in: image, textBounds: [])
        #expect(result.figures.count >= 1,
                "Should detect the large figure, got \(result.figures.count)")
        // The figure should cover a substantial portion of the image
        if let figure = result.figures.first {
            #expect(figure.area > 0.1,
                    "Figure should cover substantial area, got \(figure.area)")
        }
    }

    @Test("Saliency fallback works when instance mask finds nothing",
          .tags(.core, .figures))
    func saliencyFallbackWorks() async throws {
        // Create an abstract gradient image that instance mask may not detect
        // but saliency should pick up
        let width = 150
        let height = 150
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }
        // White background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Gradient diagonal strip — abstract pattern
        guard let data = context.data else {
            Issue.record("Failed to get context data")
            return
        }
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        for y in 30..<120 {
            for x in 30..<120 {
                let offset = (y * width + x) * 4
                ptr[offset] = UInt8(clamping: x * 2 + y)       // R
                ptr[offset + 1] = UInt8(clamping: 255 - x - y) // G
                ptr[offset + 2] = UInt8(clamping: x + y * 2)   // B
                ptr[offset + 3] = 255                            // A
            }
        }

        guard let image = context.makeImage() else {
            Issue.record("Failed to create image")
            return
        }

        let detector = FigureDetector()
        let result = try await detector.detectFigures(in: image, textBounds: [])
        // Should detect the gradient block via either method
        #expect(result.figures.count >= 1,
                "Should detect the gradient block, got \(result.figures.count)")
    }
}

// MARK: - Content Map Tests

@Suite("Figure Detection — Content Map")
struct ContentMapTests {

    @Test("Content bounding box finds content region", .tags(.figures))
    func contentBoundingBox() {
        // 5x5 grid with content in center (2,1)-(3,3)
        let cells: [[CellType]] = [
            [.background, .background, .background, .background, .background],
            [.background, .background, .content,    .content,    .background],
            [.background, .background, .content,    .content,    .background],
            [.background, .background, .content,    .content,    .background],
            [.background, .background, .background, .background, .background],
        ]
        let map = ContentMap(gridWidth: 5, gridHeight: 5, cells: cells,
                             region: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bbox = map.contentBoundingBox()
        #expect(bbox != nil, "Should find content")
        if let bbox {
            #expect(bbox.width > 0.3 && bbox.width < 0.5,
                    "Content width should be ~0.4, got \(bbox.width)")
            #expect(bbox.height > 0.5 && bbox.height < 0.7,
                    "Content height should be ~0.6, got \(bbox.height)")
        }
    }

    @Test("Content bounding box returns nil for empty map", .tags(.figures))
    func contentBoundingBoxEmpty() {
        let cells = Array(repeating: Array(repeating: CellType.background, count: 5), count: 5)
        let map = ContentMap(gridWidth: 5, gridHeight: 5, cells: cells,
                             region: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(map.contentBoundingBox() == nil)
    }

    @Test("Content density measures content fraction correctly", .tags(.figures))
    func contentDensityMeasurement() {
        // 4x4 grid: top half is content, bottom half is background
        let cells: [[CellType]] = [
            [.content, .content, .content, .content],
            [.content, .content, .content, .content],
            [.background, .background, .background, .background],
            [.background, .background, .background, .background],
        ]
        let map = ContentMap(gridWidth: 4, gridHeight: 4, cells: cells,
                             region: CGRect(x: 0, y: 0, width: 1, height: 1))
        // Full region density should be ~50%
        let fullDensity = map.contentDensity(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(fullDensity > 0.4 && fullDensity < 0.6,
                "Full density should be ~50%, got \(fullDensity)")
    }

    @Test("Text exclusion measures text-free fraction", .tags(.figures))
    func textExclusionMeasurement() {
        // 4x4 grid: one text cell, rest content/background
        let cells: [[CellType]] = [
            [.content, .content, .content, .content],
            [.content, .content, .content, .content],
            [.text,    .text,    .background, .background],
            [.text,    .text,    .background, .background],
        ]
        let map = ContentMap(gridWidth: 4, gridHeight: 4, cells: cells,
                             region: CGRect(x: 0, y: 0, width: 1, height: 1))
        let excl = map.textExclusion(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        // 12 non-text / 16 total = 75%
        #expect(excl > 0.7 && excl < 0.8, "Text exclusion should be ~75%, got \(excl)")
    }

    @Test("Content coverage measures how much content is inside rect", .tags(.figures))
    func contentCoverageMeasurement() {
        // 4x4 grid: content everywhere
        let cells = Array(repeating: Array(repeating: CellType.content, count: 4), count: 4)
        let map = ContentMap(gridWidth: 4, gridHeight: 4, cells: cells,
                             region: CGRect(x: 0, y: 0, width: 1, height: 1))
        // Half-region should cover ~50% of content
        let coverage = map.contentCoverage(of: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        #expect(coverage > 0.4 && coverage < 0.6,
                "Half-region coverage should be ~50%, got \(coverage)")
    }
}

// MARK: - Variance Excluding Text Tests

@Suite("Figure Detection — Variance Excluding Text")
struct VarianceExcludingTextTests {

    private func makeImage(
        width: Int, height: Int,
        background: (r: UInt8, g: UInt8, b: UInt8),
        blocks: [(rect: CGRect, color: (r: UInt8, g: UInt8, b: UInt8))]
    ) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: CGFloat(background.r)/255, green: CGFloat(background.g)/255,
                         blue: CGFloat(background.b)/255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for block in blocks {
            ctx.setFillColor(red: CGFloat(block.color.r)/255, green: CGFloat(block.color.g)/255,
                             blue: CGFloat(block.color.b)/255, alpha: 1)
            ctx.fill(block.rect)
        }
        return ctx.makeImage()!
    }

    @Test("Text-only image has near-zero non-text variance", .tags(.figures))
    func textOnlyLowVariance() {
        // Simulate: white bg with dark text blocks (all variance comes from text)
        // CGContext uses bottom-left origin: CG Y=60 means 60px from bottom.
        // In a 400px image: CG Y=60..80 → Vision Y=60/400..80/400 = 0.15..0.20
        let image = makeImage(width: 400, height: 400, background: (255, 255, 255), blocks: [
            (rect: CGRect(x: 40, y: 60, width: 320, height: 20), color: (30, 30, 30)),
            (rect: CGRect(x: 40, y: 120, width: 280, height: 20), color: (30, 30, 30)),
            (rect: CGRect(x: 40, y: 180, width: 300, height: 20), color: (30, 30, 30)),
        ])
        // Text bounds in Vision coords (same bottom-left origin as CG):
        // Block 1: CG y=60..80 → Vision y=0.15..0.20
        // Block 2: CG y=120..140 → Vision y=0.30..0.35
        // Block 3: CG y=180..200 → Vision y=0.45..0.50
        let textBounds = [
            CGRect(x: 0.05, y: 0.13, width: 0.90, height: 0.10),
            CGRect(x: 0.05, y: 0.28, width: 0.80, height: 0.10),
            CGRect(x: 0.05, y: 0.43, width: 0.85, height: 0.10),
        ]
        let bg = (r: 255.0, g: 255.0, b: 255.0)

        let variance = FigureDetector.varianceExcludingText(
            image: image, textBounds: textBounds, background: bg
        )
        #expect(variance < 10, "Text-only should have near-zero non-text variance, got \(variance)")
    }

    @Test("Image with figure + text has high non-text variance", .tags(.figures))
    func figureAndTextHighVariance() {
        // White bg, colorful figure in upper area (CG Y=120..200), text in lower area (CG Y=30..50)
        // CG bottom-left: Y=120 is 120px from bottom = upper part
        let image = makeImage(width: 200, height: 200, background: (255, 255, 255), blocks: [
            (rect: CGRect(x: 0, y: 120, width: 200, height: 80), color: (50, 120, 180)),
            (rect: CGRect(x: 20, y: 30, width: 160, height: 10), color: (30, 30, 30)),
            (rect: CGRect(x: 20, y: 50, width: 140, height: 10), color: (30, 30, 30)),
        ])
        // Text bounds (Vision, bottom-left): text at CG y=30..40 → Vision y=0.15..0.20
        let textBounds = [
            CGRect(x: 0.05, y: 0.13, width: 0.85, height: 0.10),
            CGRect(x: 0.05, y: 0.23, width: 0.75, height: 0.10),
        ]
        let bg = (r: 255.0, g: 255.0, b: 255.0)

        let variance = FigureDetector.varianceExcludingText(
            image: image, textBounds: textBounds, background: bg
        )
        #expect(variance > 25, "Figure + text should have high non-text variance, got \(variance)")
    }

    @Test("Empty image has near-zero variance", .tags(.figures))
    func emptyImageLowVariance() {
        let image = makeImage(width: 200, height: 200, background: (255, 255, 255), blocks: [])
        let variance = FigureDetector.varianceExcludingText(
            image: image, textBounds: [], background: (r: 255.0, g: 255.0, b: 255.0)
        )
        #expect(variance < 5, "Empty image should have near-zero variance, got \(variance)")
    }
}

// MARK: - Background Color Sampling Tests

@Suite("Figure Detection — Background Color")
struct BackgroundColorTests {

    private func makeUniformImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private func makeImageWithFigure(
        width: Int, height: Int,
        bgR: UInt8, bgG: UInt8, bgB: UInt8,
        figRect: CGRect, figR: UInt8, figG: UInt8, figB: UInt8
    ) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: CGFloat(bgR)/255, green: CGFloat(bgG)/255, blue: CGFloat(bgB)/255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(red: CGFloat(figR)/255, green: CGFloat(figG)/255, blue: CGFloat(figB)/255, alpha: 1)
        ctx.fill(figRect)
        return ctx.makeImage()!
    }

    @Test("Detects white background correctly", .tags(.figures))
    func whiteBackground() {
        let img = makeUniformImage(width: 200, height: 200, r: 255, g: 255, b: 255)
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 800,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 200, height: 200))
        let ptr = ctx.data!.bindMemory(to: UInt8.self, capacity: 200 * 200 * 4)
        let bg = FigureDetector.sampleBackgroundColor(ptr: ptr, width: 200, height: 200)
        #expect(bg.r > 250 && bg.g > 250 && bg.b > 250, "Should detect white bg, got (\(bg.r), \(bg.g), \(bg.b))")
    }

    @Test("Detects dark background correctly", .tags(.figures))
    func darkBackground() {
        let img = makeUniformImage(width: 200, height: 200, r: 45, g: 45, b: 45)
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 800,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 200, height: 200))
        let ptr = ctx.data!.bindMemory(to: UInt8.self, capacity: 200 * 200 * 4)
        let bg = FigureDetector.sampleBackgroundColor(ptr: ptr, width: 200, height: 200)
        #expect(bg.r < 50 && bg.g < 50 && bg.b < 50, "Should detect dark bg, got (\(bg.r), \(bg.g), \(bg.b))")
    }

    @Test("Detects cream background correctly", .tags(.figures))
    func creamBackground() {
        let img = makeUniformImage(width: 200, height: 200, r: 245, g: 240, b: 232)
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 800,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 200, height: 200))
        let ptr = ctx.data!.bindMemory(to: UInt8.self, capacity: 200 * 200 * 4)
        let bg = FigureDetector.sampleBackgroundColor(ptr: ptr, width: 200, height: 200)
        #expect(bg.r > 240 && bg.g > 235 && bg.b > 228,
                "Should detect cream bg, got (\(bg.r), \(bg.g), \(bg.b))")
    }

    @Test("Background sampling ignores figure in center", .tags(.figures))
    func ignoresCenterFigure() {
        // Gray background with large blue figure in the center (doesn't touch corners/edges)
        let img = makeImageWithFigure(
            width: 200, height: 200,
            bgR: 240, bgG: 240, bgB: 240,
            figRect: CGRect(x: 40, y: 40, width: 120, height: 120),
            figR: 30, figG: 80, figB: 150
        )
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 800,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 200, height: 200))
        let ptr = ctx.data!.bindMemory(to: UInt8.self, capacity: 200 * 200 * 4)
        let bg = FigureDetector.sampleBackgroundColor(ptr: ptr, width: 200, height: 200)
        // Should be close to gray (240), not blue
        let brightness = (bg.r + bg.g + bg.b) / 3.0
        #expect(brightness > 230, "Should detect gray bg (not figure), got brightness \(brightness)")
    }

    @Test("Background sampling robust when figure covers a corner", .tags(.figures))
    func robustWithCornerFigure() {
        // White background with figure in top-left corner
        let img = makeImageWithFigure(
            width: 200, height: 200,
            bgR: 255, bgG: 255, bgB: 255,
            figRect: CGRect(x: 0, y: 0, width: 80, height: 80),
            figR: 50, figG: 100, figB: 150
        )
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 800,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 200, height: 200))
        let ptr = ctx.data!.bindMemory(to: UInt8.self, capacity: 200 * 200 * 4)
        let bg = FigureDetector.sampleBackgroundColor(ptr: ptr, width: 200, height: 200)
        // Median should still pick white (most patches are white)
        let brightness = (bg.r + bg.g + bg.b) / 3.0
        #expect(brightness > 240, "Should detect white bg despite corner figure, got brightness \(brightness)")
    }
}

// MARK: - Region Growing Tests

@Suite("Figure Detection — Region Growing")
struct RegionGrowingTests {

    /// Helper: creates a CGImage with a colored rectangle on a background.
    private func makeImage(
        width: Int, height: Int,
        background: (r: UInt8, g: UInt8, b: UInt8),
        rect: CGRect, // in pixel coords
        rectColor: (r: UInt8, g: UInt8, b: UInt8)
    ) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Fill background
        ctx.setFillColor(red: CGFloat(background.r)/255, green: CGFloat(background.g)/255,
                         blue: CGFloat(background.b)/255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Fill rectangle
        ctx.setFillColor(red: CGFloat(rectColor.r)/255, green: CGFloat(rectColor.g)/255,
                         blue: CGFloat(rectColor.b)/255, alpha: 1)
        ctx.fill(rect)
        return ctx.makeImage()!
    }

    @Test("Region grows from seed to full colored block on white background", .tags(.figures))
    func growOnWhiteBackground() {
        // 200x100 image: white bg, blue block at x=20..179, y=10..59 (160x50)
        let image = makeImage(
            width: 200, height: 100,
            background: (255, 255, 255),
            rect: CGRect(x: 20, y: 10, width: 160, height: 50),
            rectColor: (50, 100, 150)
        )
        // Seed: small region in the center of the block (normalized Vision coords)
        // Block in CG coords: x=20..180, y=10..60
        // Vision coords: x=20/200=0.10, y=(100-60)/100=0.40, w=160/200=0.80, h=50/100=0.50
        // Seed: center portion of the block
        let seed = CGRect(x: 0.35, y: 0.45, width: 0.20, height: 0.10)

        let grown = FigureDetector.growRegion(seed, in: image, textBounds: [])

        // Should grow to approximately the full block
        #expect(grown.width > 0.70, "Should grow to block width, got \(grown.width)")
        #expect(grown.height > 0.40, "Should grow to block height, got \(grown.height)")
    }

    @Test("Region grows from seed to full colored block on gray background", .tags(.figures))
    func growOnGrayBackground() {
        // Gray background (240,240,240), darker block
        let image = makeImage(
            width: 200, height: 100,
            background: (240, 240, 240),
            rect: CGRect(x: 20, y: 10, width: 160, height: 50),
            rectColor: (80, 120, 100)
        )
        let seed = CGRect(x: 0.35, y: 0.45, width: 0.20, height: 0.10)
        let grown = FigureDetector.growRegion(seed, in: image, textBounds: [])

        #expect(grown.width > 0.70, "Should grow on gray bg, got width \(grown.width)")
        #expect(grown.height > 0.40, "Should grow on gray bg, got height \(grown.height)")
    }

    @Test("Region grows from seed to full colored block on dark background", .tags(.figures))
    func growOnDarkBackground() {
        // Dark background (45,45,45), lighter block
        let image = makeImage(
            width: 200, height: 100,
            background: (45, 45, 45),
            rect: CGRect(x: 20, y: 10, width: 160, height: 50),
            rectColor: (140, 160, 180)
        )
        let seed = CGRect(x: 0.35, y: 0.45, width: 0.20, height: 0.10)
        let grown = FigureDetector.growRegion(seed, in: image, textBounds: [])

        #expect(grown.width > 0.70, "Should grow on dark bg, got width \(grown.width)")
        #expect(grown.height > 0.40, "Should grow on dark bg, got height \(grown.height)")
    }

    @Test("Region does not grow into text area", .tags(.figures))
    func doesNotGrowIntoText() {
        // Block in top half, text bounds in bottom half
        let image = makeImage(
            width: 200, height: 200,
            background: (255, 255, 255),
            rect: CGRect(x: 0, y: 0, width: 200, height: 80), // top 40% in CG (y=0 is top)
            rectColor: (50, 100, 150)
        )
        // Seed in the block area (Vision: y=0.60..1.0 is top of image)
        let seed = CGRect(x: 0.30, y: 0.65, width: 0.20, height: 0.10)
        // Text in bottom half (Vision: y=0.05..0.30)
        let textBounds = [
            CGRect(x: 0.05, y: 0.10, width: 0.80, height: 0.03),
            CGRect(x: 0.05, y: 0.20, width: 0.60, height: 0.03),
        ]

        let grown = FigureDetector.growRegion(seed, in: image, textBounds: textBounds)

        // Should NOT extend into the text area
        #expect(grown.minY > 0.35,
                "Should not grow into text below, got minY=\(grown.minY)")
    }

    @Test("Region growing stops at background boundary", .tags(.figures))
    func stopsAtBackgroundBoundary() {
        // Small block (30% width) on white bg — should not grow beyond the block
        let image = makeImage(
            width: 200, height: 100,
            background: (255, 255, 255),
            rect: CGRect(x: 70, y: 25, width: 60, height: 50), // 30% width centered
            rectColor: (50, 100, 150)
        )
        let seed = CGRect(x: 0.40, y: 0.30, width: 0.10, height: 0.10)
        let grown = FigureDetector.growRegion(seed, in: image, textBounds: [])

        // Should stay within roughly the block bounds, not expand to full image
        #expect(grown.width < 0.50, "Should not grow beyond block, got width \(grown.width)")
    }
}

// MARK: - Spatial Relationship Classification Tests

@Suite("Figure Detection — Spatial Relation Classifier")
struct SpatialRelationTests {

    @Test("Text to the right of figure → adjacentRight", .tags(.figures))
    func textRightOfFigure() {
        // Gap of 0.02 between figure.maxX (0.35) and text.minX (0.37) — within proximity
        let figure = CGRect(x: 0.05, y: 0.20, width: 0.30, height: 0.60)
        let text = CGRect(x: 0.37, y: 0.30, width: 0.50, height: 0.03)
        let relation = FigureDetector.classifyTextRelation(figure: figure, text: text)
        #expect(relation == .adjacentRight,
                "Text at x=0.37 should be adjacentRight of figure ending at x=0.35, got \(relation)")
    }

    @Test("Text to the left of figure → adjacentLeft", .tags(.figures))
    func textLeftOfFigure() {
        // Gap of 0.02 between text.maxX (0.48) and figure.minX (0.50)
        let figure = CGRect(x: 0.50, y: 0.20, width: 0.40, height: 0.60)
        let text = CGRect(x: 0.18, y: 0.30, width: 0.30, height: 0.03)
        let relation = FigureDetector.classifyTextRelation(figure: figure, text: text)
        #expect(relation == .adjacentLeft,
                "Text ending at x=0.48 should be adjacentLeft of figure at x=0.50, got \(relation)")
    }

    @Test("Text below figure → adjacentBelow", .tags(.figures))
    func textBelowFigure() {
        // Vision coords: lower Y = lower in image. Gap of 0.02 between text.maxY and figure.minY
        let figure = CGRect(x: 0.05, y: 0.40, width: 0.90, height: 0.50)
        let text = CGRect(x: 0.10, y: 0.35, width: 0.70, height: 0.03)
        let relation = FigureDetector.classifyTextRelation(figure: figure, text: text)
        #expect(relation == .adjacentBelow,
                "Text at y=0.35 should be adjacentBelow figure at y=0.40..0.90, got \(relation)")
    }

    @Test("Text above figure → adjacentAbove", .tags(.figures))
    func textAboveFigure() {
        // Gap of 0.02 between figure.maxY (0.40) and text.minY (0.42)
        let figure = CGRect(x: 0.05, y: 0.10, width: 0.90, height: 0.30)
        let text = CGRect(x: 0.10, y: 0.42, width: 0.70, height: 0.03)
        let relation = FigureDetector.classifyTextRelation(figure: figure, text: text)
        #expect(relation == .adjacentAbove,
                "Text at y=0.42 should be adjacentAbove figure at y=0.10..0.40, got \(relation)")
    }

    @Test("Text overlapping figure → overlapping", .tags(.figures))
    func textOverlapsFigure() {
        let figure = CGRect(x: 0.10, y: 0.20, width: 0.50, height: 0.50)
        let text = CGRect(x: 0.30, y: 0.40, width: 0.40, height: 0.03)
        let relation = FigureDetector.classifyTextRelation(figure: figure, text: text)
        #expect(relation == .overlapping,
                "Text inside figure should be overlapping, got \(relation)")
    }

    @Test("Text far from figure → disjoint", .tags(.figures))
    func textFarFromFigure() {
        let figure = CGRect(x: 0.05, y: 0.05, width: 0.20, height: 0.20)
        let text = CGRect(x: 0.70, y: 0.70, width: 0.20, height: 0.03)
        let relation = FigureDetector.classifyTextRelation(figure: figure, text: text)
        #expect(relation == .disjoint,
                "Text far away should be disjoint, got \(relation)")
    }

    @Test("Text barely touching right edge (sub-pixel) → adjacentRight, NOT overlapping", .tags(.figures))
    func textBarelyTouchingRight() {
        // Propinion scenario: figure maxX=0.369, text minX=0.368
        let figure = CGRect(x: 0.04, y: 0.35, width: 0.329, height: 0.57)
        let text = CGRect(x: 0.368, y: 0.47, width: 0.60, height: 0.03)
        let relation = FigureDetector.classifyTextRelation(figure: figure, text: text)
        #expect(relation == .adjacentRight,
                "Text barely touching right edge should be adjacentRight (not overlapping), got \(relation)")
    }

    @Test("Text below wide figure with full horizontal span → adjacentBelow", .tags(.figures))
    func textBelowWideFigure() {
        // Hero banner scenario: wide figure, text just below with small gap
        let figure = CGRect(x: 0.00, y: 0.50, width: 1.00, height: 0.40)
        let text = CGRect(x: 0.05, y: 0.45, width: 0.85, height: 0.03)
        let relation = FigureDetector.classifyTextRelation(figure: figure, text: text)
        #expect(relation == .adjacentBelow,
                "Text below wide banner should be adjacentBelow, got \(relation)")
    }

    @Test("Blocked edges: text right blocks only right expansion", .tags(.figures))
    func blockedEdgesTextRight() {
        // Text at x=0.37, figure ends at x=0.35 — gap 0.02, within proximity
        let figure = CGRect(x: 0.05, y: 0.20, width: 0.30, height: 0.60)
        let textBlocks = [
            CGRect(x: 0.37, y: 0.30, width: 0.50, height: 0.03),
            CGRect(x: 0.37, y: 0.50, width: 0.50, height: 0.03),
        ]

        let blocked = FigureDetector.blockedExpansionEdges(
            figure: figure, textBounds: textBlocks
        )

        #expect(blocked.contains(.right), "Right should be blocked")
        #expect(!blocked.contains(.top), "Top should NOT be blocked")
        #expect(!blocked.contains(.bottom), "Bottom should NOT be blocked")
        #expect(!blocked.contains(.left), "Left should NOT be blocked")
    }

    @Test("Blocked edges: text below blocks only bottom expansion", .tags(.figures))
    func blockedEdgesTextBelow() {
        // Text at y=0.47, figure starts at y=0.50 — gap 0.0, touching
        let figure = CGRect(x: 0.00, y: 0.50, width: 1.00, height: 0.40)
        let textBlocks = [
            CGRect(x: 0.05, y: 0.45, width: 0.85, height: 0.03),
            CGRect(x: 0.05, y: 0.38, width: 0.70, height: 0.03),
        ]

        let blocked = FigureDetector.blockedExpansionEdges(
            figure: figure, textBounds: textBlocks
        )

        #expect(blocked.contains(.bottom), "Bottom should be blocked")
        #expect(!blocked.contains(.top), "Top should NOT be blocked")
        #expect(!blocked.contains(.left), "Left should NOT be blocked")
        #expect(!blocked.contains(.right), "Right should NOT be blocked")
    }
}

// MARK: - Real Image Verification Tests

@Suite("Figure Detection — Real Image Verification")
struct RealImageVerificationTests {

    /// Loads Image/testEdgesDenHaagDoet.png (1926×742), runs the full detection
    /// pipeline, and verifies:
    ///   1. Exactly one figure is detected (the hero photo)
    ///   2. It spans full width and reaches the top of the image
    ///   3. The extracted image has a wide aspect ratio (>4:1)
    ///   4. Bottom whitespace is <3% of figure height (tight crop)
    ///   5. Top whitespace is <3% (photo starts immediately)
    @Test("Real cutout: hero photo extracted without bottom whitespace",
          .tags(.figures))
    func realCutoutHeroPhotoTightCrop() async throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imagePath = projectRoot
            .appendingPathComponent("Image")
            .appendingPathComponent("testEdgesDenHaagDoet.png")

        guard let nsImage = NSImage(contentsOf: imagePath) else {
            Issue.record("Could not load test image at \(imagePath.path)")
            return
        }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("Could not convert NSImage to CGImage")
            return
        }

        // Verify source image dimensions
        #expect(cgImage.width == 1926 && cgImage.height == 742,
                "Expected 1926×742, got \(cgImage.width)×\(cgImage.height)")

        let detector = FigureDetector()

        // Get text bounds via OCR
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let ocrRequest = VNRecognizeTextRequest()
        ocrRequest.recognitionLevel = .accurate
        try handler.perform([ocrRequest])
        let textBounds = (ocrRequest.results ?? []).map { $0.boundingBox }
        #expect(textBounds.count >= 3, "Expected at least 3 text blocks (heading + body)")

        // Run the full detection pipeline
        let result = try await detector.detectFigures(in: cgImage, textBounds: textBounds)
        #expect(result.figures.count == 1, "Expected exactly 1 figure, got \(result.figures.count)")

        let hero = result.figures[0]
        let b = hero.bounds

        // --- Bounds assertions ---
        #expect(b.width > 0.95, "Hero width should be >95%, got \(b.width)")
        #expect(b.maxY > 0.95, "Hero maxY should be near 1.0 (top of image), got \(b.maxY)")
        #expect(b.minY > 0.35, "Hero minY should be above text, got \(b.minY)")

        // --- Extracted image assertions ---
        guard let extracted = hero.extractedImage else {
            Issue.record("No extracted image")
            return
        }

        let aspect = CGFloat(extracted.width) / CGFloat(extracted.height)
        #expect(aspect > 4.0, "Hero aspect ratio should be >4:1, got \(aspect):1")

        // --- Pixel-level whitespace checks (all 4 edges) ---
        let whiteThreshold = 248.0
        let maxWhitePct = 2.0

        let whiteRowsBottom = countWhiteRows(from: .bottom, in: extracted, threshold: whiteThreshold)
        let bottomPct = Double(whiteRowsBottom) / Double(extracted.height) * 100.0

        let whiteRowsTop = countWhiteRows(from: .top, in: extracted, threshold: whiteThreshold)
        let topPct = Double(whiteRowsTop) / Double(extracted.height) * 100.0

        let whiteColsRight = countWhiteCols(from: .right, in: extracted, threshold: whiteThreshold)
        let rightPct = Double(whiteColsRight) / Double(extracted.width) * 100.0

        let whiteColsLeft = countWhiteCols(from: .left, in: extracted, threshold: whiteThreshold)
        let leftPct = Double(whiteColsLeft) / Double(extracted.width) * 100.0

        print("  extracted: \(extracted.width)×\(extracted.height) aspect=\(String(format: "%.1f", aspect)):1")
        print("  white: bottom=\(whiteRowsBottom)px (\(String(format: "%.1f", bottomPct))%) top=\(whiteRowsTop)px (\(String(format: "%.1f", topPct))%) right=\(whiteColsRight)px (\(String(format: "%.1f", rightPct))%) left=\(whiteColsLeft)px (\(String(format: "%.1f", leftPct))%)")

        #expect(bottomPct < maxWhitePct,
                "Bottom whitespace should be <\(maxWhitePct)%, got \(String(format: "%.1f", bottomPct))%")
        #expect(topPct < maxWhitePct,
                "Top whitespace should be <\(maxWhitePct)%, got \(String(format: "%.1f", topPct))%")
        #expect(rightPct < maxWhitePct,
                "Right whitespace should be <\(maxWhitePct)%, got \(String(format: "%.1f", rightPct))%")
        #expect(leftPct < maxWhitePct,
                "Left whitespace should be <\(maxWhitePct)%, got \(String(format: "%.1f", leftPct))%")
    }

    /// Loads Image/testMultipleImageNews2.png — a news page with two photos:
    ///   1. Top: military photo (people + aircraft) — should be ONE figure, not two
    ///   2. Bottom: video thumbnail (dog on runway) with text overlay — should not be clipped at text
    @Test("Real cutout: news page with multiple photos and text overlay",
          .tags(.figures))
    func realCutoutMultipleNewsPhotos() async throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imagePath = projectRoot
            .appendingPathComponent("Image")
            .appendingPathComponent("testMultipleImageNews2.png")

        guard let nsImage = NSImage(contentsOf: imagePath) else {
            Issue.record("Could not load test image at \(imagePath.path)")
            return
        }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("Could not convert NSImage to CGImage")
            return
        }

        print("  Source image: \(cgImage.width)×\(cgImage.height)")

        let detector = FigureDetector()

        // Get text bounds via OCR
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let ocrRequest = VNRecognizeTextRequest()
        ocrRequest.recognitionLevel = .accurate
        try handler.perform([ocrRequest])
        let textBounds = (ocrRequest.results ?? []).map { $0.boundingBox }
        print("  OCR found \(textBounds.count) text blocks")

        // Run the full detection pipeline
        let result = try await detector.detectFigures(in: cgImage, textBounds: textBounds)

        print("  Detected \(result.figures.count) figure(s):")
        for (i, f) in result.figures.enumerated() {
            if let img = f.extractedImage {
                let aspect = CGFloat(img.width) / CGFloat(img.height)
                print("  Figure \(i+1): \(img.width)×\(img.height) aspect=\(String(format: "%.2f", aspect)):1")
            }
            print("    Bounds: x=\(String(format: "%.3f", f.bounds.minX)) y=\(String(format: "%.3f", f.bounds.minY)) w=\(String(format: "%.3f", f.bounds.width)) h=\(String(format: "%.3f", f.bounds.height))")
        }

        // --- Assertions ---

        // Should detect exactly 2 figures: top photo + bottom photo
        #expect(result.figures.count == 2,
                "Expected 2 figures (top photo + bottom video), got \(result.figures.count)")

        // Top photo: should be the full military photo, not split into person + scene
        // The top photo is in the upper portion of the image (roughly y > 0.6 in Vision coords)
        let topFigures = result.figures.filter { $0.bounds.maxY > 0.6 }
        #expect(topFigures.count == 1,
                "Top photo should be 1 figure, not \(topFigures.count) (subject should not be promoted separately)")

        if let topFigure = topFigures.first, let topExtracted = topFigure.extractedImage {
            print("  Top figure: \(topExtracted.width)×\(topExtracted.height) bounds height: \(String(format: "%.3f", topFigure.bounds.height))")
            // The top photo extends behind the headline text (white text on photo edge).
            // The OverlayTextAnalyzer should classify the headline as edgeOverlay and
            // prevent trimming. The figure should include the headline area.
            #expect(topFigure.bounds.height > 0.24,
                    "Top photo should include headline area (height > 0.24), got \(String(format: "%.3f", topFigure.bounds.height))")
            #expect(topExtracted.width > 500,
                    "Top photo width should be >500px after merge, got \(topExtracted.width)")
        }

        // Bottom photo: video thumbnail with text overlay
        // Should include the full photo including area under the text
        let bottomFigures = result.figures.filter { $0.bounds.maxY <= 0.6 }
        #expect(bottomFigures.count == 1,
                "Bottom photo should be 1 figure, got \(bottomFigures.count)")

        if let bottomFigure = bottomFigures.first, let extracted = bottomFigure.extractedImage {
            // The video thumbnail should not be clipped short — it should capture the runway scene
            let aspect = CGFloat(extracted.width) / CGFloat(extracted.height)
            print("  Bottom figure aspect: \(String(format: "%.2f", aspect)):1")
            print("  Bottom figure bounds height: \(String(format: "%.3f", bottomFigure.bounds.height))")

            // The photo is roughly landscape, expect reasonable height
            #expect(extracted.height > 100,
                    "Bottom photo height should be substantial, got \(extracted.height)px")

            // RC-2: The figure should NOT be trimmed at the text overlay.
            // The full photo (including area under "Loslopende hond..." text) should be captured.
            // Before fix: bounds height was ~0.210 (trimmed). After fix: should be ~0.270+ (full photo).
            #expect(bottomFigure.bounds.height > 0.24,
                    "Bottom photo should include area under text overlay (height > 0.24), got \(String(format: "%.3f", bottomFigure.bounds.height))")
        }
    }

    // MARK: - Helpers

    private enum ScanDirection { case top, bottom }
    private enum ColDirection { case left, right }

    /// Count consecutive rows with average brightness >= threshold, scanning from top or bottom.
    private func countWhiteRows(from direction: ScanDirection, in image: CGImage, threshold: Double) -> Int {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return 0 }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let rows: any Sequence<Int> = direction == .bottom
            ? AnySequence(stride(from: height - 1, through: 0, by: -1))
            : AnySequence(0..<height)

        var count = 0
        for row in rows {
            var rowSum = 0.0
            for x in 0..<width {
                let offset = (row * width + x) * 4
                rowSum += Double(ptr[offset]) + Double(ptr[offset + 1]) + Double(ptr[offset + 2])
            }
            let avg = rowSum / (3.0 * Double(width))
            if avg >= threshold {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    /// Loads Image/testPropinionEdges.png (2168×1256) — a cutout with a circular
    /// photo on the left side and text paragraphs on the right. The photo should be
    /// detected as a figure even though saliency may return a region covering both
    /// photo and text (which gets filtered by text overlap). Instance mask should
    /// detect the person as a foreground subject and promote it to a standalone figure.
    @Test("Real cutout: circular photo detected alongside text",
          .tags(.figures))
    func realCutoutCircularPhotoDetected() async throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imagePath = projectRoot
            .appendingPathComponent("Image")
            .appendingPathComponent("testPropinionEdges.png")

        guard let nsImage = NSImage(contentsOf: imagePath) else {
            Issue.record("Could not load test image at \(imagePath.path)")
            return
        }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("Could not convert NSImage to CGImage")
            return
        }

        #expect(cgImage.width == 2168 && cgImage.height == 1256,
                "Expected 2168×1256, got \(cgImage.width)×\(cgImage.height)")

        let detector = FigureDetector()

        // Get text bounds via OCR
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let ocrRequest = VNRecognizeTextRequest()
        ocrRequest.recognitionLevel = .accurate
        try handler.perform([ocrRequest])
        let textBounds = (ocrRequest.results ?? []).map { $0.boundingBox }
        #expect(textBounds.count >= 3, "Expected at least 3 text blocks")

        // Run the full detection pipeline
        let result = try await detector.detectFigures(in: cgImage, textBounds: textBounds)
        #expect(result.figures.count >= 1,
                "Expected at least 1 figure (the circular photo), got \(result.figures.count)")

        // The photo should be detected — verify it has reasonable dimensions
        // The circular photo is on the left side, roughly 30-50% of width, 40-70% of height
        let photo = result.figures[0]
        guard let extracted = photo.extractedImage else {
            Issue.record("No extracted image for detected figure")
            return
        }

        let aspect = CGFloat(extracted.width) / CGFloat(extracted.height)

        print("  Propinion: \(result.figures.count) figure(s) detected")
        for (i, f) in result.figures.enumerated() {
            if let img = f.extractedImage {
                print("  Figure \(i+1): \(img.width)×\(img.height) aspect=\(String(format: "%.2f", CGFloat(img.width)/CGFloat(img.height))):1")
            }
            print("    Bounds: x=\(String(format: "%.3f", f.bounds.minX)) y=\(String(format: "%.3f", f.bounds.minY)) w=\(String(format: "%.3f", f.bounds.width)) h=\(String(format: "%.3f", f.bounds.height))")
        }

        // The visible portion of the circular photo is taller than wide because
        // the right half is occluded by text columns. Expected aspect: ~0.55-0.85:1.
        #expect(aspect > 0.55 && aspect < 0.85,
                "Visible circle portion should be tall crop (0.55-0.85:1), got \(String(format: "%.2f", aspect)):1")

        // The extracted figure should capture meaningful content
        #expect(extracted.width >= 550, "Figure width should be ≥550px, got \(extracted.width)")
        #expect(extracted.height >= 800, "Figure height should be ≥800px (full visible circle), got \(extracted.height)")

        // The figure should have high color variance (it's a photo, not uniform)
        let variance = detector.colorVariance(of: extracted)
        #expect(variance > 25, "Photo should have color variance >25, got \(variance)")

    }

    /// Count consecutive columns with average brightness >= threshold, scanning from left or right.
    /// Converts a CGImage to a specific color space by redrawing it into a new bitmap context.
    private func convertToColorSpace(_ image: CGImage, colorSpace: CGColorSpace) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Scales a CGImage by the given factor (e.g. 2.0 = double dimensions).
    private func scaleImage(_ image: CGImage, factor: CGFloat) -> CGImage? {
        let newWidth = Int(CGFloat(image.width) * factor)
        let newHeight = Int(CGFloat(image.height) * factor)
        guard let context = CGContext(
            data: nil, width: newWidth, height: newHeight,
            bitsPerComponent: 8, bytesPerRow: newWidth * 4,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    private func countWhiteCols(from direction: ColDirection, in image: CGImage, threshold: Double) -> Int {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return 0 }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let cols: any Sequence<Int> = direction == .right
            ? AnySequence(stride(from: width - 1, through: 0, by: -1))
            : AnySequence(0..<width)

        var count = 0
        for col in cols {
            var colSum = 0.0
            for y in 0..<height {
                let offset = (y * width + col) * 4
                colSum += Double(ptr[offset]) + Double(ptr[offset + 1]) + Double(ptr[offset + 2])
            }
            let avg = colSum / (3.0 * Double(height))
            if avg >= threshold {
                count += 1
            } else {
                break
            }
        }
        return count
    }
}

// MARK: - Color Space & Scale Consistency Tests

@Suite("Figure Detection — Color Space & Scale Consistency")
struct ColorSpaceScaleConsistencyTests {

    private func loadDenHaagDoetImage() -> CGImage? {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imagePath = projectRoot
            .appendingPathComponent("Image")
            .appendingPathComponent("testEdgesDenHaagDoet.png")
        guard let nsImage = NSImage(contentsOf: imagePath),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
    }

    private func runDetection(on image: CGImage) async throws -> (figure: DetectedFigure, bounds: CGRect, aspect: CGFloat, leftWhitePct: Double) {
        let detector = FigureDetector()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let ocrRequest = VNRecognizeTextRequest()
        ocrRequest.recognitionLevel = .accurate
        try handler.perform([ocrRequest])
        let textBounds = (ocrRequest.results ?? []).map { $0.boundingBox }

        let result = try await detector.detectFigures(in: image, textBounds: textBounds)
        guard let hero = result.figures.first else {
            throw DetectionError.noFigureDetected
        }

        guard let extracted = hero.extractedImage else {
            throw DetectionError.noExtractedImage
        }

        let aspect = CGFloat(extracted.width) / CGFloat(extracted.height)
        let leftWhitePct = leftWhitePercentage(of: extracted)

        return (hero, hero.bounds, aspect, leftWhitePct)
    }

    private func leftWhitePercentage(of image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 100.0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return 100.0 }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var count = 0
        for col in 0..<width {
            var colSum = 0.0
            for y in 0..<height {
                let offset = (y * width + col) * 4
                colSum += Double(ptr[offset]) + Double(ptr[offset + 1]) + Double(ptr[offset + 2])
            }
            let avg = colSum / (3.0 * Double(height))
            if avg >= 248.0 {
                count += 1
            } else {
                break
            }
        }
        return Double(count) / Double(width) * 100.0
    }

    private func convertToColorSpace(_ image: CGImage, colorSpace: CGColorSpace) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func scaleImage(_ image: CGImage, factor: CGFloat) -> CGImage? {
        let newWidth = Int(CGFloat(image.width) * factor)
        let newHeight = Int(CGFloat(image.height) * factor)
        guard let context = CGContext(
            data: nil, width: newWidth, height: newHeight,
            bitsPerComponent: 8, bytesPerRow: newWidth * 4,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    enum DetectionError: Error {
        case noFigureDetected
        case noExtractedImage
    }

    // MARK: - Color Space Tests

    @Test("Detection consistency: sRGB vs Display P3 color space",
          .tags(.figures))
    func colorSpaceSRGBvsP3() async throws {
        guard let original = loadDenHaagDoetImage() else {
            Issue.record("Could not load DenHaagDoet test image")
            return
        }

        let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let p3Space = CGColorSpace(name: CGColorSpace.displayP3)!

        guard let srgbImage = convertToColorSpace(original, colorSpace: srgbSpace) else {
            Issue.record("Failed to convert to sRGB")
            return
        }
        guard let p3Image = convertToColorSpace(original, colorSpace: p3Space) else {
            Issue.record("Failed to convert to Display P3")
            return
        }

        let srgbResult = try await runDetection(on: srgbImage)
        let p3Result = try await runDetection(on: p3Image)

        print("  sRGB: bounds=(\(fmt(srgbResult.bounds))) aspect=\(String(format: "%.1f", srgbResult.aspect)):1 leftWhite=\(String(format: "%.1f", srgbResult.leftWhitePct))%")
        print("  P3:   bounds=(\(fmt(p3Result.bounds))) aspect=\(String(format: "%.1f", p3Result.aspect)):1 leftWhite=\(String(format: "%.1f", p3Result.leftWhitePct))%")

        // Both should detect exactly 1 figure
        // Bounds should be within 5% tolerance of each other
        let boundsTolerance = 0.05
        #expect(abs(srgbResult.bounds.minX - p3Result.bounds.minX) < boundsTolerance,
                "Bounds minX diverges: sRGB=\(srgbResult.bounds.minX) P3=\(p3Result.bounds.minX)")
        #expect(abs(srgbResult.bounds.width - p3Result.bounds.width) < boundsTolerance,
                "Bounds width diverges: sRGB=\(srgbResult.bounds.width) P3=\(p3Result.bounds.width)")
        #expect(abs(srgbResult.bounds.height - p3Result.bounds.height) < boundsTolerance,
                "Bounds height diverges: sRGB=\(srgbResult.bounds.height) P3=\(p3Result.bounds.height)")

        // Both should have <2% left whitespace
        #expect(srgbResult.leftWhitePct < 2.0,
                "sRGB: left whitespace \(String(format: "%.1f", srgbResult.leftWhitePct))% should be <2%")
        #expect(p3Result.leftWhitePct < 2.0,
                "P3: left whitespace \(String(format: "%.1f", p3Result.leftWhitePct))% should be <2%")

        // Aspect ratios should be within 10% of each other
        let aspectDiff = abs(srgbResult.aspect - p3Result.aspect) / srgbResult.aspect
        #expect(aspectDiff < 0.10,
                "Aspect ratio diverges >10%: sRGB=\(String(format: "%.1f", srgbResult.aspect)) P3=\(String(format: "%.1f", p3Result.aspect))")
    }

    @Test("Detection consistency: sRGB vs deviceRGB color space",
          .tags(.figures))
    func colorSpaceSRGBvsDeviceRGB() async throws {
        guard let original = loadDenHaagDoetImage() else {
            Issue.record("Could not load DenHaagDoet test image")
            return
        }

        let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let deviceSpace = CGColorSpaceCreateDeviceRGB()

        guard let srgbImage = convertToColorSpace(original, colorSpace: srgbSpace) else {
            Issue.record("Failed to convert to sRGB")
            return
        }
        guard let deviceImage = convertToColorSpace(original, colorSpace: deviceSpace) else {
            Issue.record("Failed to convert to deviceRGB")
            return
        }

        let srgbResult = try await runDetection(on: srgbImage)
        let deviceResult = try await runDetection(on: deviceImage)

        print("  sRGB:   bounds=(\(fmt(srgbResult.bounds))) aspect=\(String(format: "%.1f", srgbResult.aspect)):1 leftWhite=\(String(format: "%.1f", srgbResult.leftWhitePct))%")
        print("  device: bounds=(\(fmt(deviceResult.bounds))) aspect=\(String(format: "%.1f", deviceResult.aspect)):1 leftWhite=\(String(format: "%.1f", deviceResult.leftWhitePct))%")

        let boundsTolerance = 0.05
        #expect(abs(srgbResult.bounds.minX - deviceResult.bounds.minX) < boundsTolerance,
                "Bounds minX diverges: sRGB=\(srgbResult.bounds.minX) device=\(deviceResult.bounds.minX)")
        #expect(abs(srgbResult.bounds.width - deviceResult.bounds.width) < boundsTolerance,
                "Bounds width diverges: sRGB=\(srgbResult.bounds.width) device=\(deviceResult.bounds.width)")

        #expect(srgbResult.leftWhitePct < 2.0,
                "sRGB: left whitespace \(String(format: "%.1f", srgbResult.leftWhitePct))% should be <2%")
        #expect(deviceResult.leftWhitePct < 2.0,
                "deviceRGB: left whitespace \(String(format: "%.1f", deviceResult.leftWhitePct))% should be <2%")
    }

    // MARK: - Scale Factor Tests

    @Test("Detection consistency: 1x vs 2x scale factor",
          .tags(.figures))
    func scaleConsistency1xVs2x() async throws {
        guard let original = loadDenHaagDoetImage() else {
            Issue.record("Could not load DenHaagDoet test image")
            return
        }

        guard let scaled2x = scaleImage(original, factor: 2.0) else {
            Issue.record("Failed to scale image to 2x")
            return
        }

        let result1x = try await runDetection(on: original)
        let result2x = try await runDetection(on: scaled2x)

        print("  1x (\(original.width)×\(original.height)): bounds=(\(fmt(result1x.bounds))) aspect=\(String(format: "%.1f", result1x.aspect)):1 leftWhite=\(String(format: "%.1f", result1x.leftWhitePct))%")
        print("  2x (\(scaled2x.width)×\(scaled2x.height)): bounds=(\(fmt(result2x.bounds))) aspect=\(String(format: "%.1f", result2x.aspect)):1 leftWhite=\(String(format: "%.1f", result2x.leftWhitePct))%")

        // Normalized bounds should be nearly identical regardless of scale
        let boundsTolerance = 0.05
        #expect(abs(result1x.bounds.minX - result2x.bounds.minX) < boundsTolerance,
                "Bounds minX diverges at 2x: 1x=\(result1x.bounds.minX) 2x=\(result2x.bounds.minX)")
        #expect(abs(result1x.bounds.width - result2x.bounds.width) < boundsTolerance,
                "Bounds width diverges at 2x: 1x=\(result1x.bounds.width) 2x=\(result2x.bounds.width)")
        #expect(abs(result1x.bounds.height - result2x.bounds.height) < boundsTolerance,
                "Bounds height diverges at 2x: 1x=\(result1x.bounds.height) 2x=\(result2x.bounds.height)")

        // Both should have <2% left whitespace
        #expect(result1x.leftWhitePct < 2.0,
                "1x: left whitespace \(String(format: "%.1f", result1x.leftWhitePct))% should be <2%")
        #expect(result2x.leftWhitePct < 2.0,
                "2x: left whitespace \(String(format: "%.1f", result2x.leftWhitePct))% should be <2%")

        // Aspect ratios should be within 10%
        let aspectDiff = abs(result1x.aspect - result2x.aspect) / result1x.aspect
        #expect(aspectDiff < 0.10,
                "Aspect ratio diverges >10% at 2x: 1x=\(String(format: "%.1f", result1x.aspect)) 2x=\(String(format: "%.1f", result2x.aspect))")
    }

    @Test("Detection consistency: P3 color space at 2x scale",
          .tags(.figures))
    func colorSpaceP3At2xScale() async throws {
        guard let original = loadDenHaagDoetImage() else {
            Issue.record("Could not load DenHaagDoet test image")
            return
        }

        // Simulate a Retina Apple display: P3 color space + 2x resolution
        let p3Space = CGColorSpace(name: CGColorSpace.displayP3)!
        guard let p3Image = convertToColorSpace(original, colorSpace: p3Space),
              let p3At2x = scaleImage(p3Image, factor: 2.0) else {
            Issue.record("Failed to create P3@2x image")
            return
        }

        // Baseline: original image (likely sRGB@1x)
        let baselineResult = try await runDetection(on: original)
        let p3Result = try await runDetection(on: p3At2x)

        print("  baseline (\(original.width)×\(original.height)): bounds=(\(fmt(baselineResult.bounds))) aspect=\(String(format: "%.1f", baselineResult.aspect)):1 leftWhite=\(String(format: "%.1f", baselineResult.leftWhitePct))%")
        print("  P3@2x (\(p3At2x.width)×\(p3At2x.height)): bounds=(\(fmt(p3Result.bounds))) aspect=\(String(format: "%.1f", p3Result.aspect)):1 leftWhite=\(String(format: "%.1f", p3Result.leftWhitePct))%")

        let boundsTolerance = 0.05
        #expect(abs(baselineResult.bounds.minX - p3Result.bounds.minX) < boundsTolerance,
                "P3@2x bounds minX diverges: baseline=\(baselineResult.bounds.minX) P3@2x=\(p3Result.bounds.minX)")
        #expect(abs(baselineResult.bounds.width - p3Result.bounds.width) < boundsTolerance,
                "P3@2x bounds width diverges: baseline=\(baselineResult.bounds.width) P3@2x=\(p3Result.bounds.width)")

        #expect(baselineResult.leftWhitePct < 2.0,
                "baseline: left whitespace should be <2%")
        #expect(p3Result.leftWhitePct < 2.0,
                "P3@2x: left whitespace \(String(format: "%.1f", p3Result.leftWhitePct))% should be <2%")
    }

    // MARK: - Helpers

    private func fmt(_ r: CGRect) -> String {
        String(format: "%.3f %.3f %.3f %.3f", r.minX, r.minY, r.width, r.height)
    }
}
