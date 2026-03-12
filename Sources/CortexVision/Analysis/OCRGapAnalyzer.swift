import CoreGraphics

/// A vertical gap between text bands that may contain a figure.
public struct TextGap: Equatable, Sendable {
    /// Normalized bounds in Vision coordinates (bottom-left origin, 0..1).
    public let bounds: CGRect

    /// Height of the gap as a fraction of the image (0..1).
    public var heightFraction: CGFloat { bounds.height }
}

/// Analyzes OCR text bounds to find vertical gaps where figures may exist.
///
/// Webpages and documents are structured as alternating horizontal bands of text
/// and visual content. By sorting text blocks vertically and finding the gaps
/// between them, we can identify candidate figure regions without relying on
/// Vision saliency (which is non-deterministic across captures).
public enum OCRGapAnalyzer {

    /// Minimum gap height (fraction of image) to be considered a figure candidate.
    public static let defaultMinimumGapHeight: CGFloat = 0.05

    /// Find vertical gaps between text bands that could contain figures.
    ///
    /// - Parameters:
    ///   - textBounds: OCR text block bounds in Vision coordinates (bottom-left origin).
    ///   - minimumGapHeight: Minimum gap height as fraction of image (default 5%).
    /// - Returns: Gaps sorted by Y position (bottom to top in Vision coordinates).
    public static func findGaps(
        in textBounds: [CGRect],
        minimumGapHeight: CGFloat = defaultMinimumGapHeight
    ) -> [TextGap] {
        guard !textBounds.isEmpty else {
            // No text at all — the entire image could be a figure
            return [TextGap(bounds: CGRect(x: 0, y: 0, width: 1, height: 1))]
        }

        // 1. Project text blocks onto Y axis as intervals (minY, maxY)
        let intervals = textBounds.map { (minY: $0.minY, maxY: $0.maxY) }

        // 2. Sort by minY and merge overlapping/touching intervals
        let merged = mergeIntervals(intervals)

        // 3. Find gaps between merged text bands
        var gaps: [TextGap] = []

        // Gap below first text band (from bottom of image to first text)
        if let first = merged.first, first.minY > minimumGapHeight {
            gaps.append(TextGap(bounds: CGRect(x: 0, y: 0, width: 1, height: first.minY)))
        }

        // Gaps between consecutive text bands
        for i in 0..<(merged.count - 1) {
            let gapMinY = merged[i].maxY
            let gapMaxY = merged[i + 1].minY
            let gapHeight = gapMaxY - gapMinY
            if gapHeight >= minimumGapHeight {
                gaps.append(TextGap(bounds: CGRect(x: 0, y: gapMinY, width: 1, height: gapHeight)))
            }
        }

        // Gap above last text band (from last text to top of image)
        if let last = merged.last, (1.0 - last.maxY) >= minimumGapHeight {
            gaps.append(TextGap(bounds: CGRect(x: 0, y: last.maxY, width: 1, height: 1.0 - last.maxY)))
        }

        return gaps
    }

    /// Merge overlapping or touching Y intervals into consolidated text bands.
    static func mergeIntervals(_ intervals: [(minY: CGFloat, maxY: CGFloat)]) -> [(minY: CGFloat, maxY: CGFloat)] {
        guard !intervals.isEmpty else { return [] }

        let sorted = intervals.sorted { $0.minY < $1.minY }
        var merged: [(minY: CGFloat, maxY: CGFloat)] = [sorted[0]]

        for interval in sorted.dropFirst() {
            if interval.minY <= merged[merged.count - 1].maxY {
                // Overlapping or touching — extend the current band
                merged[merged.count - 1].maxY = max(merged[merged.count - 1].maxY, interval.maxY)
            } else {
                merged.append(interval)
            }
        }

        return merged
    }
}
