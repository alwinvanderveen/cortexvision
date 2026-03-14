import Testing
import AppKit
import CoreGraphics
import Vision
@testable import CortexVision

// MARK: - OverlayTextAnalyzer Classification Tests

@Suite("OverlayTextAnalyzer — Classification")
struct OverlayTextAnalyzerClassificationTests {

    private func loadTestImage(_ name: String) -> CGImage? {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imagePath = projectRoot
            .appendingPathComponent("Image")
            .appendingPathComponent("\(name).png")
        guard let nsImage = NSImage(contentsOf: imagePath),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
    }

    private func pageBgColor(of image: CGImage) -> (r: Double, g: Double, b: Double) {
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (255, 255, 255) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = ctx.data else { return (255, 255, 255) }
        let ptr = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        return FigureDetector.sampleBackgroundColor(ptr: ptr, width: image.width, height: image.height)
    }

    // MARK: - testMultipleImageNews2.png

    @Test("Bottom photo overlay text classified as overlay (sandwiched in photo)",
          .tags(.figures))
    func bottomPhotoOverlayText() async throws {
        guard let image = loadTestImage("testMultipleImageNews2") else {
            Issue.record("Could not load testMultipleImageNews2.png")
            return
        }

        let analyzer = HeuristicOverlayTextAnalyzer(debug: true)
        let bg = pageBgColor(of: image)

        // "Loslopende hond zorgt voor chaos op landingsbaan in Brazilië"
        // at y=0.044, figure spans y=0.000 to y=0.272
        let text = CGRect(x: 0.039, y: 0.044, width: 0.904, height: 0.019)
        let figure = CGRect(x: 0.000, y: 0.000, width: 0.980, height: 0.272)

        let classification = analyzer.classify(text: text, figure: figure, in: image, pageBgColor: bg)

        #expect(classification == .overlay,
                "Text sandwiched in photo should be .overlay, got \(classification)")
    }

    @Test("Top photo headline classified as edgeOverlay (text at photo edge)",
          .tags(.figures))
    func topPhotoHeadlineEdgeOverlay() async throws {
        guard let image = loadTestImage("testMultipleImageNews2") else {
            Issue.record("Could not load testMultipleImageNews2.png")
            return
        }

        let analyzer = HeuristicOverlayTextAnalyzer(debug: true)
        let bg = pageBgColor(of: image)

        // "Oorlog met Iran komt steeds dichterbij voor terughoudend Europa"
        // at y=0.772, figure spans y=0.740 to y=1.000
        let text = CGRect(x: 0.042, y: 0.772, width: 0.754, height: 0.019)
        let figure = CGRect(x: 0.000, y: 0.740, width: 0.985, height: 0.260)

        let classification = analyzer.classify(text: text, figure: figure, in: image, pageBgColor: bg)

        #expect(classification == .edgeOverlay || classification == .overlay,
                "Headline on photo edge should be .edgeOverlay or .overlay, got \(classification)")
    }

    @Test("Bullet point text classified as pageText (on white background)",
          .tags(.figures))
    func bulletPointPageText() async throws {
        guard let image = loadTestImage("testMultipleImageNews2") else {
            Issue.record("Could not load testMultipleImageNews2.png")
            return
        }

        let analyzer = HeuristicOverlayTextAnalyzer(debug: true)
        let bg = pageBgColor(of: image)

        // Bullet point text in the middle of the page (white background)
        // "Chemo slaat aan bij dochter van Dick Advocaat" at y≈0.580
        let text = CGRect(x: 0.000, y: 0.580, width: 0.925, height: 0.013)
        // Figure is the top photo area
        let figure = CGRect(x: 0.000, y: 0.740, width: 0.985, height: 0.260)

        let classification = analyzer.classify(text: text, figure: figure, in: image, pageBgColor: bg)

        // This text doesn't even overlap the figure, should be pageText
        #expect(classification == .pageText,
                "Bullet text on white bg should be .pageText, got \(classification)")
    }

    // MARK: - testMultipeImageNews.png (DocLayout regression guard)

    @Test("DocLayout news page headline: does not cause crop cascade",
          .tags(.figures))
    func docLayoutHeadlineNoCascade() async throws {
        guard let image = loadTestImage("testMultipeImageNews") else {
            Issue.record("Could not load testMultipeImageNews.png")
            return
        }

        let analyzer = HeuristicOverlayTextAnalyzer(debug: true)
        let bg = pageBgColor(of: image)

        // Headline "Live | Italiaanse basis in Irak..." at y≈0.770
        let text = CGRect(x: 0.061, y: 0.770, width: 0.824, height: 0.019)
        let figure = CGRect(x: 0.020, y: 0.731, width: 0.960, height: 0.263)

        let classification = analyzer.classify(text: text, figure: figure, in: image, pageBgColor: bg)

        print("  DocLayout headline classification: \(classification)")

        // The classification should be edgeOverlay or overlay (text on photo).
        // Combined with the PASS4 post-crop validation, this should NOT cause
        // the 46px cascade failure — even if the figure includes whitespace below,
        // the validation fallback prevents autoCrop from destroying the figure.
        #expect(classification != .pageText,
                "Headline on photo should not be classified as pageText — got \(classification)")
    }

    // MARK: - Edge cases

    @Test("Text outside figure classified as pageText",
          .tags(.figures))
    func textOutsideFigure() {
        // Synthetic test: text is completely outside the figure bounds
        let analyzer = HeuristicOverlayTextAnalyzer()

        // Create a minimal 100x100 white image
        guard let ctx = CGContext(
            data: nil, width: 100, height: 100,
            bitsPerComponent: 8, bytesPerRow: 100 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Could not create test context")
            return
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        guard let image = ctx.makeImage() else {
            Issue.record("Could not create test image")
            return
        }

        let text = CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.05)
        let figure = CGRect(x: 0.0, y: 0.5, width: 1.0, height: 0.5)
        let bg = (r: 255.0, g: 255.0, b: 255.0)

        let classification = analyzer.classify(text: text, figure: figure, in: image, pageBgColor: bg)
        #expect(classification == .pageText,
                "Text outside figure should be .pageText, got \(classification)")
    }
}
