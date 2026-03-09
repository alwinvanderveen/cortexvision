import Testing
import CoreGraphics
import CoreImage
import Vision
import AppKit
@testable import CortexVision

// MARK: - Test Reference Window

/// Creates an NSWindow with known, verifiable content:
/// - QR code encoding a unique identifier in the center
/// - Colored corners: red (top-left), green (top-right), blue (bottom-left), yellow (bottom-right)
/// - Known text label below the QR code
@MainActor
private final class ReferenceWindow {
    let window: NSWindow
    let identifier: String
    let expectedText = "CortexVision Verify"

    init(on screen: NSScreen, size: CGSize = CGSize(width: 400, height: 400), borderless: Bool = false) {
        self.identifier = UUID().uuidString

        // Position window in center of the given screen
        let screenFrame = screen.frame
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )

        window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: borderless ? [.borderless] : [.titled, .closable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "CortexVision Test Reference \(identifier.prefix(8))"
        window.backgroundColor = .white
        window.level = .floating // Keep above other windows for region capture

        let contentView = ReferenceContentView(
            frame: NSRect(origin: .zero, size: size),
            qrData: identifier,
            labelText: expectedText
        )
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Force layout and display so content is rendered before capture
        contentView.display()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window.orderOut(nil)
    }
}

/// Custom NSView that draws the reference pattern.
private final class ReferenceContentView: NSView {
    let qrData: String
    let labelText: String

    init(frame: NSRect, qrData: String, labelText: String) {
        self.qrData = qrData
        self.labelText = labelText
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        // White background
        NSColor.white.setFill()
        bounds.fill()

        let cornerSize: CGFloat = 40

        // Use sRGB colors explicitly to get predictable pixel values.
        // NSColor.green etc. use the catalog/P3 colorspace which shifts RGB when
        // captured and read back as raw bytes.
        let srgb = NSColorSpace.sRGB

        // Top-left: RED
        NSColor(colorSpace: srgb, components: [1, 0, 0, 1], count: 4).setFill()
        NSRect(x: 0, y: bounds.height - cornerSize, width: cornerSize, height: cornerSize).fill()

        // Top-right: GREEN
        NSColor(colorSpace: srgb, components: [0, 1, 0, 1], count: 4).setFill()
        NSRect(x: bounds.width - cornerSize, y: bounds.height - cornerSize, width: cornerSize, height: cornerSize).fill()

        // Bottom-left: BLUE
        NSColor(colorSpace: srgb, components: [0, 0, 1, 1], count: 4).setFill()
        NSRect(x: 0, y: 0, width: cornerSize, height: cornerSize).fill()

        // Bottom-right: YELLOW
        NSColor(colorSpace: srgb, components: [1, 1, 0, 1], count: 4).setFill()
        NSRect(x: bounds.width - cornerSize, y: 0, width: cornerSize, height: cornerSize).fill()

        // QR code in center
        if let qrImage = generateQRCode(from: qrData) {
            let qrSize: CGFloat = 160
            let qrRect = NSRect(
                x: (bounds.width - qrSize) / 2,
                y: (bounds.height - qrSize) / 2 + 20,
                width: qrSize,
                height: qrSize
            )
            let nsImage = NSImage(cgImage: qrImage, size: NSSize(width: qrSize, height: qrSize))
            nsImage.draw(in: qrRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        // Text label below QR
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let textSize = labelText.size(withAttributes: attrs)
        let textPoint = NSPoint(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - 160) / 2 - 30
        )
        labelText.draw(at: textPoint, withAttributes: attrs)
    }

    private func generateQRCode(from string: String) -> CGImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        // Scale up for clarity
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: scale)
        let context = CIContext()
        return context.createCGImage(scaledImage, from: scaledImage.extent)
    }
}

// MARK: - Pixel Sampling Helper

/// Convert a CGImage to sRGB color space to get predictable pixel values.
/// ScreenCaptureKit captures in the display's native color space (often P3),
/// so raw pixel bytes differ from sRGB expectations.
private func convertToSRGB(_ image: CGImage) -> CGImage? {
    guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    guard let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
}

/// Sample the color of a pixel in a CGImage at the given (x, y) coordinate.
/// Returns (r, g, b) as values 0-255. Converts to sRGB first for predictable values.
private func samplePixel(in image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int)? {
    let img = convertToSRGB(image) ?? image
    guard x >= 0, y >= 0, x < img.width, y < img.height else { return nil }

    guard let dataProvider = img.dataProvider,
          let data = dataProvider.data,
          let ptr = CFDataGetBytePtr(data) else { return nil }

    let bytesPerPixel = img.bitsPerPixel / 8
    let bytesPerRow = img.bytesPerRow
    let offset = y * bytesPerRow + x * bytesPerPixel

    // After sRGB conversion the format is RGBA (premultipliedLast)
    return (r: Int(ptr[offset]), g: Int(ptr[offset + 1]), b: Int(ptr[offset + 2]))
}

/// Check if a color is approximately the expected color (tolerance for rendering differences).
private func colorMatches(_ pixel: (r: Int, g: Int, b: Int), expected: (r: Int, g: Int, b: Int), tolerance: Int = 40) -> Bool {
    abs(pixel.r - expected.r) <= tolerance &&
    abs(pixel.g - expected.g) <= tolerance &&
    abs(pixel.b - expected.b) <= tolerance
}

// MARK: - Verification Tests

@Suite("Capture — Verification Tests", .serialized)
struct CaptureVerificationTests {
    @Test("Window capture contains correct QR code data",
          .tags(.capture, .core),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func windowCaptureQRVerification() async throws {
        // Functional: A captured window contains all its visual content, verifiable by QR decode
        // Technical: Create reference window → capture via captureWindow → decode QR → match identifier
        // Input: Reference window with unique QR code
        // Expected: Decoded QR data matches the generated identifier
        let screen = NSScreen.main!
        let ref = ReferenceWindow(on: screen)

        // Allow window to fully render
        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let windows = try await provider.availableWindows()
        let titlePrefix = "CortexVision Test Reference \(ref.identifier.prefix(8))"
        let testWindow = windows.first(where: { $0.title.hasPrefix(titlePrefix) })
        #expect(testWindow != nil, "Reference window should appear in window list")

        let result = try await provider.captureWindow(id: testWindow!.id)
        ref.close()

        // Decode QR from captured image
        let decoded = try decodeQR(from: result.image)
        #expect(decoded == ref.identifier, "QR data should match: expected \(ref.identifier), got \(decoded ?? "nil")")
    }

    @Test("Region capture contains correct QR code data",
          .tags(.capture, .core),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func regionCaptureQRVerification() async throws {
        // Functional: A captured screen region contains the exact content at that position
        // Technical: Create reference window → capture its screen region → decode QR → match
        // Input: Reference window at known position, capture that region
        // Expected: Decoded QR data matches the generated identifier
        let screen = NSScreen.main!
        let ref = ReferenceWindow(on: screen)

        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        // Use the content frame (window frame) for region capture
        let windowFrame = ref.window.frame
        let result = try await provider.captureRegion(windowFrame)
        ref.close()

        let decoded = try decodeQR(from: result.image)
        #expect(decoded == ref.identifier, "QR data should match: expected \(ref.identifier), got \(decoded ?? "nil")")
    }

    @Test("Region capture has colored corners in correct positions",
          .tags(.capture, .core),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func regionCaptureCornerColors() async throws {
        // Functional: Captured image is not cropped or shifted — all four corners are present
        // Technical: Capture content rect of reference window, sample pixels near corners, verify colors
        // Input: Reference window with red/green/blue/yellow corners
        // Expected: Top-left≈red, top-right≈green, bottom-left≈blue, bottom-right≈yellow
        let screen = NSScreen.main!
        let ref = ReferenceWindow(on: screen)

        try await Task.sleep(for: .milliseconds(500))

        // Capture only the content area (excludes titlebar) in screen coordinates
        let windowFrame = ref.window.frame
        let contentRect = ref.window.contentLayoutRect
        let contentScreenRect = CGRect(
            x: windowFrame.origin.x + contentRect.origin.x,
            y: windowFrame.origin.y + contentRect.origin.y,
            width: contentRect.width,
            height: contentRect.height
        )

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(contentScreenRect)
        ref.close()

        let img = result.image

        // The image may be larger than the actual content due to captureRegion hardcoding 2x.
        // Use the screen's backing scale factor to find the actual content pixel dimensions.
        let scale = screen.backingScaleFactor
        let contentW = Int(contentRect.width * scale)
        let contentH = Int(contentRect.height * scale)

        // The colored squares are 40pt each. Sample 10pt (in content pixels) inward from each corner.
        let inset = Int(10 * scale)

        // Top-left should be RED (in CG coords, top-left is y=0)
        let topLeft = samplePixel(in: img, x: inset, y: inset)
        #expect(topLeft != nil)
        #expect(colorMatches(topLeft!, expected: (r: 255, g: 0, b: 0), tolerance: 80),
                "Top-left corner should be red, got \(topLeft!)")

        // Top-right should be GREEN
        let topRight = samplePixel(in: img, x: contentW - inset - 1, y: inset)
        #expect(topRight != nil)
        #expect(colorMatches(topRight!, expected: (r: 0, g: 255, b: 0), tolerance: 80),
                "Top-right corner should be green, got \(topRight!)")

        // Bottom-left should be BLUE
        let bottomLeft = samplePixel(in: img, x: inset, y: contentH - inset - 1)
        #expect(bottomLeft != nil)
        #expect(colorMatches(bottomLeft!, expected: (r: 0, g: 0, b: 255), tolerance: 80),
                "Bottom-left corner should be blue, got \(bottomLeft!)")

        // Bottom-right should be YELLOW
        let bottomRight = samplePixel(in: img, x: contentW - inset - 1, y: contentH - inset - 1)
        #expect(bottomRight != nil)
        #expect(colorMatches(bottomRight!, expected: (r: 255, g: 255, b: 0), tolerance: 80),
                "Bottom-right corner should be yellow, got \(bottomRight!)")
    }

    @Test("Region capture contains recognizable text via OCR",
          .tags(.capture, .ocr),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func regionCaptureOCRVerification() async throws {
        // Functional: Captured region text is readable by OCR — full content integrity
        // Technical: Create reference window with known text → capture region → OCR → verify text
        // Input: Reference window with "CortexVision Verify" label
        // Expected: OCR results contain "CortexVision" and "Verify"
        let screen = NSScreen.main!
        let ref = ReferenceWindow(on: screen)

        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: result.image, options: [:])
        try handler.perform([request])

        let recognizedText = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")

        #expect(recognizedText.contains("CortexVision"), "OCR should find 'CortexVision' in: \(recognizedText)")
        #expect(recognizedText.contains("Verify"), "OCR should find 'Verify' in: \(recognizedText)")
    }

    @Test("Secondary screen capture contains correct QR code",
          .tags(.capture, .core),
          .enabled(if: isScreenRecordingAvailable && NSScreen.screens.count > 1))
    @MainActor
    func secondaryScreenCaptureQR() async throws {
        // Functional: Capture works correctly on a secondary display
        // Technical: Place reference window on secondary screen → region capture → decode QR
        // Input: Reference window on second screen
        // Expected: Decoded QR data matches identifier
        let secondaryScreen = NSScreen.screens.first(where: { $0 != NSScreen.main })!
        let ref = ReferenceWindow(on: secondaryScreen)

        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let decoded = try decodeQR(from: result.image)
        #expect(decoded == ref.identifier, "Secondary screen QR should match")
    }

    // MARK: - OCR Self-Verification Tests

    @Test("OCR recognizes single paragraph text",
          .tags(.ocr, .capture),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func singleParagraphOCR() async throws {
        // Functional: OCR correctly recognizes a paragraph of clear text
        // Technical: Create reference window with known text → capture → OCR → verify key phrases
        let screen = NSScreen.main!
        let ref = OCRReferenceWindow.singleParagraph(on: screen)
        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let engine = OCREngine()
        let ocrResult = try await engine.recognizeText(in: result.image)

        let fullText = ocrResult.fullText
        #expect(fullText.contains("CortexVision"), "Should find 'CortexVision' in: \(fullText)")
        #expect(fullText.contains("OCR"), "Should find 'OCR' in: \(fullText)")
        #expect(ocrResult.textBlocks.count >= 1, "Should have at least one text block")
        #expect(ocrResult.wordCount > 0, "Should have recognized words")
    }

    @Test("OCR recognizes two-column layout",
          .tags(.ocr, .capture),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func twoColumnOCR() async throws {
        // Functional: OCR handles multi-column text layouts
        // Technical: Two-column reference window → capture → OCR → verify both columns recognized
        let screen = NSScreen.main!
        let ref = OCRReferenceWindow.twoColumns(on: screen)
        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let engine = OCREngine()
        let ocrResult = try await engine.recognizeText(in: result.image)

        let fullText = ocrResult.fullText
        #expect(fullText.contains("Left"), "Should find 'Left' in: \(fullText)")
        #expect(fullText.contains("Right"), "Should find 'Right' in: \(fullText)")
        let hasLeftContent = fullText.contains("Alpha") || fullText.contains("Delta")
        let hasRightContent = fullText.contains("One") || fullText.contains("Two") || fullText.contains("Four") || fullText.contains("Five")
        #expect(hasLeftContent, "Should find left column content in: \(fullText)")
        #expect(hasRightContent, "Should find right column content in: \(fullText)")
    }

    @Test("OCR recognizes text around figures",
          .tags(.ocr, .capture),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func textWithFigureOCR() async throws {
        // Functional: OCR extracts text correctly even when figures are present
        // Technical: Reference window with text and blue rectangle → capture → OCR → verify text
        let screen = NSScreen.main!
        let ref = OCRReferenceWindow.textWithFigure(on: screen)
        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let engine = OCREngine()
        let ocrResult = try await engine.recognizeText(in: result.image)

        let fullText = ocrResult.fullText
        let hasAboveText = fullText.contains("Mixed") || fullText.contains("Content") || fullText.contains("above")
        let hasBelowText = fullText.contains("below") || fullText.contains("figure")
        #expect(hasAboveText, "Should find text above figure in: \(fullText)")
        #expect(hasBelowText, "Should find text below figure in: \(fullText)")
    }

    @Test("OCR recognizes Dutch diacritics",
          .tags(.ocr, .capture),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func dutchDiacriticsOCR() async throws {
        // Functional: OCR correctly handles Dutch characters with diacritics
        // Technical: Reference window with Dutch text → capture → OCR → verify diacritics preserved
        let screen = NSScreen.main!
        let ref = OCRReferenceWindow.dutchText(on: screen)
        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let engine = OCREngine()
        let ocrResult = try await engine.recognizeText(in: result.image)

        let fullText = ocrResult.fullText
        #expect(fullText.contains("Nederlandse"), "Should find 'Nederlandse' in: \(fullText)")
        let hasDiacritics = fullText.contains("café") || fullText.contains("crème") ||
                           fullText.contains("brûlée") || fullText.contains("geïnspireerde") ||
                           fullText.contains("coöperatie")
        #expect(hasDiacritics, "Should recognize at least some Dutch diacritics in: \(fullText)")
    }

    @Test("OCR on empty window produces empty result",
          .tags(.ocr, .capture),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func emptyContentOCR() async throws {
        // Functional: Empty capture produces empty result without crash
        // Technical: White window with no text → capture → OCR → verify minimal result
        let screen = NSScreen.main!
        let ref = OCRReferenceWindow.emptyContent(on: screen)
        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let engine = OCREngine()
        let ocrResult = try await engine.recognizeText(in: result.image)

        #expect(ocrResult.textBlocks.count <= 2, "Empty window should have very few text blocks, got \(ocrResult.textBlocks.count)")
    }

    @Test("OCR recognizes multiple separated paragraphs",
          .tags(.ocr, .capture),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func multipleParagraphsOCR() async throws {
        // Functional: OCR handles multiple paragraphs with spacing between them
        // Technical: Reference window with 3 paragraphs → capture → OCR → verify all found
        let screen = NSScreen.main!
        let ref = OCRReferenceWindow.multipleParagraphs(on: screen)
        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let engine = OCREngine()
        let ocrResult = try await engine.recognizeText(in: result.image)

        let fullText = ocrResult.fullText
        #expect(fullText.contains("First"), "Should find 'First' in: \(fullText)")
        #expect(fullText.contains("Second"), "Should find 'Second' in: \(fullText)")
        #expect(fullText.contains("Third"), "Should find 'Third' in: \(fullText)")
        #expect(fullText.contains("fox"), "Should find 'fox' in: \(fullText)")
        #expect(ocrResult.textBlocks.count >= 3, "Should have at least 3 text blocks for 3 paragraphs")
    }

    @Test("OCR confidence scores are within valid range",
          .tags(.ocr, .capture),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func confidenceScoreRange() async throws {
        // Functional: Confidence scores are meaningful values between 0 and 1
        // Technical: OCR on clear text should produce high confidence (>0.8) with values in [0,1]
        let screen = NSScreen.main!
        let ref = OCRReferenceWindow.singleParagraph(on: screen)
        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let engine = OCREngine()
        let ocrResult = try await engine.recognizeText(in: result.image)

        for block in ocrResult.textBlocks {
            #expect(block.confidence >= 0.0 && block.confidence <= 1.0,
                    "Block confidence \(block.confidence) should be in [0,1]")
            for word in block.words {
                #expect(word.confidence >= 0.0 && word.confidence <= 1.0,
                        "Word confidence \(word.confidence) should be in [0,1]")
            }
        }

        let avgConfidence = ocrResult.textBlocks.map(\.confidence).reduce(0, +) / Float(max(ocrResult.textBlocks.count, 1))
        #expect(avgConfidence > 0.8, "Average confidence on clear text should be >0.8, got \(avgConfidence)")
    }

    @Test("OCR text blocks have valid normalized bounds",
          .tags(.ocr, .capture),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func textBlockBoundsValid() async throws {
        // Functional: Bounding boxes are correctly positioned within the image
        // Technical: All bounds should be within 0..1 range (normalized coordinates from Vision)
        let screen = NSScreen.main!
        let ref = OCRReferenceWindow.singleParagraph(on: screen)
        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let engine = OCREngine()
        let ocrResult = try await engine.recognizeText(in: result.image)

        // Vision framework may return slightly negative values near edges (rounding)
        let tolerance: CGFloat = 0.01
        for block in ocrResult.textBlocks {
            #expect(block.bounds.origin.x >= -tolerance && block.bounds.origin.x <= 1,
                    "Block x \(block.bounds.origin.x) should be near [0,1]")
            #expect(block.bounds.origin.y >= -tolerance && block.bounds.origin.y <= 1,
                    "Block y \(block.bounds.origin.y) should be near [0,1]")
            #expect(block.bounds.width > 0 && block.bounds.maxX <= 1 + tolerance,
                    "Block width should be positive and maxX within bounds")
            #expect(block.bounds.height > 0 && block.bounds.maxY <= 1 + tolerance,
                    "Block height should be positive and maxY within bounds")
        }
    }

    @Test("OCR only captures visible text in scrollable window",
          .tags(.ocr, .capture),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func scrollingTextOCR() async throws {
        // Functional: When a window has a scrollbar, OCR only recognizes text visible in the viewport
        // Technical: Create window with NSScrollView containing 10 paragraphs in a 300pt window →
        //           capture → OCR → verify top paragraphs are found, bottom paragraphs are NOT
        // Input: 10 paragraphs with unique keywords (ALPHA through JULIET) in 600x300 window
        // Expected: ALPHA (top), BRAVO (2nd), CHARLIE (3rd) visible; HOTEL, INDIA, JULIET NOT visible
        let screen = NSScreen.main!
        let ref = OCRReferenceWindow.scrollingText(on: screen)
        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let engine = OCREngine()
        let ocrResult = try await engine.recognizeText(in: result.image)

        let fullText = ocrResult.fullText.uppercased()

        // Top paragraphs should be visible and recognized
        #expect(fullText.contains("ALPHA"),
                "First paragraph (ALPHA) should be visible at top: \(ocrResult.fullText)")
        #expect(fullText.contains("BRAVO"),
                "Second paragraph (BRAVO) should be visible: \(ocrResult.fullText)")
        #expect(fullText.contains("CHARLIE"),
                "Third paragraph (CHARLIE) should be visible: \(ocrResult.fullText)")

        // Paragraphs far below the fold should NOT be captured
        #expect(!fullText.contains("HOTEL"),
                "Eighth paragraph (HOTEL) should NOT be visible (scrolled off): \(ocrResult.fullText)")
        #expect(!fullText.contains("INDIA"),
                "Ninth paragraph (INDIA) should NOT be visible (scrolled off): \(ocrResult.fullText)")
        #expect(!fullText.contains("JULIET"),
                "Tenth paragraph (JULIET) should NOT be visible (scrolled off): \(ocrResult.fullText)")

        // Should have recognized multiple text blocks from visible area
        #expect(ocrResult.textBlocks.count >= 2,
                "Should find multiple text blocks in visible area")
        #expect(ocrResult.wordCount > 10,
                "Should find significant word count in visible area")
    }

    // MARK: - Helpers

    private func decodeQR(from image: CGImage) throws -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return request.results?
            .compactMap { $0.payloadStringValue }
            .first
    }
}

// MARK: - OCR Reference Windows

/// Creates reference windows with specific text layouts for OCR verification.
@MainActor
private final class OCRReferenceWindow {
    let window: NSWindow

    static func singleParagraph(on screen: NSScreen) -> OCRReferenceWindow {
        let content = "CortexVision OCR Test\nThis is a single paragraph of text used to verify\nthat the OCR engine correctly recognizes and extracts\ntext content from captured screen regions."
        return OCRReferenceWindow(on: screen, size: CGSize(width: 600, height: 300), content: content)
    }

    static func twoColumns(on screen: NSScreen) -> OCRReferenceWindow {
        return OCRReferenceWindow(on: screen, size: CGSize(width: 800, height: 350), columns: [
            "Left Column\nAlpha Beta\nDelta Epsilon",
            "Right Column\nOne Two\nFour Five",
        ])
    }

    static func textWithFigure(on screen: NSScreen) -> OCRReferenceWindow {
        return OCRReferenceWindow(on: screen, size: CGSize(width: 700, height: 500), textAndFigure: true)
    }

    static func dutchText(on screen: NSScreen) -> OCRReferenceWindow {
        let content = "Nederlandse tekst verificatie\nHet café serveerde crème brûlée\nen geïnspireerde coöperatie ideeën"
        return OCRReferenceWindow(on: screen, size: CGSize(width: 600, height: 250), content: content)
    }

    static func emptyContent(on screen: NSScreen) -> OCRReferenceWindow {
        return OCRReferenceWindow(on: screen, size: CGSize(width: 400, height: 300), content: nil)
    }

    static func multipleParagraphs(on screen: NSScreen) -> OCRReferenceWindow {
        return OCRReferenceWindow(on: screen, size: CGSize(width: 600, height: 500), paragraphs: [
            "First Paragraph\nThe quick brown fox jumps over the lazy dog.",
            "Second Paragraph\nPack my box with five dozen liquor jugs.",
            "Third Paragraph\nHow vexingly quick daft zebras jump.",
        ])
    }

    /// Creates a window with an NSScrollView containing many paragraphs.
    /// Only a few paragraphs are visible; the rest overflow below the fold.
    /// Each paragraph has a unique keyword for identification.
    static func scrollingText(on screen: NSScreen) -> OCRReferenceWindow {
        let paragraphs = [
            "ALPHA paragraph is the first block of text visible at the very top of this scrollable document window.",
            "BRAVO paragraph comes second and should still be visible in the upper portion of the viewport area.",
            "CHARLIE paragraph is the third block and may be partially visible depending on the window height used.",
            "DELTA paragraph is the fourth block of text which likely falls near the bottom edge of the viewport.",
            "ECHO paragraph is the fifth block of content that should be just barely visible or at the fold line.",
            "FOXTROT paragraph is the sixth block of text and starts going below the visible area of the window.",
            "GOLF paragraph is the seventh block which is definitely scrolled out of view in the initial state.",
            "HOTEL paragraph is the eighth block of content far below the visible viewport of this test window.",
            "INDIA paragraph is the ninth block of text well beyond the scroll position of the initial viewport.",
            "JULIET paragraph is the tenth and final block of text at the very bottom of the scrollable content.",
        ]
        return OCRReferenceWindow(on: screen, size: CGSize(width: 600, height: 300), scrollingParagraphs: paragraphs)
    }

    private init(on screen: NSScreen, size: CGSize, content: String?) {
        let screenFrame = screen.frame
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "OCR Test Reference"
        window.backgroundColor = .white
        window.level = .floating

        let view = OCRSingleTextView(frame: NSRect(origin: .zero, size: size), content: content)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        view.display()
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(on screen: NSScreen, size: CGSize, columns: [String]) {
        let screenFrame = screen.frame
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "OCR Test Columns"
        window.backgroundColor = .white
        window.level = .floating

        let view = OCRColumnTextView(frame: NSRect(origin: .zero, size: size), columns: columns)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        view.display()
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(on screen: NSScreen, size: CGSize, textAndFigure: Bool) {
        let screenFrame = screen.frame
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "OCR Test With Figure"
        window.backgroundColor = .white
        window.level = .floating

        let view = OCRTextAndFigureView(frame: NSRect(origin: .zero, size: size))
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        view.display()
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(on screen: NSScreen, size: CGSize, paragraphs: [String]) {
        let screenFrame = screen.frame
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "OCR Test Paragraphs"
        window.backgroundColor = .white
        window.level = .floating

        let view = OCRParagraphsView(frame: NSRect(origin: .zero, size: size), paragraphs: paragraphs)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        view.display()
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(on screen: NSScreen, size: CGSize, scrollingParagraphs: [String]) {
        let screenFrame = screen.frame
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "OCR Test Scrolling"
        window.backgroundColor = .white
        window.level = .floating

        let view = OCRScrollingTextView(frame: NSRect(origin: .zero, size: size), paragraphs: scrollingParagraphs)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        view.display()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window.orderOut(nil)
    }
}

// MARK: - OCR Reference Content Views

private final class OCRSingleTextView: NSView {
    let content: String?

    init(frame: NSRect, content: String?) {
        self.content = content
        super.init(frame: frame)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        guard let content else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        let lines = content.components(separatedBy: "\n")
        var y = bounds.height - 40
        for line in lines {
            line.draw(at: NSPoint(x: 30, y: y), withAttributes: attrs)
            y -= 28
        }
    }
}

private final class OCRColumnTextView: NSView {
    let columns: [String]

    init(frame: NSRect, columns: [String]) {
        self.columns = columns
        super.init(frame: frame)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.black,
        ]

        let columnWidth = bounds.width / CGFloat(columns.count)
        for (i, column) in columns.enumerated() {
            let lines = column.components(separatedBy: "\n")
            let x = CGFloat(i) * columnWidth + 20
            var y = bounds.height - 40
            for line in lines {
                line.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
                y -= 26
            }
        }
    }
}

private final class OCRTextAndFigureView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor.black,
        ]

        "OCR Mixed Content Test".draw(at: NSPoint(x: 40, y: bounds.height - 50), withAttributes: textAttrs)
        "Text above the figure".draw(at: NSPoint(x: 40, y: bounds.height - 85), withAttributes: textAttrs)

        NSColor.systemBlue.setFill()
        NSRect(x: 60, y: bounds.height / 2 - 50, width: bounds.width - 120, height: 80).fill()

        "Text below the figure".draw(at: NSPoint(x: 40, y: 80), withAttributes: textAttrs)
    }
}

private final class OCRScrollingTextView: NSView {
    let paragraphs: [String]

    init(frame: NSRect, paragraphs: [String]) {
        self.paragraphs = paragraphs
        super.init(frame: frame)

        // Create a scroll view with a text view containing all paragraphs.
        // The text content is taller than the frame, so a scrollbar appears.
        let scrollView = NSScrollView(frame: bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: NSRect(origin: .zero, size: CGSize(width: frame.width - 20, height: 0)))
        textView.isEditable = false
        textView.isSelectable = false
        textView.backgroundColor = .white
        textView.textContainerInset = NSSize(width: 15, height: 15)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        // Build attributed string with large font and spacing between paragraphs
        let fullText = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 18, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 20

        for (i, paragraph) in paragraphs.enumerated() {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle,
            ]
            fullText.append(NSAttributedString(string: paragraph, attributes: attrs))
            if i < paragraphs.count - 1 {
                fullText.append(NSAttributedString(string: "\n\n", attributes: attrs))
            }
        }

        textView.textStorage?.setAttributedString(fullText)

        scrollView.documentView = textView
        addSubview(scrollView)

        // Scroll to top
        textView.scrollToBeginningOfDocument(nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

private final class OCRParagraphsView: NSView {
    let paragraphs: [String]

    init(frame: NSRect, paragraphs: [String]) {
        self.paragraphs = paragraphs
        super.init(frame: frame)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.black,
        ]

        var y = bounds.height - 40
        for paragraph in paragraphs {
            let lines = paragraph.components(separatedBy: "\n")
            for line in lines {
                line.draw(at: NSPoint(x: 30, y: y), withAttributes: attrs)
                y -= 24
            }
            y -= 20
        }
    }
}
