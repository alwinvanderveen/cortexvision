import CoreGraphics
import Foundation

/// Manages interactive overlay items: selection, move, resize, delete, add, exclusion, re-extraction.
///
/// Extracted from AppViewModel to keep overlay logic testable without SwiftUI dependency.
/// AppViewModel delegates all overlay mutations to this controller.
public final class OverlayInteractionController {

    // MARK: - State

    public private(set) var overlayItems: [OverlayItem] = []
    public private(set) var selectedOverlayId: UUID?

    /// Original text blocks stored for re-association after overlay resize.
    /// Bounds are in SwiftUI coordinates (top-left origin, normalized 0..1).
    private var textBlocksSwiftUI: [(id: UUID, bounds: CGRect)] = []

    private let textBlockGrouper: TextBlockGrouper

    public init(textBlockGrouper: TextBlockGrouper = TextBlockGrouper()) {
        self.textBlockGrouper = textBlockGrouper
    }

    // MARK: - Build Overlays from Analysis Results

    /// Builds interactive overlay items from OCR text blocks and detected figures.
    ///
    /// Text blocks are grouped into logical regions via `TextBlockGrouper`.
    /// Figure bounds are Y-flipped from Vision coordinates (bottom-left origin)
    /// to SwiftUI coordinates (top-left origin).
    ///
    /// - Parameters:
    ///   - textBlocks: OCR text blocks with bounds in Vision coordinates.
    ///   - figures: Detected figures with bounds in Vision coordinates.
    /// Text block classifications by text block ID. Set during buildOverlayItems.
    /// Maps text block UUID → (classification, figureIndex).
    public typealias TextClassification = (classification: TextOverlayClassification, figureIndex: Int?)

    public func buildOverlayItems(
        textBlocks: [(id: UUID, text: String, bounds: CGRect)],
        figures: [DetectedFigure],
        textClassifications: [UUID: TextClassification] = [:]
    ) {
        // Store text blocks in SwiftUI coords for re-association after resize
        textBlocksSwiftUI = textBlocks.map { block in
            (id: block.id, bounds: CGRect(
                x: block.bounds.origin.x,
                y: 1.0 - block.bounds.origin.y - block.bounds.height,
                width: block.bounds.width,
                height: block.bounds.height
            ))
        }

        // Separate page-text from overlay-text based on classifications
        var pageTextBlocks: [(id: UUID, text: String, bounds: CGRect)] = []
        var overlayTextBlocks: [(id: UUID, text: String, bounds: CGRect, classification: TextOverlayClassification, figureIndex: Int?)] = []

        for block in textBlocks {
            if let cls = textClassifications[block.id] {
                switch cls.classification {
                case .overlay, .edgeOverlay:
                    overlayTextBlocks.append((id: block.id, text: block.text, bounds: block.bounds, classification: cls.classification, figureIndex: cls.figureIndex))
                case .pageText, .uncertain:
                    pageTextBlocks.append(block)
                }
            } else {
                pageTextBlocks.append(block)
            }
        }

        // Group only page-text blocks into logical regions
        let pageTextOverlays = textBlockGrouper.group(pageTextBlocks)

        // Create figure overlay items (with SwiftUI Y-flip)
        let figureOverlays = figures.enumerated().map { index, figure in
            OverlayItem(
                bounds: CGRect(
                    x: figure.bounds.origin.x,
                    y: 1.0 - figure.bounds.origin.y - figure.bounds.height,
                    width: figure.bounds.width,
                    height: figure.bounds.height
                ),
                kind: .figure,
                label: figure.label,
                sourceFigureIndex: index
            )
        }

        // Group overlay-text blocks per figure into a single overlay item per figure.
        var overlayTextByFigure: [Int: [(id: UUID, text: String, bounds: CGRect, classification: TextOverlayClassification)]] = [:]
        for block in overlayTextBlocks {
            let figIdx = block.figureIndex ?? -1
            overlayTextByFigure[figIdx, default: []].append(
                (id: block.id, text: block.text, bounds: block.bounds, classification: block.classification)
            )
        }

        let overlayTextItems: [OverlayItem] = overlayTextByFigure.compactMap { figIdx, blocks in
            guard !blocks.isEmpty else { return nil }
            // Union bounds of all text blocks on this figure (Vision coords → SwiftUI)
            var unionBounds = blocks[0].bounds
            for b in blocks.dropFirst() {
                unionBounds = unionBounds.union(b.bounds)
            }
            let swiftuiBounds = CGRect(
                x: unionBounds.origin.x,
                y: 1.0 - unionBounds.origin.y - unionBounds.height,
                width: unionBounds.width,
                height: unionBounds.height
            )
            let combinedText = blocks.map(\.text).joined(separator: " ")
            let figOverlayId = figIdx >= 0
                ? figureOverlays.first { $0.sourceFigureIndex == figIdx }?.id
                : nil
            // Use the strongest classification (overlay > edgeOverlay)
            let cls: TextOverlayClassification = blocks.contains(where: { $0.classification == .overlay })
                ? .overlay : .edgeOverlay
            return OverlayItem(
                bounds: swiftuiBounds,
                kind: .text,
                label: String(combinedText.prefix(40)),
                sourceTextBlockIds: blocks.map(\.id),
                textOverlayClassification: cls,
                associatedFigureOverlayId: figOverlayId
            )
        }

        overlayItems = pageTextOverlays + figureOverlays + overlayTextItems
        selectedOverlayId = nil
    }

    // MARK: - Selection

    /// Select an overlay by ID. Deselects the previously selected overlay.
    public func selectOverlay(id: UUID?) {
        // Deselect previous
        if let prevId = selectedOverlayId,
           let prevIdx = overlayItems.firstIndex(where: { $0.id == prevId }) {
            overlayItems[prevIdx].isSelected = false
        }
        // Select new
        selectedOverlayId = id
        if let newId = id,
           let newIdx = overlayItems.firstIndex(where: { $0.id == newId }) {
            overlayItems[newIdx].isSelected = true
        }
    }

    // MARK: - Move & Resize

    /// Move an overlay by a normalized delta.
    public func moveOverlay(id: UUID, dx: CGFloat, dy: CGFloat) {
        guard let idx = overlayItems.firstIndex(where: { $0.id == id }) else { return }
        overlayItems[idx].move(dx: dx, dy: dy)
        if overlayItems[idx].kind == .text {
            reassociateTextBlocks(at: idx)
        }
    }

    /// Resize an overlay to new bounds.
    public func resizeOverlay(id: UUID, to newBounds: CGRect) {
        guard let idx = overlayItems.firstIndex(where: { $0.id == id }) else { return }
        overlayItems[idx].resize(to: newBounds)
        if overlayItems[idx].kind == .text {
            reassociateTextBlocks(at: idx)
        }
    }

    /// Re-associates text blocks with a text overlay based on spatial intersection.
    /// A text block belongs to this overlay if ≥50% of its area intersects.
    private func reassociateTextBlocks(at index: Int) {
        let overlayBounds = overlayItems[index].bounds
        overlayItems[index].sourceTextBlockIds = textBlocksSwiftUI.compactMap { block in
            let intersection = overlayBounds.intersection(block.bounds)
            guard !intersection.isEmpty else { return nil }
            let blockArea = block.bounds.width * block.bounds.height
            guard blockArea > 0 else { return nil }
            let overlapFraction = (intersection.width * intersection.height) / blockArea
            return overlapFraction >= 0.5 ? block.id : nil
        }
    }

    // MARK: - Delete

    /// Delete the selected overlay.
    public func deleteSelectedOverlay() {
        guard let id = selectedOverlayId else { return }
        overlayItems.removeAll { $0.id == id }
        selectedOverlayId = nil
    }

    // MARK: - Exclusion

    /// Toggle exclusion state of an overlay (include/exclude from export).
    public func toggleOverlayExclusion(id: UUID) {
        guard let idx = overlayItems.firstIndex(where: { $0.id == id }) else { return }
        overlayItems[idx].isExcluded.toggle()
    }

    /// IDs of TextBlocks that belong to excluded text overlays.
    public var excludedTextBlockIds: Set<UUID> {
        var ids = Set<UUID>()
        for item in overlayItems where item.kind == .text && item.isExcluded {
            ids.formUnion(item.sourceTextBlockIds)
        }
        return ids
    }

    /// IDs of TextBlocks that are covered by a non-excluded text overlay.
    /// Only these text blocks should be shown in the results panel.
    /// Text blocks not covered by any overlay (e.g. after resize) are excluded.
    public var includedTextBlockIds: Set<UUID> {
        var ids = Set<UUID>()
        for item in overlayItems where item.kind == .text && !item.isExcluded {
            ids.formUnion(item.sourceTextBlockIds)
        }
        return ids
    }

    /// Indices of figures whose overlay is excluded. Used to derive export selection state.
    public var excludedFigureIndices: Set<Int> {
        var indices = Set<Int>()
        for item in overlayItems where item.kind == .figure && item.isExcluded {
            if let idx = item.sourceFigureIndex {
                indices.insert(idx)
            }
        }
        return indices
    }

    /// Returns figures with isSelected adjusted to reflect overlay exclusion state.
    /// Excluded overlays → isSelected=false, non-excluded → isSelected=true.
    public func syncedFigures(from figures: [DetectedFigure]) -> [DetectedFigure] {
        let excluded = excludedFigureIndices
        return figures.enumerated().map { index, figure in
            DetectedFigure(
                id: figure.id,
                bounds: figure.bounds,
                label: figure.label,
                extractedImage: figure.extractedImage,
                isSelected: !excluded.contains(index)
            )
        }
    }

    // MARK: - Add Manual Figure

    /// Add a new manually drawn figure overlay. Auto-selects the new overlay.
    public func addManualFigureOverlay(bounds: CGRect) {
        let label = "Figure \(overlayItems.filter { $0.kind == .figure }.count + 1)"
        let item = OverlayItem(
            bounds: bounds,
            kind: .figure,
            label: label,
            isManual: true
        )
        overlayItems.append(item)
        selectOverlay(id: item.id)
    }

    // MARK: - Re-Extract Figure

    /// Re-extracts the figure CGImage for an overlay after it was moved/resized.
    ///
    /// - Parameters:
    ///   - overlayId: The overlay to re-extract.
    ///   - image: The source captured image.
    ///   - figures: The current detected figures array.
    /// - Returns: Updated figures array if the overlay had a sourceFigureIndex, nil otherwise.
    public func reExtractFigure(
        for overlayId: UUID,
        from image: CGImage,
        figures: [DetectedFigure]
    ) -> (croppedImage: CGImage, updatedFigures: [DetectedFigure]?)? {
        guard let idx = overlayItems.firstIndex(where: { $0.id == overlayId }),
              overlayItems[idx].kind == .figure else { return nil }

        let item = overlayItems[idx]
        // Convert SwiftUI bounds to pixel rect
        let pixelRect = CGRect(
            x: item.bounds.origin.x * CGFloat(image.width),
            y: item.bounds.origin.y * CGFloat(image.height),
            width: item.bounds.width * CGFloat(image.width),
            height: item.bounds.height * CGFloat(image.height)
        )
        let clamped = pixelRect.intersection(
            CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        guard !clamped.isEmpty, let cropped = image.cropping(to: clamped) else { return nil }

        // Update the figure result if this was an auto-detected figure
        if let figIdx = item.sourceFigureIndex, figIdx < figures.count {
            var updatedFigures = figures
            // Convert SwiftUI bounds back to Vision bounds
            let visionBounds = CGRect(
                x: item.bounds.origin.x,
                y: 1.0 - item.bounds.origin.y - item.bounds.height,
                width: item.bounds.width,
                height: item.bounds.height
            )
            updatedFigures[figIdx] = DetectedFigure(
                id: figures[figIdx].id,
                bounds: visionBounds,
                label: figures[figIdx].label,
                extractedImage: cropped,
                isSelected: figures[figIdx].isSelected
            )
            return (croppedImage: cropped, updatedFigures: updatedFigures)
        }

        return (croppedImage: cropped, updatedFigures: nil)
    }
}
