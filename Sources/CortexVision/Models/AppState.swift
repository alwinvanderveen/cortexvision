import CoreGraphics
import Foundation

/// Represents the current state of the application.
public enum CaptureState: Equatable {
    case idle
    case capturing
    case captured(width: Int, height: Int)
    case analyzing
    case analyzed(wordCount: Int, figureCount: Int)
    case error(String)

    public var statusText: String {
        switch self {
        case .idle:
            return "No capture"
        case .capturing:
            return "Capturing..."
        case .captured(let w, let h):
            return "Captured \(w)×\(h)"
        case .analyzing:
            return "Analyzing..."
        case .analyzed(let words, let figures):
            return "Analyzed · \(words) words · \(figures) figures"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
