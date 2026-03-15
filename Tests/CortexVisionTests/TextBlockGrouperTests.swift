import Testing
import CoreGraphics
@testable import CortexVision

@Suite("TextBlockGrouper — Grouping")
struct TextBlockGrouperTests {

    private let grouper = TextBlockGrouper()

    // TC-5a.8: 10 OCR lines with small gaps → grouped to 1-3 text blocks
    @Test("10 lines with small gaps grouped to 1-3 blocks", .tags(.core, .figures))
    func tenLinesSmallGaps() {
        // 10 lines of text, each 0.015 tall, spaced 0.005 apart (typical paragraph)
        // All in the same column (x=0.05, width=0.9)
        var blocks: [(text: String, bounds: CGRect)] = []
        for i in 0..<10 {
            let y = 0.8 - CGFloat(i) * 0.020  // Vision Y: top line at y=0.8, descending
            blocks.append((
                text: "Line \(i + 1) of the paragraph with some text content",
                bounds: CGRect(x: 0.05, y: y, width: 0.9, height: 0.015)
            ))
        }

        let result = grouper.group(blocks)

        #expect(result.count >= 1 && result.count <= 3,
                "10 close lines should group to 1-3 blocks, got \(result.count)")

        // All items should be text overlays
        #expect(result.allSatisfy { $0.kind == .text })
    }

    // TC-5a.9: Two separated text columns → two separate overlays
    @Test("Two text columns produce two separate overlays", .tags(.core, .figures))
    func twoColumns() {
        // Left column: 5 lines at x=0.05, width=0.4
        var blocks: [(text: String, bounds: CGRect)] = []
        for i in 0..<5 {
            let y = 0.8 - CGFloat(i) * 0.020
            blocks.append((
                text: "Left column line \(i + 1)",
                bounds: CGRect(x: 0.05, y: y, width: 0.4, height: 0.015)
            ))
        }

        // Right column: 5 lines at x=0.55, width=0.4 (no horizontal overlap with left)
        for i in 0..<5 {
            let y = 0.8 - CGFloat(i) * 0.020
            blocks.append((
                text: "Right column line \(i + 1)",
                bounds: CGRect(x: 0.55, y: y, width: 0.4, height: 0.015)
            ))
        }

        let result = grouper.group(blocks)

        #expect(result.count == 2,
                "Two non-overlapping columns should produce 2 groups, got \(result.count)")
    }

    @Test("Empty input produces empty output", .tags(.core))
    func emptyInput() {
        let result = grouper.group([] as [(text: String, bounds: CGRect)])
        #expect(result.isEmpty)
    }

    @Test("Single text block produces single overlay", .tags(.core))
    func singleBlock() {
        let blocks: [(text: String, bounds: CGRect)] = [
            (text: "Hello world", bounds: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.02))
        ]
        let result = grouper.group(blocks)
        #expect(result.count == 1)
        #expect(result[0].kind == .text)
        #expect(result[0].label == "Hello world")
    }

    @Test("Large vertical gap separates into different groups", .tags(.core, .figures))
    func largeGapSeparates() {
        // Two paragraphs with a large gap between them
        let blocks: [(text: String, bounds: CGRect)] = [
            // Paragraph 1 (top)
            (text: "First paragraph line 1", bounds: CGRect(x: 0.05, y: 0.8, width: 0.9, height: 0.015)),
            (text: "First paragraph line 2", bounds: CGRect(x: 0.05, y: 0.78, width: 0.9, height: 0.015)),
            // Paragraph 2 (bottom, large gap)
            (text: "Second paragraph line 1", bounds: CGRect(x: 0.05, y: 0.5, width: 0.9, height: 0.015)),
            (text: "Second paragraph line 2", bounds: CGRect(x: 0.05, y: 0.48, width: 0.9, height: 0.015)),
        ]

        let result = grouper.group(blocks)

        #expect(result.count == 2,
                "Two paragraphs with large gap should produce 2 groups, got \(result.count)")
    }

    @Test("Grouped bounds are in SwiftUI coordinates (top-left origin)", .tags(.core))
    func boundsAreSwiftUI() {
        // Single text block at Vision (x=0.1, y=0.8, w=0.5, h=0.02)
        // In SwiftUI: y should be 1.0 - 0.8 - 0.02 = 0.18
        let blocks: [(text: String, bounds: CGRect)] = [
            (text: "Test", bounds: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.02))
        ]

        let result = grouper.group(blocks)
        #expect(result.count == 1)

        let b = result[0].bounds
        #expect(abs(b.origin.x - 0.1) < 0.001, "x should be 0.1, got \(b.origin.x)")
        #expect(abs(b.origin.y - 0.18) < 0.001, "y should be 0.18 (SwiftUI), got \(b.origin.y)")
        #expect(abs(b.width - 0.5) < 0.001, "width should be 0.5, got \(b.width)")
        #expect(abs(b.height - 0.02) < 0.001, "height should be 0.02, got \(b.height)")
    }

    @Test("Grouped overlay contains combined text in label", .tags(.core))
    func combinedLabel() {
        let blocks: [(text: String, bounds: CGRect)] = [
            (text: "First line", bounds: CGRect(x: 0.05, y: 0.5, width: 0.9, height: 0.015)),
            (text: "Second line", bounds: CGRect(x: 0.05, y: 0.48, width: 0.9, height: 0.015)),
        ]

        let result = grouper.group(blocks)
        #expect(result.count == 1)
        #expect(result[0].label?.contains("First line") == true)
        #expect(result[0].label?.contains("Second line") == true)
    }
}
