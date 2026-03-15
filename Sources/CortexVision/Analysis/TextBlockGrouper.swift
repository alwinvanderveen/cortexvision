import CoreGraphics
import Foundation

/// Groups nearby OCR text blocks into logical text regions.
///
/// Instead of showing one overlay per OCR line (which produces many small boxes),
/// this groups lines that belong to the same paragraph or column into a single
/// overlay item. Grouping is based on vertical proximity and horizontal alignment.
public struct TextBlockGrouper {

    /// Maximum vertical gap (as fraction of average text height) between blocks
    /// to still be considered part of the same group. Default: 1.5 line heights.
    private let maxVerticalGapFactor: CGFloat

    /// Minimum horizontal overlap fraction to consider blocks horizontally aligned.
    /// Default: 0.3 (30% overlap).
    private let minHorizontalOverlap: CGFloat

    public init(
        maxVerticalGapFactor: CGFloat = 1.5,
        minHorizontalOverlap: CGFloat = 0.3
    ) {
        self.maxVerticalGapFactor = maxVerticalGapFactor
        self.minHorizontalOverlap = minHorizontalOverlap
    }

    /// Groups text blocks into logical regions.
    ///
    /// - Parameter textBlocks: OCR text blocks with bounds in Vision coordinates (bottom-left origin).
    /// - Returns: Grouped overlay items with bounds in SwiftUI coordinates (top-left origin).
    public func group(_ textBlocks: [(text: String, bounds: CGRect)]) -> [OverlayItem] {
        let withIds = textBlocks.map { (id: UUID(), text: $0.text, bounds: $0.bounds) }
        return groupWithIds(withIds)
    }

    /// Groups text blocks into logical regions, preserving source TextBlock IDs.
    ///
    /// - Parameter textBlocks: OCR text blocks with IDs and bounds in Vision coordinates (bottom-left origin).
    /// - Returns: Grouped overlay items with `sourceTextBlockIds` populated.
    public func group(_ textBlocks: [(id: UUID, text: String, bounds: CGRect)]) -> [OverlayItem] {
        groupWithIds(textBlocks)
    }

    private func groupWithIds(_ textBlocks: [(id: UUID, text: String, bounds: CGRect)]) -> [OverlayItem] {
        guard !textBlocks.isEmpty else { return [] }

        // Sort by Y descending (top of page first in Vision coords = highest Y)
        let sorted = textBlocks.sorted { $0.bounds.midY > $1.bounds.midY }

        // Average text height for gap threshold
        let avgHeight = sorted.reduce(0.0) { $0 + $1.bounds.height } / CGFloat(sorted.count)
        let maxGap = avgHeight * maxVerticalGapFactor

        // Union-find grouping
        var groupIds = Array(0..<sorted.count)

        func find(_ i: Int) -> Int {
            var root = i
            while groupIds[root] != root { root = groupIds[root] }
            // Path compression
            var node = i
            while groupIds[node] != root {
                let next = groupIds[node]
                groupIds[node] = root
                node = next
            }
            return root
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a)
            let rb = find(b)
            if ra != rb { groupIds[rb] = ra }
        }

        // Group blocks that are vertically close and horizontally overlapping
        for i in 0..<sorted.count {
            for j in (i + 1)..<sorted.count {
                let a = sorted[i].bounds
                let b = sorted[j].bounds

                // Vertical gap: distance between bottom of upper block and top of lower block
                let vGap = a.minY - b.maxY  // Vision: a is above b (higher Y)
                guard vGap >= 0, vGap <= maxGap else { continue }

                // Horizontal overlap: fraction of the narrower block that overlaps
                let overlapLeft = max(a.minX, b.minX)
                let overlapRight = min(a.maxX, b.maxX)
                let overlapWidth = max(0, overlapRight - overlapLeft)
                let narrowerWidth = min(a.width, b.width)
                guard narrowerWidth > 0 else { continue }
                let hOverlapFraction = overlapWidth / narrowerWidth

                if hOverlapFraction >= minHorizontalOverlap {
                    union(i, j)
                }
            }
        }

        // Build groups
        var groups: [Int: [Int]] = [:]
        for i in 0..<sorted.count {
            groups[find(i), default: []].append(i)
        }

        // Convert each group to an OverlayItem
        return groups.values.map { indices in
            let members = indices.map { sorted[$0] }

            // Union of all bounds (Vision coords)
            var unionBounds = members[0].bounds
            for m in members.dropFirst() {
                unionBounds = unionBounds.union(m.bounds)
            }

            // Concatenate text (sorted top to bottom = descending Y in Vision)
            let sortedMembers = members.sorted { $0.bounds.midY > $1.bounds.midY }
            let combinedText = sortedMembers.map(\.text).joined(separator: " ")
            let previewLabel = String(combinedText.prefix(40))

            // Convert Vision coords (bottom-left) to SwiftUI coords (top-left)
            let swiftuiBounds = CGRect(
                x: unionBounds.origin.x,
                y: 1.0 - unionBounds.origin.y - unionBounds.height,
                width: unionBounds.width,
                height: unionBounds.height
            )

            return OverlayItem(
                bounds: swiftuiBounds,
                kind: .text,
                label: previewLabel,
                sourceTextBlockIds: members.map(\.id)
            )
        }
        .sorted { $0.bounds.origin.y < $1.bounds.origin.y } // top-to-bottom in SwiftUI
    }
}
