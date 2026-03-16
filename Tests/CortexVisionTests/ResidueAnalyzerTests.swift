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

    private func topOriginRect(_ cgContextRect: CGRect, imageHeight: Int) -> CGRect {
        CGRect(
            x: cgContextRect.origin.x,
            y: CGFloat(imageHeight) - cgContextRect.origin.y - cgContextRect.height,
            width: cgContextRect.width,
            height: cgContextRect.height
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

    @Test("TC-5b.49: Low-saturation badge near OCR anchor is still detectable after pass 1", .tags(.core))
    func lowSaturationBadgeRemainsDetectable() {
        let width = 220
        let height = 140
        let badge = CGRect(x: 56, y: 34, width: 52, height: 26)
        let textGap = CGRect(x: 74, y: 39, width: 12, height: 14)

        let original = makeImage(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(gray: 0.32, alpha: 1))
            ctx.fill(badge)
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1))
            ctx.fill(textGap)
        }

        let pass1Improved = makeImage(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(gray: 0.32, alpha: 1))
            ctx.fill(badge)
        }

        let textBounds = [normalizedVisionRect(textGap, imageWidth: width, imageHeight: height)]
        let analyzer = ResidueAnalyzer(minConfidence: 0.45, debug: false)
        let result = analyzer.analyze(originalCrop: original, pass1Result: pass1Improved, textBounds: textBounds)

        #expect(!result.candidates.isEmpty,
                "A low-saturation but coherent badge near the OCR anchor should remain detectable")

        let top = result.candidates.max(by: { $0.confidence < $1.confidence })!
        #expect(top.anchorProximity > 0.5, "The accepted low-saturation badge should stay OCR-anchored")
        #expect(top.textCoverage > 0.4, "The accepted low-saturation badge should still cover the text region")
        #expect(top.pass1DeltaScore > 0.1, "Pass 1 should still contribute evidence for the low-saturation badge")
    }

    @Test("TC-5b.50: Thin strip near OCR anchor is rejected as UI residue", .tags(.core))
    func thinStripNearAnchorIsRejected() {
        let width = 220
        let height = 140
        let strip = CGRect(x: 74, y: 24, width: 8, height: 58)
        let textGap = CGRect(x: 74, y: 44, width: 8, height: 12)

        let original = makeImage(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(gray: 0.32, alpha: 1))
            ctx.fill(strip)
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1))
            ctx.fill(textGap)
        }

        let pass1Improved = makeImage(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(gray: 0.32, alpha: 1))
            ctx.fill(strip)
        }

        let textBounds = [normalizedVisionRect(textGap, imageWidth: width, imageHeight: height)]
        let analyzer = ResidueAnalyzer(minConfidence: 0.45, debug: false)
        let result = analyzer.analyze(originalCrop: original, pass1Result: pass1Improved, textBounds: textBounds)

        #expect(result.candidates.isEmpty,
                "A long thin strip near the OCR anchor should be rejected instead of being treated as a badge/button")
    }

    @Test("TC-5b.51: Remote dark photo blob near text anchor is rejected as residue", .tags(.core))
    func remoteDarkBlobNearAnchorIsRejected() {
        let width = 280
        let height = 180
        let label = CGRect(x: 36, y: 122, width: 88, height: 34)
        let textGap = CGRect(x: 64, y: 130, width: 24, height: 18)
        let remoteBlob = CGRect(x: 42, y: 72, width: 96, height: 36)

        let original = makeImage(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(gray: 0.35, alpha: 1))
            ctx.fill(label)
            ctx.fill(remoteBlob)
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1))
            ctx.fill(textGap)
        }

        let pass1Improved = makeImage(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(gray: 0.35, alpha: 1))
            ctx.fill(label)
            ctx.fill(remoteBlob)
        }

        let textBounds = [normalizedVisionRect(textGap, imageWidth: width, imageHeight: height)]
        let analyzer = ResidueAnalyzer(minConfidence: 0.50, debug: true)
        let result = analyzer.analyze(originalCrop: original, pass1Result: pass1Improved, textBounds: textBounds)
        let remoteBlobTop = topOriginRect(remoteBlob, imageHeight: height)

        let remoteCandidates = result.candidates.filter { candidate in
            candidate.bounds.intersects(remoteBlobTop)
        }
        let localCandidates = result.candidates.filter { candidate in
            candidate.textCoverage > 0.5
        }

        #expect(remoteCandidates.isEmpty,
                "A remote dark photo-like blob should not be accepted just because it shares color/uniformity with the local text background")
        #expect(!localCandidates.isEmpty,
                "The compact local badge should still be accepted so this fixture exercises remote-blob rejection instead of disabling anchor-color expansion outright")

        let remoteDebug = result.debugInfo.filter { debug in
            debug.componentBounds.intersects(remoteBlobTop)
        }
        #expect(!remoteDebug.isEmpty,
                "The remote blob should still be analyzable so the rejection path remains observable")
    }
}
