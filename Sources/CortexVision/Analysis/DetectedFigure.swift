import CoreGraphics
import Foundation

/// A figure detected in a captured image (chart, diagram, photo, table, etc.).
public struct DetectedFigure: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Normalized bounds (0..1) relative to the image, in Vision coordinates (bottom-left origin).
    public let bounds: CGRect
    /// Display label, e.g. "Figure 1".
    public let label: String
    /// The extracted figure as a cropped image. Nil until extraction is performed.
    public let extractedImage: CGImage?
    /// Whether this figure is selected for export.
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        bounds: CGRect,
        label: String,
        extractedImage: CGImage? = nil,
        isSelected: Bool = true
    ) {
        self.id = id
        self.bounds = bounds
        self.label = label
        self.extractedImage = extractedImage
        self.isSelected = isSelected
    }

    /// Creates a label from a zero-based index: 0 → "Figure 1", 2 → "Figure 3".
    public static func label(for index: Int) -> String {
        "Figure \(index + 1)"
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

    /// The area of the bounds (normalized, 0..1).
    public var area: CGFloat {
        bounds.width * bounds.height
    }
}

/// The result of figure detection on a single image.
public struct FigureDetectionResult: Equatable, Sendable {
    public let figures: [DetectedFigure]

    public init(figures: [DetectedFigure]) {
        self.figures = figures
    }

    /// Only figures that are selected for export.
    public var selectedFigures: [DetectedFigure] {
        figures.filter(\.isSelected)
    }

    /// Empty result with no detected figures.
    public static let empty = FigureDetectionResult(figures: [])
}

// MARK: - Multi-Pass Pipeline Types

/// Source of a figure candidate detection.
public enum CandidateSource: Equatable, Sendable {
    /// Detected by attention-based saliency (visually interesting region).
    case saliency
    /// Detected by instance mask (foreground subject like person/object).
    case instanceMask
    /// Promoted subject not covered by saliency.
    case promoted
}

/// Evidence supporting a figure candidate.
public enum EvidenceType: Hashable, Sendable {
    /// Region was marked as salient by Vision attention API.
    case salient
    /// Instance mask detected a foreground subject in this region.
    case hasSubject
    /// Region has high color variance (visual complexity).
    case highVariance
    /// Region pixels differ significantly from page background.
    case distinctFromBackground
}

/// Pixel-level profile of a figure candidate's content and edges.
/// Computed once in Pass 1 and used throughout subsequent passes.
public struct PixelProfile: Equatable, Sendable {
    /// Average background color of the page (sampled from corners/edges).
    public let backgroundRGB: (r: Double, g: Double, b: Double)
    /// Average brightness of the background.
    public var backgroundBrightness: Double {
        (backgroundRGB.r + backgroundRGB.g + backgroundRGB.b) / 3.0
    }
    /// Color variance of the interior (excluding text regions).
    public let interiorVariance: Double
    /// Contrast between the figure edge and background, per direction.
    /// Higher = sharper boundary, easier to detect.
    public let edgeContrast: [ExpansionEdge: Double]

    public init(
        backgroundRGB: (r: Double, g: Double, b: Double),
        interiorVariance: Double,
        edgeContrast: [ExpansionEdge: Double] = [:]
    ) {
        self.backgroundRGB = backgroundRGB
        self.interiorVariance = interiorVariance
        self.edgeContrast = edgeContrast
    }

    public static func == (lhs: PixelProfile, rhs: PixelProfile) -> Bool {
        lhs.backgroundRGB.r == rhs.backgroundRGB.r &&
        lhs.backgroundRGB.g == rhs.backgroundRGB.g &&
        lhs.backgroundRGB.b == rhs.backgroundRGB.b &&
        lhs.interiorVariance == rhs.interiorVariance
    }
}

/// A figure candidate that flows through the multi-pass pipeline.
/// Accumulates evidence and confidence across passes before becoming a DetectedFigure.
public struct FigureCandidate: Equatable, Sendable {
    /// Normalized bounds in Vision coordinates (bottom-left origin, 0..1).
    public var bounds: CGRect
    /// How this candidate was initially detected.
    public let source: CandidateSource
    /// Accumulated confidence (0..1). Increased by supporting evidence, decreased by red flags.
    public var confidence: Double
    /// Evidence collected across passes.
    public var evidence: Set<EvidenceType>
    /// Spatial relations to text blocks (computed in Pass 2).
    public var textRelations: [(text: CGRect, relation: TextFigureRelation)]
    /// Pixel-level profile (computed in Pass 1).
    public var pixelProfile: PixelProfile?

    public init(
        bounds: CGRect,
        source: CandidateSource,
        confidence: Double = 0.5,
        evidence: Set<EvidenceType> = [],
        textRelations: [(text: CGRect, relation: TextFigureRelation)] = [],
        pixelProfile: PixelProfile? = nil
    ) {
        self.bounds = bounds
        self.source = source
        self.confidence = confidence
        self.evidence = evidence
        self.textRelations = textRelations
        self.pixelProfile = pixelProfile
    }

    /// Checks if any text block is classified as overlay on this figure.
    public var hasOverlayText: Bool {
        textRelations.contains { $0.relation == .overlayOnFigure }
    }

    /// Text blocks that are adjacent (not overlay, not disjoint).
    public var adjacentTextBounds: [CGRect] {
        textRelations.compactMap { pair in
            switch pair.relation {
            case .adjacentLeft, .adjacentRight, .adjacentAbove, .adjacentBelow:
                return pair.text
            default:
                return nil
            }
        }
    }

    public static func == (lhs: FigureCandidate, rhs: FigureCandidate) -> Bool {
        lhs.bounds == rhs.bounds && lhs.source == rhs.source && lhs.confidence == rhs.confidence
    }
}

// MARK: - Content Map

/// Classification of a cell in the content map grid.
public enum CellType: Equatable, Sendable {
    case background
    case text
    case content
}

/// A coarse grid classification of an image region into background, text, and content cells.
/// Used by the hypothesis-and-validate boundary detection to determine figure boundaries
/// independent of saliency accuracy.
public struct ContentMap: Equatable, Sendable {
    /// Grid dimensions.
    public let gridWidth: Int
    public let gridHeight: Int
    /// Cell classifications, row-major: cells[y][x].
    public let cells: [[CellType]]
    /// The normalized region (Vision coords) this map covers.
    public let region: CGRect

    public init(gridWidth: Int, gridHeight: Int, cells: [[CellType]], region: CGRect) {
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.cells = cells
        self.region = region
    }

    /// Returns the tightest bounding box (in Vision coords) around all `.content` cells.
    /// Returns nil if no content cells exist.
    public func contentBoundingBox() -> CGRect? {
        var minGX = gridWidth, maxGX = -1, minGY = gridHeight, maxGY = -1
        for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                if cells[gy][gx] == .content {
                    minGX = min(minGX, gx)
                    maxGX = max(maxGX, gx)
                    minGY = min(minGY, gy)
                    maxGY = max(maxGY, gy)
                }
            }
        }
        guard maxGX >= 0 else { return nil }

        let cellW = region.width / CGFloat(gridWidth)
        let cellH = region.height / CGFloat(gridHeight)
        // Grid Y=0 is top of region (pixel order), Vision Y increases upward
        let visionMinY = region.maxY - CGFloat(maxGY + 1) * cellH
        let visionMaxY = region.maxY - CGFloat(minGY) * cellH
        return CGRect(
            x: region.minX + CGFloat(minGX) * cellW,
            y: visionMinY,
            width: CGFloat(maxGX - minGX + 1) * cellW,
            height: visionMaxY - visionMinY
        )
    }

    /// Fraction of cells inside `rect` that are `.content`.
    public func contentDensity(in rect: CGRect) -> Double {
        let (total, contentCount) = countCells(in: rect, type: .content)
        return total > 0 ? Double(contentCount) / Double(total) : 0
    }

    /// Fraction of ALL content cells that fall inside `rect`.
    public func contentCoverage(of rect: CGRect) -> Double {
        var totalContent = 0
        var coveredContent = 0
        let cellW = region.width / CGFloat(gridWidth)
        let cellH = region.height / CGFloat(gridHeight)

        for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                if cells[gy][gx] == .content {
                    totalContent += 1
                    let cellCenterX = region.minX + (CGFloat(gx) + 0.5) * cellW
                    let cellCenterY = region.maxY - (CGFloat(gy) + 0.5) * cellH
                    if rect.contains(CGPoint(x: cellCenterX, y: cellCenterY)) {
                        coveredContent += 1
                    }
                }
            }
        }
        return totalContent > 0 ? Double(coveredContent) / Double(totalContent) : 0
    }

    /// Fraction of cells inside `rect` that are NOT `.text`.
    public func textExclusion(in rect: CGRect) -> Double {
        let (total, textCount) = countCells(in: rect, type: .text)
        return total > 0 ? Double(total - textCount) / Double(total) : 1.0
    }

    private func countCells(in rect: CGRect, type: CellType) -> (total: Int, matching: Int) {
        let cellW = region.width / CGFloat(gridWidth)
        let cellH = region.height / CGFloat(gridHeight)
        var total = 0, matching = 0

        for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                let cellCenterX = region.minX + (CGFloat(gx) + 0.5) * cellW
                let cellCenterY = region.maxY - (CGFloat(gy) + 0.5) * cellH
                if rect.contains(CGPoint(x: cellCenterX, y: cellCenterY)) {
                    total += 1
                    if cells[gy][gx] == type { matching += 1 }
                }
            }
        }
        return (total, matching)
    }
}

// MARK: - Boundary Hypothesis

/// Strategy used to generate a boundary hypothesis.
public enum HypothesisStrategy: Equatable, Sendable {
    case contentFit
    case edgeDetection
    case saliencyAnchored
    case subjectAnchored
    case textGap
}

/// A proposed figure boundary with its generating strategy and score.
public struct BoundaryHypothesis: Equatable, Sendable {
    public let bounds: CGRect
    public let strategy: HypothesisStrategy
    public let score: Double

    public init(bounds: CGRect, strategy: HypothesisStrategy, score: Double) {
        self.bounds = bounds
        self.strategy = strategy
        self.score = score
    }
}
