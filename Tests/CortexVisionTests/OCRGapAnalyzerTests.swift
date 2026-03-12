import Testing
import CoreGraphics
@testable import CortexVision

@Suite("OCR Gap Analysis — Vertical gap detection between text bands")
struct OCRGapAnalyzerTests {

    // MARK: - Edge Cases

    @Test("No text blocks returns single full-image gap", .tags(.core, .figures))
    func noTextReturnsFullImage() {
        let gaps = OCRGapAnalyzer.findGaps(in: [])
        #expect(gaps.count == 1)
        #expect(gaps[0].bounds == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test("Single text block covering entire image returns no gaps", .tags(.core, .figures))
    func fullCoverageNoGaps() {
        let text = [CGRect(x: 0, y: 0, width: 1, height: 1)]
        let gaps = OCRGapAnalyzer.findGaps(in: text)
        #expect(gaps.isEmpty)
    }

    // MARK: - Basic Gap Detection

    @Test("Text at top creates gap below", .tags(.core, .figures))
    func textAtTopGapBelow() {
        // Vision coords: high Y = top of image
        let text = [CGRect(x: 0, y: 0.8, width: 1, height: 0.2)]
        let gaps = OCRGapAnalyzer.findGaps(in: text)
        #expect(gaps.count == 1)
        #expect(gaps[0].bounds.minY == 0)
        #expect(abs(gaps[0].bounds.height - 0.8) < 0.001)
    }

    @Test("Text at bottom creates gap above", .tags(.core, .figures))
    func textAtBottomGapAbove() {
        let text = [CGRect(x: 0, y: 0, width: 1, height: 0.2)]
        let gaps = OCRGapAnalyzer.findGaps(in: text)
        #expect(gaps.count == 1)
        #expect(abs(gaps[0].bounds.minY - 0.2) < 0.001)
        #expect(abs(gaps[0].bounds.height - 0.8) < 0.001)
    }

    @Test("Two text bands with figure gap between them", .tags(.core, .figures))
    func gapBetweenTwoBands() {
        let text = [
            CGRect(x: 0, y: 0.0, width: 1, height: 0.2),  // bottom text
            CGRect(x: 0, y: 0.7, width: 1, height: 0.3),  // top text
        ]
        let gaps = OCRGapAnalyzer.findGaps(in: text)
        #expect(gaps.count == 1, "Expected 1 gap between two text bands, got \(gaps.count)")
        #expect(abs(gaps[0].bounds.minY - 0.2) < 0.001)
        #expect(abs(gaps[0].bounds.height - 0.5) < 0.001)
    }

    @Test("Multiple gaps between three text bands", .tags(.core, .figures))
    func multipleGaps() {
        let text = [
            CGRect(x: 0, y: 0.0, width: 1, height: 0.1),  // bottom
            CGRect(x: 0, y: 0.3, width: 1, height: 0.1),  // middle
            CGRect(x: 0, y: 0.6, width: 1, height: 0.1),  // upper middle
        ]
        let gaps = OCRGapAnalyzer.findGaps(in: text)
        // Gaps: 0.1-0.3 (h=0.2), 0.4-0.6 (h=0.2), 0.7-1.0 (h=0.3) = 3 gaps
        #expect(gaps.count == 3, "Expected 3 gaps, got \(gaps.count)")
        // Sorted by Y position (bottom to top)
        #expect(abs(gaps[0].bounds.minY - 0.1) < 0.001)
        #expect(abs(gaps[1].bounds.minY - 0.4) < 0.001)
        #expect(abs(gaps[2].bounds.minY - 0.7) < 0.001)
    }

    // MARK: - Filtering

    @Test("Small gaps below threshold are filtered out", .tags(.core, .figures))
    func smallGapsFiltered() {
        let text = [
            CGRect(x: 0, y: 0.0, width: 1, height: 0.48),  // bottom half
            CGRect(x: 0, y: 0.52, width: 1, height: 0.48),  // top half
        ]
        // Gap is 0.04 (4%) which is below default 5% threshold
        let gaps = OCRGapAnalyzer.findGaps(in: text)
        #expect(gaps.isEmpty, "Gap of 4% should be filtered out by default 5% threshold")
    }

    @Test("Custom minimum gap height is respected", .tags(.core, .figures))
    func customMinimumHeight() {
        let text = [
            CGRect(x: 0, y: 0.0, width: 1, height: 0.48),
            CGRect(x: 0, y: 0.52, width: 1, height: 0.48),
        ]
        // Gap is 0.04 — use a lower threshold
        let gaps = OCRGapAnalyzer.findGaps(in: text, minimumGapHeight: 0.03)
        #expect(gaps.count == 1, "Gap of 4% should pass with 3% threshold")
    }

    // MARK: - Interval Merging

    @Test("Overlapping text blocks are merged before gap computation", .tags(.core, .figures))
    func overlappingTextMerged() {
        let text = [
            CGRect(x: 0.0, y: 0.5, width: 0.5, height: 0.3),  // y=0.5-0.8
            CGRect(x: 0.3, y: 0.6, width: 0.5, height: 0.2),  // y=0.6-0.8 (overlaps)
        ]
        let gaps = OCRGapAnalyzer.findGaps(in: text)
        // Merged band: y=0.5-0.8. Gaps: 0-0.5 (50%) and 0.8-1.0 (20%)
        #expect(gaps.count == 2)
        #expect(abs(gaps[0].bounds.minY - 0.0) < 0.001)
        #expect(abs(gaps[0].bounds.height - 0.5) < 0.001)
        #expect(abs(gaps[1].bounds.minY - 0.8) < 0.001)
        #expect(abs(gaps[1].bounds.height - 0.2) < 0.001)
    }

    @Test("Adjacent text blocks are merged", .tags(.core, .figures))
    func adjacentTextMerged() {
        let text = [
            CGRect(x: 0, y: 0.3, width: 1, height: 0.2),  // y=0.3-0.5
            CGRect(x: 0, y: 0.5, width: 1, height: 0.2),  // y=0.5-0.7 (touching)
        ]
        let gaps = OCRGapAnalyzer.findGaps(in: text)
        // Merged band: y=0.3-0.7. Gaps: 0-0.3 (30%) and 0.7-1.0 (30%)
        #expect(gaps.count == 2)
    }

    // MARK: - Real-world Simulation

    @Test("News page layout: hero + text + photo + caption", .tags(.figures))
    func newsPageLayout() {
        // Simulates the nu.nl news page layout from debug logs
        let text: [CGRect] = [
            // Headlines (y=0.683-0.895)
            CGRect(x: 0.02, y: 0.885, width: 0.43, height: 0.010),
            CGRect(x: 0.02, y: 0.875, width: 0.24, height: 0.009),
            CGRect(x: 0.00, y: 0.850, width: 0.50, height: 0.008),
            CGRect(x: 0.00, y: 0.836, width: 0.42, height: 0.006),
            CGRect(x: 0.00, y: 0.820, width: 0.47, height: 0.009),
            CGRect(x: 0.00, y: 0.805, width: 0.45, height: 0.007),
            CGRect(x: 0.00, y: 0.789, width: 0.49, height: 0.007),
            CGRect(x: 0.00, y: 0.775, width: 0.42, height: 0.008),
            CGRect(x: 0.00, y: 0.759, width: 0.32, height: 0.009),
            CGRect(x: 0.00, y: 0.744, width: 0.42, height: 0.007),
            CGRect(x: 0.00, y: 0.730, width: 0.49, height: 0.007),
            CGRect(x: 0.00, y: 0.714, width: 0.42, height: 0.007),
            CGRect(x: 0.00, y: 0.698, width: 0.48, height: 0.009),
            CGRect(x: 0.00, y: 0.683, width: 0.41, height: 0.007),
            // Section headers
            CGRect(x: 0.19, y: 0.667, width: 0.11, height: 0.009),
            CGRect(x: 0.00, y: 0.644, width: 0.14, height: 0.009),
            // Photo caption (y=0.510-0.532)
            CGRect(x: 0.02, y: 0.522, width: 0.39, height: 0.010),
            CGRect(x: 0.02, y: 0.510, width: 0.21, height: 0.010),
        ]

        let gaps = OCRGapAnalyzer.findGaps(in: text)

        // Expected gaps:
        // 1. Below caption (y=0-0.510): 51% → hero at bottom? Actually this is the bottom of the page
        // 2. Between caption and section headers (y=0.532-0.644): ~11.2% → whale photo
        // 3. Above headlines (y=0.895-1.0): ~10.5% → hero photo at top

        let heroGap = gaps.first { $0.bounds.minY > 0.89 }
        #expect(heroGap != nil, "Should detect hero photo gap above headlines")
        if let hero = heroGap {
            #expect(hero.heightFraction > 0.05, "Hero gap should be >5%, got \(hero.heightFraction)")
        }

        let whaleGap = gaps.first { $0.bounds.minY > 0.52 && $0.bounds.minY < 0.65 }
        #expect(whaleGap != nil, "Should detect whale photo gap between caption and section headers")
        if let whale = whaleGap {
            #expect(whale.heightFraction > 0.05, "Whale gap should be >5%, got \(whale.heightFraction)")
        }
    }

    // MARK: - Interval Merging Unit Tests

    @Test("mergeIntervals merges overlapping intervals", .tags(.core))
    func mergeIntervalsOverlapping() {
        let intervals: [(minY: CGFloat, maxY: CGFloat)] = [
            (0.1, 0.4), (0.3, 0.6), (0.8, 0.9)
        ]
        let merged = OCRGapAnalyzer.mergeIntervals(intervals)
        #expect(merged.count == 2)
        #expect(abs(merged[0].minY - 0.1) < 0.001)
        #expect(abs(merged[0].maxY - 0.6) < 0.001)
        #expect(abs(merged[1].minY - 0.8) < 0.001)
        #expect(abs(merged[1].maxY - 0.9) < 0.001)
    }

    @Test("mergeIntervals handles empty input", .tags(.core))
    func mergeIntervalsEmpty() {
        let merged = OCRGapAnalyzer.mergeIntervals([])
        #expect(merged.isEmpty)
    }

    @Test("mergeIntervals handles single interval", .tags(.core))
    func mergeIntervalsSingle() {
        let merged = OCRGapAnalyzer.mergeIntervals([(0.2, 0.5)])
        #expect(merged.count == 1)
    }
}
