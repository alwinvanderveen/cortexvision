import Testing
import CoreGraphics
import AppKit
@testable import CortexVision

// MARK: - DocLayout-YOLO Model Tests

@Suite("DocLayout-YOLO — Model Loading & Inference")
struct DocLayoutDetectorTests {

    /// Helper: load a test image from the test bundle resources.
    private func loadTestImage(_ name: String) throws -> CGImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources") else {
            throw DocLayoutError.modelNotFound
        }
        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let image = CGImage(
                pngDataProviderSource: dataProvider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw DocLayoutError.renderFailed
        }
        return image
    }

    @Test("Model loads from bundle resources", .tags(.figures))
    func modelLoads() throws {
        let detector = try DocLayoutDetector()
        _ = detector
    }

    @Test("DenHaagDoet: YOLO model limitation — hero banner not detected as figure", .tags(.figures))
    func denHaagDoetDetection() throws {
        // Known limitation: DocLayout-YOLO does not detect hero banners as figures.
        // The hybrid pipeline (FigureDetector) handles this via Vision saliency fallback.
        // This test documents the model limitation for auditability.
        let detector = try DocLayoutDetector()
        let image = try loadTestImage("testEdgesDenHaagDoet")
        let detections = try detector.detect(in: image)

        let figures = detections.filter { LayoutClass.figureClasses.contains($0.layoutClass) }
        #expect(figures.count == 0, "YOLO model limitation: hero banners are not detected as figures (hybrid pipeline compensates via Vision fallback)")

        let textRegions = detections.filter { LayoutClass.textClasses.contains($0.layoutClass) }
        print("DenHaagDoet YOLO-only: \(figures.count) figures, \(textRegions.count) text regions")
    }

    @Test("Propinion: detects circular photo as figure", .tags(.figures))
    func propinionDetection() throws {
        let detector = try DocLayoutDetector()
        let image = try loadTestImage("testPropinionEdges")
        let detections = try detector.detect(in: image)

        let figures = detections.filter { LayoutClass.figureClasses.contains($0.layoutClass) }
        #expect(figures.count >= 1, "Expected at least 1 figure, got \(figures.count)")

        if let largestFigure = figures.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) {
            let aspect = largestFigure.bounds.width / largestFigure.bounds.height
            #expect(aspect > 0.2 && aspect < 3.0, "Photo should have reasonable aspect ratio, got \(aspect)")
            #expect(largestFigure.confidence > 0.5, "Figure confidence should be high")
            print("Propinion largest figure: bounds=\(largestFigure.bounds), confidence=\(largestFigure.confidence), aspect=\(aspect)")
        }

        let textRegions = detections.filter { LayoutClass.textClasses.contains($0.layoutClass) }
        #expect(textRegions.count >= 1, "Should also detect text regions")
        print("Propinion: \(figures.count) figures, \(textRegions.count) text regions")
    }

    @Test("Black background with picture: YOLO model limitation — not detected", .tags(.figures))
    func blackBackgroundDetection() throws {
        // Known limitation: DocLayout-YOLO does not detect figures on dark/black backgrounds.
        // The hybrid pipeline (FigureDetector) handles this via Vision instance mask fallback.
        // This test documents the model limitation for auditability.
        let detector = try DocLayoutDetector()
        let image = try loadTestImage("testBlackBackgrondAndPicture")
        let detections = try detector.detect(in: image)

        let figures = detections.filter { LayoutClass.figureClasses.contains($0.layoutClass) }
        #expect(figures.count == 0, "YOLO model limitation: figures on black backgrounds are not detected (hybrid pipeline compensates via Vision fallback)")

        print("BlackBackground YOLO-only: \(figures.count) figures, \(detections.count) total detections")
        for d in detections {
            print("  \(d.layoutClass) conf=\(String(format: "%.3f", d.confidence)) bounds=\(d.bounds)")
        }
    }

    @Test("All detections have valid normalized bounds", .tags(.figures))
    func validBounds() throws {
        let detector = try DocLayoutDetector()
        let image = try loadTestImage("testPropinionEdges")
        let detections = try detector.detect(in: image)

        #expect(!detections.isEmpty, "Should have detections to validate")

        for detection in detections {
            #expect(detection.bounds.origin.x >= 0 && detection.bounds.origin.x <= 1,
                    "x should be 0..1, got \(detection.bounds.origin.x)")
            #expect(detection.bounds.origin.y >= 0 && detection.bounds.origin.y <= 1,
                    "y should be 0..1, got \(detection.bounds.origin.y)")
            #expect(detection.bounds.maxX <= 1.001, "maxX should be ≤1, got \(detection.bounds.maxX)")
            #expect(detection.bounds.maxY <= 1.001, "maxY should be ≤1, got \(detection.bounds.maxY)")
            #expect(detection.bounds.width > 0, "width should be >0")
            #expect(detection.bounds.height > 0, "height should be >0")
        }
    }

    @Test("Confidence filtering works", .tags(.figures))
    func confidenceFiltering() throws {
        let detector = try DocLayoutDetector()
        let image = try loadTestImage("testPropinionEdges")

        let lowThreshold = try detector.detect(in: image, confidenceThreshold: 0.1)
        let highThreshold = try detector.detect(in: image, confidenceThreshold: 0.8)

        #expect(lowThreshold.count >= highThreshold.count,
                "Lower threshold should yield >= detections than higher threshold")
    }

    @Test("LayoutClass figure and text sets are disjoint", .tags(.core, .figures))
    func classSetDisjoint() {
        let overlap = LayoutClass.figureClasses.intersection(LayoutClass.textClasses)
        #expect(overlap.isEmpty, "Figure and text class sets should not overlap: \(overlap)")
    }

    @Test("News page with multiple photos: both images detected", .tags(.figures))
    func newsPageMultiplePhotos() async throws {
        let image = try loadTestImage("testMultipeImageNews")

        // Hybrid pipeline should detect both photos
        let engine = OCREngine()
        let ocrResult = try await engine.recognizeText(in: image)
        let figureDetector = FigureDetector()
        let figureResult = try await figureDetector.detectFigures(
            in: image, textBounds: ocrResult.textBlocks.map(\.bounds)
        )

        // Expect at least 2 photos: hero image (top) + Indonesia news image (bottom)
        #expect(figureResult.figures.count >= 2,
                "News page should have at least 2 photos detected, got \(figureResult.figures.count)")

        // Both figures should have extracted images
        for (i, fig) in figureResult.figures.enumerated() {
            #expect(fig.extractedImage != nil, "Figure \(i) should have an extracted image")
            if let img = fig.extractedImage {
                #expect(img.width > 100, "Figure \(i) should have reasonable width, got \(img.width)")
                #expect(img.height > 50, "Figure \(i) should have reasonable height, got \(img.height)")
            }
        }

        // Figures should be in different vertical regions (not overlapping)
        if figureResult.figures.count >= 2 {
            let sorted = figureResult.figures.sorted { $0.bounds.origin.y < $1.bounds.origin.y }
            let gap = sorted[1].bounds.origin.y - (sorted[0].bounds.origin.y + sorted[0].bounds.height)
            #expect(gap > 0.05, "Figures should be in separate vertical regions, gap=\(String(format: "%.3f", gap))")
        }
    }
}
