import CoreGraphics
import Foundation

/// Sorts text blocks into reading order with automatic column detection.
///
/// For single-column layouts: top-to-bottom, left-to-right within each line.
/// For multi-column layouts: each column is read top-to-bottom, columns ordered left-to-right.
/// Full-width blocks (spanning across column boundaries) are placed before column content.
public enum ReadingOrderSorter {
    /// Sort text blocks into reading order.
    ///
    /// - Parameter blocks: Unordered text blocks with normalized bounds (0..1).
    /// - Returns: Text blocks sorted in reading order.
    public static func sort(_ blocks: [TextBlock]) -> [TextBlock] {
        guard blocks.count > 1 else { return blocks }

        // Sort by vertical center: Vision uses bottom-left origin (y=0 at bottom),
        // so higher midY = higher on screen = should be read first → sort descending.
        let sorted = blocks.sorted { $0.bounds.midY > $1.bounds.midY }

        // Cluster into bands: blocks on the same visual line
        let bands = clusterIntoBands(sorted)

        // Try column detection: if blocks form distinct columns, read per column
        if let boundary = detectColumnBoundary(bands: bands) {
            return sortByColumns(blocks: blocks, boundary: boundary)
        }

        // Single column: sort within each band by X position (left to right)
        return bands.flatMap { band in
            band.sorted { $0.bounds.minX < $1.bounds.minX }
        }
    }

    // MARK: - Y-Band Clustering

    private static func clusterIntoBands(_ sorted: [TextBlock]) -> [[TextBlock]] {
        var bands: [[TextBlock]] = []
        var currentBand: [TextBlock] = []

        for block in sorted {
            if let last = currentBand.last {
                let tolerance = max(last.bounds.height, block.bounds.height) * 0.5
                if abs(block.bounds.midY - last.bounds.midY) <= tolerance {
                    currentBand.append(block)
                    continue
                }
            }
            if !currentBand.isEmpty {
                bands.append(currentBand)
            }
            currentBand = [block]
        }
        if !currentBand.isEmpty {
            bands.append(currentBand)
        }

        return bands
    }

    // MARK: - Column Detection

    /// Detects a column boundary by finding consistent horizontal gaps across Y-bands.
    ///
    /// Returns the X position of the boundary if at least 2 bands have a significant
    /// gap at a consistent horizontal position, indicating a multi-column layout.
    private static func detectColumnBoundary(bands: [[TextBlock]]) -> CGFloat? {
        let multiBands = bands.filter { $0.count > 1 }
        guard multiBands.count >= 2 else { return nil }

        var gapCenters: [CGFloat] = []
        for band in multiBands {
            let sortedByX = band.sorted { $0.bounds.minX < $1.bounds.minX }
            var maxGap: CGFloat = 0
            var maxGapCenter: CGFloat = 0
            for i in 1..<sortedByX.count {
                let gap = sortedByX[i].bounds.minX - sortedByX[i - 1].bounds.maxX
                if gap > maxGap {
                    maxGap = gap
                    maxGapCenter = (sortedByX[i - 1].bounds.maxX + sortedByX[i].bounds.minX) / 2
                }
            }
            // A gap > 5% of normalized width is significant
            if maxGap > 0.05 {
                gapCenters.append(maxGapCenter)
            }
        }

        guard gapCenters.count >= 2 else { return nil }

        // Gap positions must be consistent (within 15% of each other) to indicate true columns
        let avg = gapCenters.reduce(0, +) / CGFloat(gapCenters.count)
        let consistent = gapCenters.allSatisfy { abs($0 - avg) < 0.15 }

        return consistent ? avg : nil
    }

    // MARK: - Column-Aware Sorting

    /// Sorts blocks by column: full-width blocks first, then left column top-to-bottom,
    /// then right column top-to-bottom.
    private static func sortByColumns(blocks: [TextBlock], boundary: CGFloat) -> [TextBlock] {
        var spanning: [TextBlock] = []
        var leftColumn: [TextBlock] = []
        var rightColumn: [TextBlock] = []

        for block in blocks {
            // Block whose bounds span across the column boundary is full-width
            if block.bounds.minX < boundary && block.bounds.maxX > boundary {
                spanning.append(block)
            } else if block.bounds.midX < boundary {
                leftColumn.append(block)
            } else {
                rightColumn.append(block)
            }
        }

        // Sort each group top-to-bottom (descending midY for Vision coords)
        spanning.sort { $0.bounds.midY > $1.bounds.midY }
        leftColumn.sort { $0.bounds.midY > $1.bounds.midY }
        rightColumn.sort { $0.bounds.midY > $1.bounds.midY }

        return spanning + leftColumn + rightColumn
    }
}
