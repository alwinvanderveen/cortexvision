import Testing
import CoreGraphics
import Foundation
@testable import CortexVision

@Suite("ResidueAnalyzer")
struct ResidueAnalyzerTests {

    private func makeImage(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
        return context.makeImage()!
    }

    private func normalizedVisionRect(_ cgContextRect: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        CGRect(
            x: cgContextRect.origin.x / CGFloat(imageWidth),
            y: cgContextRect.origin.y / CGFloat(imageHeight),
            width: cgContextRect.width / CGFloat(imageWidth),
            height: cgContextRect.height / CGFloat(imageHeight)
        )
    }

    @Test("Pass-1 delta increases candidate confidence for split overlay button", .tags(.core))
    func pass1DeltaRaisesConfidence() {
        let width = 200
        let height = 120
        let button = CGRect(x: 48, y: 30, width: 44, height: 24)
        let textGap = CGRect(x: 65, y: 34, width: 10, height: 14)

        let original = makeImage(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))
            ctx.fill(button)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(textGap)
        }

        let pass1Improved = makeImage(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))
            ctx.fill(button)
        }

        let unchanged = original
        let textBounds = [normalizedVisionRect(textGap, imageWidth: width, imageHeight: height)]
        let analyzer = ResidueAnalyzer(minConfidence: 0.45, debug: false)

        let improved = analyzer.analyze(originalCrop: original, pass1Result: pass1Improved, textBounds: textBounds)
        let unchangedResult = analyzer.analyze(originalCrop: original, pass1Result: unchanged, textBounds: textBounds)

        #expect(!improved.candidates.isEmpty, "Improved pass-1 output should produce a candidate")
        #expect(!unchangedResult.debugInfo.isEmpty, "Original geometry should still be analyzable")

        let improvedTop = improved.candidates.max(by: { $0.confidence < $1.confidence })!
        let unchangedTopConfidence = unchangedResult.debugInfo.map(\.confidence).max() ?? 0
        let unchangedTopDelta = unchangedResult.debugInfo.map(\.pass1DeltaScore).max() ?? 0

        #expect(improvedTop.pass1DeltaScore > unchangedTopDelta,
                "Pass 1 should raise the delta score when it fills the text gap")
        #expect(improvedTop.confidence > unchangedTopConfidence,
                "Pass 1 should raise the overall confidence when the overlay becomes more coherent")
        #expect(improvedTop.compactnessGain > 0 || improvedTop.varianceReduction > 0,
                "Pass 1 should improve at least one generic separability signal")
        #expect(improvedTop.textCoverage > 0.5,
                "The candidate should stay anchored to the OCR text region")
    }

    @Test("Candidate geometry stays pixel-precise instead of collapsing to its bbox", .tags(.core))
    func candidateGeometryRemainsPixelPrecise() {
        let width = 200
        let height = 120
        let button = CGRect(x: 48, y: 30, width: 44, height: 24)
        let textGap = CGRect(x: 65, y: 34, width: 10, height: 14)

        let original = makeImage(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))
            ctx.fill(button)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(textGap)
        }

        let pass1Improved = makeImage(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))
            ctx.fill(button)
        }

        let textBounds = [normalizedVisionRect(textGap, imageWidth: width, imageHeight: height)]
        let analyzer = ResidueAnalyzer(minConfidence: 0.45, debug: false)
        let result = analyzer.analyze(originalCrop: original, pass1Result: pass1Improved, textBounds: textBounds)

        #expect(!result.candidates.isEmpty, "Expected a candidate for the synthetic button")
        let candidate = result.candidates.max(by: { $0.pixelCount < $1.pixelCount })!
        let bboxArea = Int(candidate.bounds.width * candidate.bounds.height)

        #expect(candidate.pixelIndices.count == candidate.pixelCount,
                "Candidate should preserve exact component support")
        #expect(candidate.pixelCount < bboxArea,
                "Exact support should remain smaller than the full bbox when text splits the original shape")
        #expect(candidate.dilationRadius >= 3,
                "Component masks should still receive a small dilation radius for pass 2 support")
    }
}
