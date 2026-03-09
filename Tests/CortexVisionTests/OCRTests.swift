import Testing
import CoreGraphics
@testable import CortexVision

// MARK: - TextBlock Model Tests

@Suite("OCR — TextBlock Model")
struct TextBlockModelTests {
    @Test("RecognizedWord isLowConfidence below 0.7 threshold", .tags(.core, .ocr))
    func wordLowConfidence() {
        // Functional: Words with low OCR confidence are flagged for user review
        // Technical: RecognizedWord.isLowConfidence returns true when confidence < 0.7
        let word = RecognizedWord(text: "blurry", confidence: 0.5, bounds: .zero)
        #expect(word.isLowConfidence == true)
    }

    @Test("RecognizedWord is not low confidence at 0.7", .tags(.core, .ocr))
    func wordNormalConfidence() {
        // Functional: Words with adequate confidence are not flagged
        // Technical: RecognizedWord.isLowConfidence returns false when confidence >= 0.7
        let word = RecognizedWord(text: "clear", confidence: 0.7, bounds: .zero)
        #expect(word.isLowConfidence == false)
    }

    @Test("RecognizedWord is not low confidence at high confidence", .tags(.core, .ocr))
    func wordHighConfidence() {
        let word = RecognizedWord(text: "sharp", confidence: 0.95, bounds: .zero)
        #expect(word.isLowConfidence == false)
    }

    @Test("TextBlock detects low confidence words", .tags(.core, .ocr))
    func blockHasLowConfidenceWords() {
        // Functional: Text blocks with unreliable words are highlighted in the results panel
        // Technical: TextBlock.hasLowConfidenceWords returns true if any word has confidence < 0.7
        let words = [
            RecognizedWord(text: "Hello", confidence: 0.95, bounds: .zero),
            RecognizedWord(text: "wrld", confidence: 0.4, bounds: .zero),
        ]
        let block = TextBlock(text: "Hello wrld", confidence: 0.7, bounds: .zero, words: words)
        #expect(block.hasLowConfidenceWords == true)
    }

    @Test("TextBlock without low confidence words", .tags(.core, .ocr))
    func blockAllHighConfidence() {
        let words = [
            RecognizedWord(text: "Hello", confidence: 0.95, bounds: .zero),
            RecognizedWord(text: "World", confidence: 0.88, bounds: .zero),
        ]
        let block = TextBlock(text: "Hello World", confidence: 0.9, bounds: .zero, words: words)
        #expect(block.hasLowConfidenceWords == false)
    }

    @Test("TextBlock pixelRect converts normalized bounds", .tags(.core, .ocr))
    func blockPixelRect() {
        // Functional: Text block bounding boxes are correctly positioned on the preview
        // Technical: TextBlock.pixelRect(for:) converts normalized 0..1 bounds to pixel coordinates
        let block = TextBlock(text: "Test", confidence: 1.0, bounds: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.05))
        let pixel = block.pixelRect(for: CGSize(width: 1000, height: 800))
        #expect(pixel.origin.x == 100)
        #expect(pixel.origin.y == 160)
        #expect(pixel.width == 500)
        #expect(pixel.height == 40)
    }

    @Test("OCRResult fullText joins blocks with newlines", .tags(.core, .ocr))
    func ocrResultFullText() {
        // Functional: User sees all recognized text as continuous readable text
        // Technical: OCRResult.fullText joins all block texts with newline separators
        let blocks = [
            TextBlock(text: "First line", confidence: 1.0, bounds: CGRect(x: 0, y: 0, width: 1, height: 0.1)),
            TextBlock(text: "Second line", confidence: 1.0, bounds: CGRect(x: 0, y: 0.2, width: 1, height: 0.1)),
        ]
        let result = OCRResult(textBlocks: blocks)
        #expect(result.fullText == "First line\nSecond line")
    }

    @Test("OCRResult wordCount sums across blocks", .tags(.core, .ocr))
    func ocrResultWordCount() {
        // Functional: Status bar shows correct total word count
        // Technical: OCRResult.wordCount sums words across all text blocks
        let blocks = [
            TextBlock(text: "Hello World", confidence: 1.0, bounds: .zero, words: [
                RecognizedWord(text: "Hello", confidence: 1.0, bounds: .zero),
                RecognizedWord(text: "World", confidence: 1.0, bounds: .zero),
            ]),
            TextBlock(text: "Test", confidence: 1.0, bounds: .zero, words: [
                RecognizedWord(text: "Test", confidence: 1.0, bounds: .zero),
            ]),
        ]
        let result = OCRResult(textBlocks: blocks)
        #expect(result.wordCount == 3)
    }

    @Test("OCRResult.empty has no text or words", .tags(.core, .ocr))
    func ocrResultEmpty() {
        // Functional: Empty capture produces empty result without crash
        // Technical: OCRResult.empty contains no blocks, empty fullText, zero wordCount
        let result = OCRResult.empty
        #expect(result.textBlocks.isEmpty)
        #expect(result.fullText.isEmpty)
        #expect(result.wordCount == 0)
    }

    @Test("Each RecognizedWord has a unique identifier", .tags(.core, .ocr))
    func wordUniqueIds() {
        let w1 = RecognizedWord(text: "A", confidence: 1.0, bounds: .zero)
        let w2 = RecognizedWord(text: "B", confidence: 1.0, bounds: .zero)
        #expect(w1.id != w2.id)
    }
}

// MARK: - Reading Order Tests

@Suite("OCR — Reading Order Sorter")
struct ReadingOrderSorterTests {
    @Test("Single block returns unchanged", .tags(.core, .ocr))
    func singleBlock() {
        // Functional: A single text block is returned as-is
        let block = TextBlock(text: "Only", confidence: 1.0, bounds: CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.05))
        let sorted = ReadingOrderSorter.sort([block])
        #expect(sorted.count == 1)
        #expect(sorted[0].text == "Only")
    }

    @Test("Empty array returns empty", .tags(.core, .ocr))
    func emptyBlocks() {
        let sorted = ReadingOrderSorter.sort([])
        #expect(sorted.isEmpty)
    }

    @Test("Blocks on same line sorted left to right", .tags(.core, .ocr))
    func sameLineSorting() {
        // Functional: Words on the same line appear in left-to-right order
        // Technical: Blocks with similar Y positions are clustered into one band and sorted by X
        let right = TextBlock(text: "Right", confidence: 1.0, bounds: CGRect(x: 0.6, y: 0.5, width: 0.2, height: 0.05))
        let left = TextBlock(text: "Left", confidence: 1.0, bounds: CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.05))
        let sorted = ReadingOrderSorter.sort([right, left])
        #expect(sorted[0].text == "Left")
        #expect(sorted[1].text == "Right")
    }

    @Test("Blocks on different lines sorted top to bottom", .tags(.core, .ocr))
    func differentLinesSorting() {
        // Functional: Text reads from top to bottom of the page
        // Technical: Vision uses bottom-left origin: higher midY = higher on screen = read first
        let bottom = TextBlock(text: "Bottom", confidence: 1.0, bounds: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05))
        let top = TextBlock(text: "Top", confidence: 1.0, bounds: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.05))
        let sorted = ReadingOrderSorter.sort([bottom, top])
        #expect(sorted[0].text == "Top")
        #expect(sorted[1].text == "Bottom")
    }

    @Test("Multi-column layout reads column by column", .tags(.core, .ocr))
    func multiColumnLayout() {
        // Functional: Two-column text reads left column top-to-bottom, then right column top-to-bottom
        // Technical: Column detection finds consistent horizontal gap → reads per column, not per row
        let blocks = [
            TextBlock(text: "Col2-Line1", confidence: 1.0, bounds: CGRect(x: 0.55, y: 0.8, width: 0.4, height: 0.05)),
            TextBlock(text: "Col1-Line2", confidence: 1.0, bounds: CGRect(x: 0.05, y: 0.7, width: 0.4, height: 0.05)),
            TextBlock(text: "Col1-Line1", confidence: 1.0, bounds: CGRect(x: 0.05, y: 0.8, width: 0.4, height: 0.05)),
            TextBlock(text: "Col2-Line2", confidence: 1.0, bounds: CGRect(x: 0.55, y: 0.7, width: 0.4, height: 0.05)),
        ]
        let sorted = ReadingOrderSorter.sort(blocks)
        #expect(sorted[0].text == "Col1-Line1")
        #expect(sorted[1].text == "Col1-Line2")
        #expect(sorted[2].text == "Col2-Line1")
        #expect(sorted[3].text == "Col2-Line2")
    }

    @Test("Full-width header above columns reads first", .tags(.core, .ocr))
    func headerAboveColumns() {
        // Functional: A title spanning the full width is read before column content
        // Technical: Block spanning the column boundary is classified as full-width
        let blocks = [
            TextBlock(text: "Page Title", confidence: 1.0, bounds: CGRect(x: 0.05, y: 0.9, width: 0.9, height: 0.05)),
            TextBlock(text: "Col2-Line1", confidence: 1.0, bounds: CGRect(x: 0.55, y: 0.8, width: 0.4, height: 0.05)),
            TextBlock(text: "Col1-Line1", confidence: 1.0, bounds: CGRect(x: 0.05, y: 0.8, width: 0.4, height: 0.05)),
            TextBlock(text: "Col2-Line2", confidence: 1.0, bounds: CGRect(x: 0.55, y: 0.7, width: 0.4, height: 0.05)),
            TextBlock(text: "Col1-Line2", confidence: 1.0, bounds: CGRect(x: 0.05, y: 0.7, width: 0.4, height: 0.05)),
        ]
        let sorted = ReadingOrderSorter.sort(blocks)
        #expect(sorted[0].text == "Page Title")
        #expect(sorted[1].text == "Col1-Line1")
        #expect(sorted[2].text == "Col1-Line2")
        #expect(sorted[3].text == "Col2-Line1")
        #expect(sorted[4].text == "Col2-Line2")
    }

    @Test("Single-line text is not detected as columns", .tags(.core, .ocr))
    func noFalseColumnDetection() {
        // Functional: Regular text on the same line is not split into columns
        // Technical: Only 1 multi-block band → column detection requires >= 2
        let blocks = [
            TextBlock(text: "Word1", confidence: 1.0, bounds: CGRect(x: 0.05, y: 0.5, width: 0.2, height: 0.05)),
            TextBlock(text: "Word2", confidence: 1.0, bounds: CGRect(x: 0.55, y: 0.5, width: 0.2, height: 0.05)),
            TextBlock(text: "Line2", confidence: 1.0, bounds: CGRect(x: 0.05, y: 0.3, width: 0.5, height: 0.05)),
        ]
        let sorted = ReadingOrderSorter.sort(blocks)
        // Should read line-by-line, left-to-right (no column detection)
        #expect(sorted[0].text == "Word1")
        #expect(sorted[1].text == "Word2")
        #expect(sorted[2].text == "Line2")
    }
}
