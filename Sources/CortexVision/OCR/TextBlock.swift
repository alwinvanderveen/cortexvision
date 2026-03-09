import CoreGraphics
import Foundation

/// A single word recognized by OCR with its confidence and position.
public struct RecognizedWord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let confidence: Float
    /// Normalized bounds (0..1) relative to the image.
    public let bounds: CGRect

    public init(id: UUID = UUID(), text: String, confidence: Float, bounds: CGRect) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.bounds = bounds
    }

    /// True if confidence is below the threshold for reliable recognition.
    public var isLowConfidence: Bool {
        confidence < 0.7
    }
}

/// A block of text recognized by OCR, containing one or more words on a single line.
public struct TextBlock: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let confidence: Float
    /// Normalized bounds (0..1) relative to the image.
    public let bounds: CGRect
    public let words: [RecognizedWord]

    public init(id: UUID = UUID(), text: String, confidence: Float, bounds: CGRect, words: [RecognizedWord] = []) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.bounds = bounds
        self.words = words
    }

    /// True if any word in this block has low confidence.
    public var hasLowConfidenceWords: Bool {
        words.contains(where: { $0.isLowConfidence })
    }

    /// Converts normalized bounds to pixel coordinates for a given image size.
    public func pixelRect(for imageSize: CGSize) -> CGRect {
        CGRect(
            x: bounds.origin.x * imageSize.width,
            y: bounds.origin.y * imageSize.height,
            width: bounds.width * imageSize.width,
            height: bounds.height * imageSize.height
        )
    }
}

/// The result of an OCR operation on a single image.
public struct OCRResult: Equatable, Sendable {
    public let textBlocks: [TextBlock]

    public init(textBlocks: [TextBlock]) {
        self.textBlocks = textBlocks
    }

    /// All recognized text joined in reading order.
    public var fullText: String {
        textBlocks.map(\.text).joined(separator: "\n")
    }

    /// Total number of words across all blocks.
    public var wordCount: Int {
        textBlocks.reduce(0) { $0 + $1.words.count }
    }

    /// Empty result with no recognized text.
    public static let empty = OCRResult(textBlocks: [])
}
