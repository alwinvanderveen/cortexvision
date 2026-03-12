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

    @Test("DenHaagDoet: detects hero banner as figure", .tags(.figures))
    func denHaagDoetDetection() throws {
        let detector = try DocLayoutDetector()
        let image = try loadTestImage("testEdgesDenHaagDoet")
        let detections = try detector.detect(in: image)

        // The hero banner contains a photo with a person — this should be detected as a figure.
        let figures = detections.filter { LayoutClass.figureClasses.contains($0.layoutClass) }
        #expect(figures.count >= 1, "Expected at least 1 figure, got \(figures.count)")

        if let largestFigure = figures.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) {
            #expect(largestFigure.bounds.width > 0.5, "Hero banner should be wide (>50% of image width)")
            #expect(largestFigure.confidence > 0.3, "Confidence should be reasonable")
            print("DenHaagDoet largest figure: bounds=\(largestFigure.bounds), confidence=\(largestFigure.confidence), class=\(largestFigure.layoutClass)")
        }

        let textRegions = detections.filter { LayoutClass.textClasses.contains($0.layoutClass) }
        print("DenHaagDoet: \(figures.count) figures, \(textRegions.count) text regions")
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

    @Test("Black background with picture: detects figure", .tags(.figures))
    func blackBackgroundDetection() throws {
        let detector = try DocLayoutDetector()
        let image = try loadTestImage("testBlackBackgrondAndPicture")
        let detections = try detector.detect(in: image)

        let figures = detections.filter { LayoutClass.figureClasses.contains($0.layoutClass) }
        #expect(figures.count >= 1, "Expected at least 1 figure on black background, got \(figures.count)")

        print("BlackBackground: \(figures.count) figures, \(detections.count) total detections")
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
}
