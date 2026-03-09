import CoreGraphics
import Foundation
import Vision

/// Performs OCR on CGImage using the Vision framework.
///
/// Supports English and Dutch text recognition with configurable recognition level.
/// Results are sorted in reading order (top-left to bottom-right).
public final class OCREngine: Sendable {
    public init() {}

    /// Recognize text in the given image.
    ///
    /// - Parameters:
    ///   - image: The image to analyze.
    ///   - languages: Recognition languages (default: English and Dutch).
    ///   - level: Recognition accuracy level (default: `.accurate`).
    /// - Returns: OCR result with text blocks sorted in reading order.
    public func recognizeText(
        in image: CGImage,
        languages: [String] = ["en-US", "nl-NL"],
        level: VNRequestTextRecognitionLevel = .accurate
    ) async throws -> OCRResult {
        let textBlocks = try await performRecognition(image: image, languages: languages, level: level)
        let sorted = ReadingOrderSorter.sort(textBlocks)
        return OCRResult(textBlocks: sorted)
    }

    private func performRecognition(
        image: CGImage,
        languages: [String],
        level: VNRequestTextRecognitionLevel
    ) async throws -> [TextBlock] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let blocks = observations.compactMap { observation -> TextBlock? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }

                    let bounds = observation.boundingBox
                    let words = self.extractWords(from: candidate, observationBounds: bounds)

                    return TextBlock(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        bounds: bounds,
                        words: words
                    )
                }

                continuation.resume(returning: blocks)
            }

            request.recognitionLevel = level
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func extractWords(from candidate: VNRecognizedText, observationBounds: CGRect) -> [RecognizedWord] {
        let text = candidate.string
        let words = text.split(separator: " ")
        var result: [RecognizedWord] = []

        for word in words {
            guard let range = text.range(of: word) else { continue }

            if let rect = try? candidate.boundingBox(for: range) {
                result.append(RecognizedWord(
                    text: String(word),
                    confidence: candidate.confidence,
                    bounds: rect.boundingBox
                ))
            } else {
                // Fallback: use observation bounds for individual words
                result.append(RecognizedWord(
                    text: String(word),
                    confidence: candidate.confidence,
                    bounds: observationBounds
                ))
            }
        }

        return result
    }
}
