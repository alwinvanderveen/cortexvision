import CoreGraphics
import Foundation

/// An interactive overlay item displayed on the preview.
/// Unlike the read-only `AnalysisOverlay`, this model supports selection,
/// repositioning, resizing, and deletion for UC-5a interactive editing.
///
/// Bounds are in SwiftUI coordinates (top-left origin, normalized 0..1).
public struct OverlayItem: Identifiable, Equatable {
    public let id: UUID
    /// Normalized bounds (0..1) relative to the image, in SwiftUI coordinates (top-left origin).
    public var bounds: CGRect
    /// Whether this is a text or figure overlay.
    public let kind: OverlayKind
    /// Display label (e.g. "Figure 1" or first 30 chars of text).
    public var label: String?
    /// Whether this overlay is currently selected for editing.
    public var isSelected: Bool
    /// Index into the source figure array (for figure overlays). Used for re-extraction.
    public let sourceFigureIndex: Int?
    /// Whether this overlay is excluded from export (user toggled it off).
    public var isExcluded: Bool
    /// Whether this overlay was added manually by the user (vs. auto-detected).
    public let isManual: Bool
    /// IDs of the source TextBlocks that were grouped into this overlay (text overlays only).
    /// Updated when the overlay is resized to reflect spatial re-association.
    public var sourceTextBlockIds: [UUID]
    /// For text overlays: classification relative to a figure (overlay, edgeOverlay, pageText, uncertain).
    public let textOverlayClassification: TextOverlayClassification?
    /// For overlay-text: the ID of the figure overlay this text sits on.
    public var associatedFigureOverlayId: UUID?

    public init(
        id: UUID = UUID(),
        bounds: CGRect,
        kind: OverlayKind,
        label: String? = nil,
        isSelected: Bool = false,
        isExcluded: Bool = false,
        sourceFigureIndex: Int? = nil,
        isManual: Bool = false,
        sourceTextBlockIds: [UUID] = [],
        textOverlayClassification: TextOverlayClassification? = nil,
        associatedFigureOverlayId: UUID? = nil
    ) {
        self.id = id
        self.bounds = bounds
        self.kind = kind
        self.label = label
        self.isSelected = isSelected
        self.isExcluded = isExcluded
        self.sourceFigureIndex = sourceFigureIndex
        self.isManual = isManual
        self.textOverlayClassification = textOverlayClassification
        self.associatedFigureOverlayId = associatedFigureOverlayId
        self.sourceTextBlockIds = sourceTextBlockIds
    }

    /// Clamps bounds to the valid range 0..1.
    public mutating func clampBounds() {
        bounds = CGRect(
            x: max(0, min(1.0 - bounds.width, bounds.origin.x)),
            y: max(0, min(1.0 - bounds.height, bounds.origin.y)),
            width: max(0.01, min(1.0, bounds.width)),
            height: max(0.01, min(1.0, bounds.height))
        )
    }

    /// Moves the overlay by a normalized delta, clamping to valid bounds.
    public mutating func move(dx: CGFloat, dy: CGFloat) {
        bounds.origin.x += dx
        bounds.origin.y += dy
        clampBounds()
    }

    /// Resizes the overlay to new bounds, clamping to valid range.
    public mutating func resize(to newBounds: CGRect) {
        bounds = newBounds
        clampBounds()
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

    /// Converts pixel coordinates back to normalized bounds.
    public static func normalizedBounds(from pixelRect: CGRect, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        return CGRect(
            x: pixelRect.origin.x / imageSize.width,
            y: pixelRect.origin.y / imageSize.height,
            width: pixelRect.width / imageSize.width,
            height: pixelRect.height / imageSize.height
        )
    }
}
