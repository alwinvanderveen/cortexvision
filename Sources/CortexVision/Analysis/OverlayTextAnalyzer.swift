import CoreGraphics
import Foundation

// MARK: - Classification

/// Classification of the spatial relationship between a text block and a figure.
/// Used to decide whether text-trimming should be applied.
public enum TextOverlayClassification: Equatable, Sendable {
    /// Text is fully embedded within figure content — content on both sides.
    case overlay
    /// Text is on the edge of a figure — content on one side, figure boundary on the other,
    /// but local pixel analysis confirms the figure extends behind the text.
    case edgeOverlay
    /// Text is on page background, not on figure content.
    case pageText
    /// Insufficient signal to classify with confidence.
    case uncertain
}

// MARK: - Protocol

/// Abstraction for overlay text analysis. Allows replacing the heuristic implementation
/// with a model-assisted variant without changing the pipeline interface.
public protocol OverlayTextAnalyzing: Sendable {
    func classify(
        text: CGRect,
        figure: CGRect,
        in image: CGImage,
        pageBgColor: (r: Double, g: Double, b: Double)
    ) -> TextOverlayClassification

    func filterForTrimming(
        figure: CGRect,
        textBounds: [CGRect],
        image: CGImage,
        pageBgColor: (r: Double, g: Double, b: Double)
    ) -> [CGRect]
}

// MARK: - Heuristic Implementation

/// Local patch-based overlay text analyzer.
///
/// For each text block overlapping a figure, extracts a local pixel patch and uses
/// two independent signals to classify the relationship:
/// 1. **Pixel continuity**: vertical scan lines through the text region measure how many
///    contiguous non-background pixel rows exist above and below the text.
/// 2. **Structural coherence**: the fraction of the text region's background pixels that
///    differ from the page background (indicating the text sits on figure content rather
///    than on the page).
///
/// These signals are combined with figure-edge proximity to distinguish overlay, edgeOverlay,
/// pageText and uncertain.
public struct HeuristicOverlayTextAnalyzer: OverlayTextAnalyzing {

    private let debug: Bool

    public init(debug: Bool = false) {
        if debug {
            self.debug = true
        } else {
            self.debug = ProcessInfo.processInfo.environment["FIGURE_DEBUG"] == "1"
        }
    }

    private func dbg(_ msg: String) {
        if debug { print("[OverlayTextAnalyzer] \(msg)") }
    }

    // MARK: - Public API

    public func classify(
        text: CGRect,
        figure: CGRect,
        in image: CGImage,
        pageBgColor: (r: Double, g: Double, b: Double)
    ) -> TextOverlayClassification {
        let intersection = figure.intersection(text)
        guard !intersection.isNull else { return .pageText }

        let textArea = text.width * text.height
        guard textArea > 0 else { return .pageText }
        let interFraction = (intersection.width * intersection.height) / textArea
        guard interFraction > 0.3 else { return .pageText }

        // For document/page images, the page background is typically light (white/cream/light gray).
        // If the sampled pageBgColor is dark (brightness < 180), it likely picked up figure content
        // rather than the actual page background. Fall back to white in that case.
        let bgBrightness = (pageBgColor.r + pageBgColor.g + pageBgColor.b) / 3.0
        let effectiveBgColor: (r: Double, g: Double, b: Double)
        if bgBrightness < 180 {
            effectiveBgColor = (r: 250, g: 250, b: 250)
        } else {
            effectiveBgColor = pageBgColor
        }

        let imgW = image.width
        let imgH = image.height

        let patchContext = PatchContext(
            text: text,
            figure: figure,
            imageWidth: imgW,
            imageHeight: imgH
        )

        guard let pixelData = extractFullImagePixels(from: image) else {
            return .uncertain
        }

        // --- Signal 1: Vertical continuity scan ---
        let continuity = measureVerticalContinuity(
            patch: patchContext,
            ptr: pixelData.ptr,
            imgW: imgW,
            imgH: imgH,
            pageBgColor: effectiveBgColor
        )

        // --- Signal 2: Structural coherence (pixels behind text) ---
        let coherence = measureStructuralCoherence(
            patch: patchContext,
            ptr: pixelData.ptr,
            imgW: imgW,
            imgH: imgH,
            pageBgColor: effectiveBgColor
        )

        // --- Signal 3: Figure edge proximity ---
        let edgeProximity = measureEdgeProximity(text: text, figure: figure)

        // --- Classification ---
        let classification = combine(
            continuity: continuity,
            coherence: coherence,
            edgeProximity: edgeProximity,
            text: text,
            figure: figure
        )

        dbg("classify text=(\(fmt(text))) → \(classification)  "
            + "continuity(above=\(continuity.aboveCount) below=\(continuity.belowCount) "
            + "cols=\(continuity.columnsWithAbove)/\(continuity.totalColumns)) "
            + "coherence=\(String(format: "%.2f", coherence)) "
            + "edge=\(String(format: "%.3f", edgeProximity.distToNearestEdge)) "
            + "nearEdge=\(edgeProximity.nearEdge?.rawValue ?? "none")")

        return classification
    }

    public func filterForTrimming(
        figure: CGRect,
        textBounds: [CGRect],
        image: CGImage,
        pageBgColor: (r: Double, g: Double, b: Double)
    ) -> [CGRect] {
        return textBounds.filter { text in
            let classification = classify(
                text: text,
                figure: figure,
                in: image,
                pageBgColor: pageBgColor
            )
            // Conservative policy: only trim text that is clearly on the page background.
            return classification == .pageText
        }
    }

    // MARK: - Patch Context

    private struct PatchContext {
        let textPixelRect: PixelRect
        let patchPixelRect: PixelRect
        let sampleColumns: [Int]  // x-coordinates to scan vertically
        let textTopPixelY: Int    // top of text in pixel coords (low Y = top)
        let textBottomPixelY: Int // bottom of text in pixel coords

        init(text: CGRect, figure: CGRect, imageWidth: Int, imageHeight: Int) {
            // Convert text from Vision coords to pixel coords
            let txMin = Int(max(0, text.minX * CGFloat(imageWidth)))
            let txMax = Int(min(CGFloat(imageWidth) - 1, text.maxX * CGFloat(imageWidth)))
            // Vision Y is bottom-up; pixel Y is top-down
            let tyTop = Int(max(0, (1.0 - text.maxY) * CGFloat(imageHeight)))
            let tyBottom = Int(min(CGFloat(imageHeight) - 1, (1.0 - text.minY) * CGFloat(imageHeight)))
            textPixelRect = PixelRect(xMin: txMin, xMax: txMax, yMin: tyTop, yMax: tyBottom)
            textTopPixelY = tyTop
            textBottomPixelY = tyBottom

            // Patch: 3x text height above/below, 1.5x text width left/right
            let textH = tyBottom - tyTop
            let textW = txMax - txMin
            let vPad = max(20, textH * 3)
            let hPad = max(10, textW / 2)
            let pxMin = max(0, txMin - hPad)
            let pxMax = min(imageWidth - 1, txMax + hPad)
            let pyMin = max(0, tyTop - vPad)
            let pyMax = min(imageHeight - 1, tyBottom + vPad)
            patchPixelRect = PixelRect(xMin: pxMin, xMax: pxMax, yMin: pyMin, yMax: pyMax)

            // Adaptive column sampling: scale with text width.
            // Minimum 3 columns, approximately 1 per 30px, capped at 20.
            let colCount = max(3, min(20, textW / 30 + 1))
            let step = max(1, textW / colCount)
            var cols: [Int] = []
            for i in 0..<colCount {
                let x = txMin + step / 2 + step * i
                if x <= txMax { cols.append(x) }
            }
            if cols.isEmpty { cols.append((txMin + txMax) / 2) }
            sampleColumns = cols
        }
    }

    private struct PixelRect {
        let xMin: Int, xMax: Int, yMin: Int, yMax: Int
        var width: Int { xMax - xMin + 1 }
        var height: Int { yMax - yMin + 1 }
    }

    // MARK: - Signal 1: Vertical Continuity

    private struct ContinuityResult {
        let aboveCount: Int       // median contiguous non-bg rows above text across columns
        let belowCount: Int       // median contiguous non-bg rows below text across columns
        let columnsWithAbove: Int // columns with meaningful continuity above
        let columnsWithBelow: Int // columns with meaningful continuity below
        let totalColumns: Int
    }

    private func measureVerticalContinuity(
        patch: PatchContext,
        ptr: UnsafePointer<UInt8>,
        imgW: Int,
        imgH: Int,
        pageBgColor: (r: Double, g: Double, b: Double)
    ) -> ContinuityResult {
        let bgThreshold = 50.0
        // Minimum contiguous non-bg rows to count as "meaningful continuity"
        let minContinuity = max(3, (patch.textBottomPixelY - patch.textTopPixelY) / 2)

        var aboveCounts: [Int] = []
        var belowCounts: [Int] = []

        for x in patch.sampleColumns {
            // Scan upward from text top
            var aboveRun = 0
            for y in stride(from: patch.textTopPixelY - 1, through: patch.patchPixelRect.yMin, by: -1) {
                if isNonBackground(ptr: ptr, x: x, y: y, width: imgW, pageBgColor: pageBgColor, threshold: bgThreshold) {
                    aboveRun += 1
                } else {
                    break
                }
            }
            aboveCounts.append(aboveRun)

            // Scan downward from text bottom
            var belowRun = 0
            for y in (patch.textBottomPixelY + 1)...patch.patchPixelRect.yMax {
                if isNonBackground(ptr: ptr, x: x, y: y, width: imgW, pageBgColor: pageBgColor, threshold: bgThreshold) {
                    belowRun += 1
                } else {
                    break
                }
            }
            belowCounts.append(belowRun)
        }

        let sortedAbove = aboveCounts.sorted()
        let sortedBelow = belowCounts.sorted()
        let medianAbove = sortedAbove.isEmpty ? 0 : sortedAbove[sortedAbove.count / 2]
        let medianBelow = sortedBelow.isEmpty ? 0 : sortedBelow[sortedBelow.count / 2]

        let colsAbove = aboveCounts.filter { $0 >= minContinuity }.count
        let colsBelow = belowCounts.filter { $0 >= minContinuity }.count

        return ContinuityResult(
            aboveCount: medianAbove,
            belowCount: medianBelow,
            columnsWithAbove: colsAbove,
            columnsWithBelow: colsBelow,
            totalColumns: patch.sampleColumns.count
        )
    }

    // MARK: - Signal 2: Structural Coherence

    /// Measures what fraction of sampled pixels in the text region differ from the page background.
    /// High coherence (>0.5) means the text sits on figure content (photo, banner, etc.).
    /// Low coherence (<0.2) means the text sits on page background (white space).
    private func measureStructuralCoherence(
        patch: PatchContext,
        ptr: UnsafePointer<UInt8>,
        imgW: Int,
        imgH: Int,
        pageBgColor: (r: Double, g: Double, b: Double)
    ) -> Double {
        let bgThreshold = 50.0
        let tr = patch.textPixelRect

        // Sample pixels across the text region — adaptively based on text area
        let rowStep = max(1, tr.height / 5)
        let colStep = max(1, tr.width / 15)
        var nonBgCount = 0
        var totalCount = 0

        var y = tr.yMin
        while y <= tr.yMax {
            var x = tr.xMin
            while x <= tr.xMax {
                let off = (y * imgW + x) * 4
                let r = Double(ptr[off])
                let g = Double(ptr[off + 1])
                let b = Double(ptr[off + 2])
                let dist = abs(r - pageBgColor.r) + abs(g - pageBgColor.g) + abs(b - pageBgColor.b)
                if dist > bgThreshold {
                    nonBgCount += 1
                }
                totalCount += 1
                x += colStep
            }
            y += rowStep
        }

        return totalCount > 0 ? Double(nonBgCount) / Double(totalCount) : 0
    }

    // MARK: - Signal 3: Figure Edge Proximity

    private enum FigureEdge: String {
        case top, bottom, left, right
    }

    private struct EdgeProximity {
        let distToNearestEdge: CGFloat  // normalized 0..1 (fraction of figure dimension)
        let nearEdge: FigureEdge?
    }

    private func measureEdgeProximity(text: CGRect, figure: CGRect) -> EdgeProximity {
        guard figure.width > 0, figure.height > 0 else {
            return EdgeProximity(distToNearestEdge: 1.0, nearEdge: nil)
        }

        let distTop = (figure.maxY - text.maxY) / figure.height     // Vision: higher Y = top
        let distBottom = (text.minY - figure.minY) / figure.height
        let distLeft = (text.minX - figure.minX) / figure.width
        let distRight = (figure.maxX - text.maxX) / figure.width

        let distances: [(CGFloat, FigureEdge)] = [
            (distTop, .top), (distBottom, .bottom), (distLeft, .left), (distRight, .right)
        ]

        let nearest = distances.min(by: { $0.0 < $1.0 })
        return EdgeProximity(
            distToNearestEdge: nearest?.0 ?? 1.0,
            nearEdge: nearest?.1
        )
    }

    // MARK: - Classification Logic

    private func combine(
        continuity: ContinuityResult,
        coherence: Double,
        edgeProximity: EdgeProximity,
        text: CGRect,
        figure: CGRect
    ) -> TextOverlayClassification {
        let totalCols = continuity.totalColumns
        guard totalCols > 0 else { return .uncertain }

        let aboveFraction = CGFloat(continuity.columnsWithAbove) / CGFloat(totalCols)
        let belowFraction = CGFloat(continuity.columnsWithBelow) / CGFloat(totalCols)

        // --- overlay: content clearly on both sides ---
        // Majority of columns show continuity above AND below.
        if aboveFraction >= 0.5 && belowFraction >= 0.5 {
            return .overlay
        }

        // --- edgeOverlay: content on one side, figure edge on the other ---
        // Requirements:
        //   1. Strong continuity on at least one side (majority of columns)
        //   2. Text is near the figure edge on the opposite side (<20% of figure dimension)
        //   3. Structural coherence confirms text is on figure content (>0.4)
        //      This prevents false positives from body text near a figure edge.
        let nearEdgeThreshold: CGFloat = 0.20
        let isNearEdge = edgeProximity.distToNearestEdge < nearEdgeThreshold

        if isNearEdge && coherence > 0.4 {
            // Strong continuity on the side OPPOSITE to the near edge
            let hasStrongContinuityOpposite: Bool
            switch edgeProximity.nearEdge {
            case .bottom:
                hasStrongContinuityOpposite = aboveFraction >= 0.5
            case .top:
                hasStrongContinuityOpposite = belowFraction >= 0.5
            case .left:
                // For lateral edges, check vertical continuity on either side
                hasStrongContinuityOpposite = aboveFraction >= 0.5 || belowFraction >= 0.5
            case .right:
                hasStrongContinuityOpposite = aboveFraction >= 0.5 || belowFraction >= 0.5
            case nil:
                hasStrongContinuityOpposite = false
            }

            if hasStrongContinuityOpposite {
                return .edgeOverlay
            }
        }

        // --- pageText: clearly no figure content around the text ---
        // Neither side has meaningful continuity AND coherence is low.
        if aboveFraction < 0.3 && belowFraction < 0.3 && coherence < 0.3 {
            return .pageText
        }

        // --- uncertain: mixed signals ---
        // Some evidence of overlay but not enough for a confident classification.
        // Per conservative policy, uncertain text will NOT be trimmed.
        if coherence > 0.4 || aboveFraction >= 0.3 || belowFraction >= 0.3 {
            return .uncertain
        }

        return .pageText
    }

    // MARK: - Pixel Helpers

    private struct PixelBuffer {
        let ptr: UnsafePointer<UInt8>
        let context: CGContext // keep alive
    }

    private func extractFullImagePixels(from image: CGImage) -> PixelBuffer? {
        let w = image.width
        let h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        return PixelBuffer(ptr: ptr, context: ctx)
    }

    private func isNonBackground(
        ptr: UnsafePointer<UInt8>,
        x: Int, y: Int,
        width: Int,
        pageBgColor: (r: Double, g: Double, b: Double),
        threshold: Double
    ) -> Bool {
        let off = (y * width + x) * 4
        let r = Double(ptr[off])
        let g = Double(ptr[off + 1])
        let b = Double(ptr[off + 2])
        let dist = abs(r - pageBgColor.r) + abs(g - pageBgColor.g) + abs(b - pageBgColor.b)
        return dist > threshold
    }

    private func fmt(_ r: CGRect) -> String {
        String(format: "%.3f %.3f %.3f %.3f", r.minX, r.minY, r.width, r.height)
    }
}
