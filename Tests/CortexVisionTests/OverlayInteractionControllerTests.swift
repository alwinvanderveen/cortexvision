import Testing
import CoreGraphics
import Foundation
@testable import CortexVision

@Suite("OverlayInteractionController — UC-5a AppViewModel overlay logic")
struct OverlayInteractionControllerTests {

    // MARK: - Helpers

    /// Creates an OCR-like text block tuple in Vision coordinates (bottom-left origin).
    private func textBlock(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)
        -> (id: UUID, text: String, bounds: CGRect) {
        (id: UUID(), text: text, bounds: CGRect(x: x, y: y, width: w, height: h))
    }

    /// Creates a DetectedFigure in Vision coordinates (bottom-left origin).
    private func figure(_ label: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)
        -> DetectedFigure {
        DetectedFigure(bounds: CGRect(x: x, y: y, width: w, height: h), label: label)
    }

    /// Creates a 100x100 single-color CGImage for re-extraction tests.
    private func testImage(width: Int = 100, height: Int = 100) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Fill with red so cropped regions have detectable content
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    // MARK: - TC-5a.11: buildOverlayItems after analysis

    @Test("buildOverlayItems produces grouped text + figure items", .tags(.core))
    func buildOverlayItemsAfterAnalysis() {
        let controller = OverlayInteractionController()

        // Two text blocks close together (should group), one figure
        let textBlocks = [
            textBlock("Hello world", x: 0.1, y: 0.8, w: 0.3, h: 0.03),
            textBlock("Second line", x: 0.1, y: 0.75, w: 0.3, h: 0.03),
        ]
        let figures = [
            figure("Figure 1", x: 0.5, y: 0.2, w: 0.4, h: 0.3),
        ]

        controller.buildOverlayItems(textBlocks: textBlocks, figures: figures)

        let items = controller.overlayItems
        let textItems = items.filter { $0.kind == .text }
        let figureItems = items.filter { $0.kind == .figure }

        // Text blocks should be grouped (2 nearby lines → 1 group)
        #expect(textItems.count >= 1, "Text blocks should be grouped into at least 1 overlay")
        #expect(textItems.count < textBlocks.count, "Grouping should reduce text overlay count")

        // Figure should be present
        #expect(figureItems.count == 1, "Should have 1 figure overlay")
        #expect(figureItems[0].label == "Figure 1")
        #expect(figureItems[0].sourceFigureIndex == 0)

        // Figure bounds should be Y-flipped to SwiftUI coords
        let originalVisionY = figures[0].bounds.origin.y  // 0.2 (bottom-left)
        let expectedSwiftUIY = 1.0 - originalVisionY - figures[0].bounds.height  // 1.0 - 0.2 - 0.3 = 0.5
        #expect(abs(figureItems[0].bounds.origin.y - expectedSwiftUIY) < 0.001)

        // Selection should be cleared
        #expect(controller.selectedOverlayId == nil)
    }

    @Test("buildOverlayItems with empty input produces empty array", .tags(.core))
    func buildOverlayItemsEmpty() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [], figures: [])
        #expect(controller.overlayItems.isEmpty)
    }

    @Test("buildOverlayItems with only figures produces figure-only items", .tags(.core))
    func buildOverlayItemsOnlyFigures() {
        let controller = OverlayInteractionController()
        let figures = [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.3, h: 0.4),
            figure("Figure 2", x: 0.6, y: 0.5, w: 0.2, h: 0.2),
        ]
        controller.buildOverlayItems(textBlocks: [], figures: figures)
        #expect(controller.overlayItems.count == 2)
        #expect(controller.overlayItems.allSatisfy { $0.kind == .figure })
        #expect(controller.overlayItems[0].sourceFigureIndex == 0)
        #expect(controller.overlayItems[1].sourceFigureIndex == 1)
    }

    // MARK: - TC-5a.12: selectOverlay(id:)

    @Test("selectOverlay selects new and deselects previous", .tags(.core))
    func selectOverlay() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [], figures: [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.3, h: 0.3),
            figure("Figure 2", x: 0.6, y: 0.5, w: 0.2, h: 0.2),
        ])

        let id1 = controller.overlayItems[0].id
        let id2 = controller.overlayItems[1].id

        // Select first
        controller.selectOverlay(id: id1)
        #expect(controller.selectedOverlayId == id1)
        #expect(controller.overlayItems[0].isSelected == true)
        #expect(controller.overlayItems[1].isSelected == false)

        // Select second — first should deselect
        controller.selectOverlay(id: id2)
        #expect(controller.selectedOverlayId == id2)
        #expect(controller.overlayItems[0].isSelected == false)
        #expect(controller.overlayItems[1].isSelected == true)

        // Deselect all via nil
        controller.selectOverlay(id: nil)
        #expect(controller.selectedOverlayId == nil)
        #expect(controller.overlayItems[0].isSelected == false)
        #expect(controller.overlayItems[1].isSelected == false)
    }

    // MARK: - TC-5a.13: moveOverlay(id:dx:dy:)

    @Test("moveOverlay shifts bounds correctly, clamped within 0..1", .tags(.core))
    func moveOverlay() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [], figures: [
            figure("Figure 1", x: 0.2, y: 0.3, w: 0.3, h: 0.3),
        ])

        let id = controller.overlayItems[0].id
        let originalX = controller.overlayItems[0].bounds.origin.x

        // Normal move
        controller.moveOverlay(id: id, dx: 0.1, dy: 0.05)
        #expect(abs(controller.overlayItems[0].bounds.origin.x - (originalX + 0.1)) < 0.001)

        // Move far beyond edge — should clamp
        controller.moveOverlay(id: id, dx: 5.0, dy: 5.0)
        let item = controller.overlayItems[0]
        #expect(item.bounds.origin.x >= 0)
        #expect(item.bounds.origin.y >= 0)
        #expect(item.bounds.maxX <= 1.0 + 0.001)
        #expect(item.bounds.maxY <= 1.0 + 0.001)
    }

    // MARK: - TC-5a.14: resizeOverlay(id:to:)

    @Test("resizeOverlay changes bounds, clamped within 0..1", .tags(.core))
    func resizeOverlay() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [], figures: [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.3, h: 0.3),
        ])

        let id = controller.overlayItems[0].id

        // Normal resize
        controller.resizeOverlay(id: id, to: CGRect(x: 0.05, y: 0.1, width: 0.5, height: 0.6))
        #expect(abs(controller.overlayItems[0].bounds.width - 0.5) < 0.001)
        #expect(abs(controller.overlayItems[0].bounds.height - 0.6) < 0.001)

        // Resize beyond edge — should clamp
        controller.resizeOverlay(id: id, to: CGRect(x: 0.9, y: 0.9, width: 0.5, height: 0.5))
        let item = controller.overlayItems[0]
        #expect(item.bounds.maxX <= 1.0 + 0.001)
        #expect(item.bounds.maxY <= 1.0 + 0.001)
    }

    // MARK: - TC-5a.15: deleteSelectedOverlay()

    @Test("deleteSelectedOverlay removes selected item and nils selectedOverlayId", .tags(.core))
    func deleteSelectedOverlay() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [], figures: [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.3, h: 0.3),
            figure("Figure 2", x: 0.6, y: 0.5, w: 0.2, h: 0.2),
        ])

        let id1 = controller.overlayItems[0].id

        // Select and delete
        controller.selectOverlay(id: id1)
        #expect(controller.overlayItems.count == 2)

        controller.deleteSelectedOverlay()
        #expect(controller.overlayItems.count == 1)
        #expect(controller.selectedOverlayId == nil)
        #expect(controller.overlayItems.contains { $0.id == id1 } == false)
    }

    @Test("deleteSelectedOverlay with no selection does nothing", .tags(.core))
    func deleteWithNoSelection() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [], figures: [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.3, h: 0.3),
        ])

        controller.deleteSelectedOverlay()
        #expect(controller.overlayItems.count == 1)
    }

    // MARK: - TC-5a.16: addManualFigureOverlay(bounds:)

    @Test("addManualFigureOverlay creates manual figure and selects it", .tags(.core))
    func addManualFigureOverlay() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [], figures: [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.3, h: 0.3),
        ])

        let bounds = CGRect(x: 0.5, y: 0.4, width: 0.3, height: 0.2)
        controller.addManualFigureOverlay(bounds: bounds)

        #expect(controller.overlayItems.count == 2)

        let manual = controller.overlayItems.last!
        #expect(manual.isManual == true)
        #expect(manual.kind == .figure)
        #expect(manual.label == "Figure 2")  // 1 existing figure + 1 new = "Figure 2"
        #expect(manual.isSelected == true)
        #expect(controller.selectedOverlayId == manual.id)
        #expect(abs(manual.bounds.origin.x - 0.5) < 0.001)
    }

    @Test("addManualFigureOverlay auto-numbers correctly with mixed kinds", .tags(.core))
    func addManualFigureAutoNumbering() {
        let controller = OverlayInteractionController()
        // Start with text + 2 figures
        let textBlocks = [
            textBlock("Some text", x: 0.1, y: 0.9, w: 0.3, h: 0.03),
        ]
        let figures = [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.2, h: 0.2),
            figure("Figure 2", x: 0.5, y: 0.2, w: 0.2, h: 0.2),
        ]
        controller.buildOverlayItems(textBlocks: textBlocks, figures: figures)

        controller.addManualFigureOverlay(bounds: CGRect(x: 0.3, y: 0.5, width: 0.1, height: 0.1))
        let manual = controller.overlayItems.last!
        // 2 existing figures + 1 new → "Figure 3"
        #expect(manual.label == "Figure 3")
    }

    // MARK: - TC-5a.17: toggleOverlayExclusion(id:)

    @Test("toggleOverlayExclusion toggles isExcluded flag", .tags(.core))
    func toggleOverlayExclusion() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [
            textBlock("Hello", x: 0.1, y: 0.8, w: 0.3, h: 0.03),
        ], figures: [])

        let id = controller.overlayItems[0].id

        #expect(controller.overlayItems[0].isExcluded == false)

        controller.toggleOverlayExclusion(id: id)
        #expect(controller.overlayItems[0].isExcluded == true)

        controller.toggleOverlayExclusion(id: id)
        #expect(controller.overlayItems[0].isExcluded == false)
    }

    @Test("toggleOverlayExclusion with unknown ID does nothing", .tags(.core))
    func toggleExclusionUnknownId() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [], figures: [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.3, h: 0.3),
        ])

        // Toggle with random ID — should not crash or change anything
        controller.toggleOverlayExclusion(id: UUID())
        #expect(controller.overlayItems[0].isExcluded == false)
    }

    // MARK: - TC-5a.18: reExtractFigure(for:)

    @Test("reExtractFigure produces cropped image and updates figures", .tags(.core))
    func reExtractFigure() {
        let controller = OverlayInteractionController()
        let image = testImage(width: 200, height: 200)
        let figures = [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.4, h: 0.3),
        ]
        controller.buildOverlayItems(textBlocks: [], figures: figures)

        let id = controller.overlayItems[0].id

        // Move the overlay to a new position
        controller.moveOverlay(id: id, dx: 0.1, dy: 0.05)

        // Re-extract
        let result = controller.reExtractFigure(for: id, from: image, figures: figures)
        #expect(result != nil)
        #expect(result!.croppedImage.width > 0)
        #expect(result!.croppedImage.height > 0)

        // Since this had sourceFigureIndex=0, updatedFigures should be non-nil
        #expect(result!.updatedFigures != nil)
        #expect(result!.updatedFigures!.count == 1)
        #expect(result!.updatedFigures![0].extractedImage != nil)
    }

    @Test("reExtractFigure for manual overlay returns cropped but no updated figures", .tags(.core))
    func reExtractManualFigure() {
        let controller = OverlayInteractionController()
        let image = testImage(width: 200, height: 200)
        controller.buildOverlayItems(textBlocks: [], figures: [])

        // Add manual figure
        controller.addManualFigureOverlay(bounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        let id = controller.overlayItems[0].id

        let result = controller.reExtractFigure(for: id, from: image, figures: [])
        #expect(result != nil)
        #expect(result!.croppedImage.width > 0)
        #expect(result!.updatedFigures == nil)  // Manual overlay has no sourceFigureIndex
    }

    @Test("reExtractFigure for text overlay returns nil", .tags(.core))
    func reExtractTextOverlay() {
        let controller = OverlayInteractionController()
        let image = testImage(width: 200, height: 200)
        controller.buildOverlayItems(textBlocks: [
            textBlock("Hello", x: 0.1, y: 0.8, w: 0.3, h: 0.03),
        ], figures: [])

        let id = controller.overlayItems[0].id
        let result = controller.reExtractFigure(for: id, from: image, figures: [])
        #expect(result == nil)  // Text overlays cannot be re-extracted
    }

    // MARK: - TC-5a.19: Coordinate conversion

    @Test("OverlayItem pixelRect converts normalized to pixel coords correctly", .tags(.core))
    func pixelRectConversion() {
        let item = OverlayItem(
            bounds: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25),
            kind: .figure
        )
        let imageSize = CGSize(width: 1000, height: 800)
        let pixel = item.pixelRect(for: imageSize)

        #expect(abs(pixel.origin.x - 250) < 0.1)
        #expect(abs(pixel.origin.y - 400) < 0.1)
        #expect(abs(pixel.width - 500) < 0.1)
        #expect(abs(pixel.height - 200) < 0.1)
    }

    @Test("OverlayItem normalizedBounds converts pixel to normalized coords", .tags(.core))
    func normalizedBoundsConversion() {
        let pixelRect = CGRect(x: 250, y: 400, width: 500, height: 200)
        let imageSize = CGSize(width: 1000, height: 800)
        let norm = OverlayItem.normalizedBounds(from: pixelRect, imageSize: imageSize)

        #expect(abs(norm.origin.x - 0.25) < 0.001)
        #expect(abs(norm.origin.y - 0.5) < 0.001)
        #expect(abs(norm.width - 0.5) < 0.001)
        #expect(abs(norm.height - 0.25) < 0.001)
    }

    @Test("OverlayItem normalizedBounds with zero image size returns zero", .tags(.core))
    func normalizedBoundsZeroImage() {
        let norm = OverlayItem.normalizedBounds(from: CGRect(x: 10, y: 20, width: 30, height: 40), imageSize: .zero)
        #expect(norm == .zero)
    }

    @Test("Round-trip: normalized → pixel → normalized preserves bounds", .tags(.core))
    func roundTripConversion() {
        let original = CGRect(x: 0.15, y: 0.25, width: 0.6, height: 0.35)
        let imageSize = CGSize(width: 1920, height: 1080)
        let item = OverlayItem(bounds: original, kind: .figure)
        let pixel = item.pixelRect(for: imageSize)
        let restored = OverlayItem.normalizedBounds(from: pixel, imageSize: imageSize)

        #expect(abs(restored.origin.x - original.origin.x) < 0.001)
        #expect(abs(restored.origin.y - original.origin.y) < 0.001)
        #expect(abs(restored.width - original.width) < 0.001)
        #expect(abs(restored.height - original.height) < 0.001)
    }

    // MARK: - Text Exclusion (deelstap 3)

    @Test("sourceTextBlockIds are populated for text overlays", .tags(.core))
    func sourceTextBlockIdsPopulated() {
        let controller = OverlayInteractionController()
        let blockId1 = UUID()
        let blockId2 = UUID()
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: blockId1, text: "Line 1", bounds: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.015)),
            (id: blockId2, text: "Line 2", bounds: CGRect(x: 0.1, y: 0.77, width: 0.3, height: 0.015)),
        ]
        controller.buildOverlayItems(textBlocks: textBlocks, figures: [])

        let textItems = controller.overlayItems.filter { $0.kind == .text }
        #expect(!textItems.isEmpty)
        // All source IDs should be accounted for across all text overlays
        let allSourceIds = textItems.flatMap(\.sourceTextBlockIds)
        #expect(allSourceIds.contains(blockId1))
        #expect(allSourceIds.contains(blockId2))
    }

    @Test("excludedTextBlockIds returns IDs of blocks in excluded text overlays", .tags(.core))
    func excludedTextBlockIds() {
        let controller = OverlayInteractionController()
        let blockId1 = UUID()
        let blockId2 = UUID()
        let blockId3 = UUID()
        // Two groups: blocks 1+2 close together (will group), block 3 far away (separate group)
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: blockId1, text: "Group A line 1", bounds: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.015)),
            (id: blockId2, text: "Group A line 2", bounds: CGRect(x: 0.1, y: 0.77, width: 0.3, height: 0.015)),
            (id: blockId3, text: "Group B line 1", bounds: CGRect(x: 0.1, y: 0.3, width: 0.3, height: 0.015)),
        ]
        controller.buildOverlayItems(textBlocks: textBlocks, figures: [])

        // No exclusions initially
        #expect(controller.excludedTextBlockIds.isEmpty)

        // Find the overlay containing blockId1 and exclude it
        let overlayWithBlock1 = controller.overlayItems.first { $0.sourceTextBlockIds.contains(blockId1) }!
        controller.toggleOverlayExclusion(id: overlayWithBlock1.id)

        let excluded = controller.excludedTextBlockIds
        // blockId1 and blockId2 should be excluded (they're in the same group)
        #expect(excluded.contains(blockId1))
        #expect(excluded.contains(blockId2))
        // blockId3 should NOT be excluded
        #expect(!excluded.contains(blockId3))
    }

    @Test("excludedTextBlockIds is empty for figure-only exclusions", .tags(.core))
    func excludedTextBlockIdsWithFigureExclusion() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [
            textBlock("Some text", x: 0.1, y: 0.8, w: 0.3, h: 0.03),
        ], figures: [
            figure("Figure 1", x: 0.5, y: 0.2, w: 0.3, h: 0.3),
        ])

        // Exclude the figure overlay, not the text
        let figureItem = controller.overlayItems.first { $0.kind == .figure }!
        controller.toggleOverlayExclusion(id: figureItem.id)

        // No text blocks should be excluded
        #expect(controller.excludedTextBlockIds.isEmpty)
    }

    @Test("TextBlockGrouper preserves IDs through grouping with ID overload", .tags(.core))
    func grouperPreservesIds() {
        let grouper = TextBlockGrouper()
        let id1 = UUID()
        let id2 = UUID()
        let blocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: id1, text: "First", bounds: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.02)),
            (id: id2, text: "Second", bounds: CGRect(x: 0.1, y: 0.77, width: 0.5, height: 0.02)),
        ]
        let result = grouper.group(blocks)
        let allIds = result.flatMap(\.sourceTextBlockIds)
        #expect(allIds.contains(id1))
        #expect(allIds.contains(id2))
    }

    // MARK: - UC-5b Deelstap 1: Unified Exclusion

    @Test("TC-5b.1: Exclude figure overlay → excludedFigureIndices contains sourceFigureIndex", .tags(.core))
    func excludeFigureOverlay() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [], figures: [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.3, h: 0.3),
            figure("Figure 2", x: 0.6, y: 0.5, w: 0.2, h: 0.2),
        ])

        let figItem = controller.overlayItems.first { $0.kind == .figure && $0.sourceFigureIndex == 0 }!
        controller.toggleOverlayExclusion(id: figItem.id)

        #expect(controller.excludedFigureIndices.contains(0))
        #expect(!controller.excludedFigureIndices.contains(1))
    }

    @Test("TC-5b.2: Re-include figure overlay → index removed from excludedFigureIndices", .tags(.core))
    func reincludeFigureOverlay() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [], figures: [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.3, h: 0.3),
        ])

        let figItem = controller.overlayItems.first { $0.kind == .figure }!

        // Exclude
        controller.toggleOverlayExclusion(id: figItem.id)
        #expect(controller.excludedFigureIndices.contains(0))

        // Re-include
        controller.toggleOverlayExclusion(id: figItem.id)
        #expect(controller.excludedFigureIndices.isEmpty)
    }

    @Test("TC-5b.3: syncedFigures filters excluded figures correctly", .tags(.core))
    func syncedFiguresExclusion() {
        let controller = OverlayInteractionController()
        let figs = [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.3, h: 0.3),
            figure("Figure 2", x: 0.6, y: 0.5, w: 0.2, h: 0.2),
        ]
        controller.buildOverlayItems(textBlocks: [], figures: figs)

        // Exclude first figure
        let figItem = controller.overlayItems.first { $0.sourceFigureIndex == 0 }!
        controller.toggleOverlayExclusion(id: figItem.id)

        let synced = controller.syncedFigures(from: figs)
        #expect(synced[0].isSelected == false, "Excluded figure should have isSelected=false")
        #expect(synced[1].isSelected == true, "Non-excluded figure should have isSelected=true")
    }

    @Test("TC-5b.4: Multiple figures, one excluded → only excluded is filtered", .tags(.core))
    func syncedFiguresMultiple() {
        let controller = OverlayInteractionController()
        let figs = [
            figure("Figure 1", x: 0.1, y: 0.1, w: 0.2, h: 0.2),
            figure("Figure 2", x: 0.4, y: 0.1, w: 0.2, h: 0.2),
            figure("Figure 3", x: 0.7, y: 0.1, w: 0.2, h: 0.2),
        ]
        controller.buildOverlayItems(textBlocks: [], figures: figs)

        // Exclude middle figure
        let figItem = controller.overlayItems.first { $0.sourceFigureIndex == 1 }!
        controller.toggleOverlayExclusion(id: figItem.id)

        let synced = controller.syncedFigures(from: figs)
        #expect(synced[0].isSelected == true)
        #expect(synced[1].isSelected == false)
        #expect(synced[2].isSelected == true)
    }

    @Test("TC-5b.5: Exclude + re-include round-trip restores original state", .tags(.core))
    func excludeReincludeRoundTrip() {
        let controller = OverlayInteractionController()
        let figs = [
            figure("Figure 1", x: 0.1, y: 0.2, w: 0.3, h: 0.3),
        ]
        controller.buildOverlayItems(textBlocks: [], figures: figs)

        let figItem = controller.overlayItems.first { $0.kind == .figure }!

        // Original state
        let originalSynced = controller.syncedFigures(from: figs)
        #expect(originalSynced[0].isSelected == true)

        // Exclude
        controller.toggleOverlayExclusion(id: figItem.id)
        let excludedSynced = controller.syncedFigures(from: figs)
        #expect(excludedSynced[0].isSelected == false)

        // Re-include
        controller.toggleOverlayExclusion(id: figItem.id)
        let restoredSynced = controller.syncedFigures(from: figs)
        #expect(restoredSynced[0].isSelected == true)
        #expect(controller.excludedFigureIndices.isEmpty)
    }

    // MARK: - BUG-2 Regression: Text overlay resize updates sourceTextBlockIds

    @Test("Resize text overlay updates sourceTextBlockIds based on spatial overlap", .tags(.core))
    func resizeTextOverlayReassociates() {
        let controller = OverlayInteractionController()
        let blockId1 = UUID()
        let blockId2 = UUID()
        let blockId3 = UUID()
        // 3 text blocks far apart so they become separate groups (Vision coords: Y=bottom-left)
        // Large vertical gaps ensure TextBlockGrouper creates separate overlays
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: blockId1, text: "Top line", bounds: CGRect(x: 0.1, y: 0.9, width: 0.5, height: 0.02)),
            (id: blockId2, text: "Middle line", bounds: CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.02)),
            (id: blockId3, text: "Bottom line", bounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.02)),
        ]
        controller.buildOverlayItems(textBlocks: textBlocks, figures: [])

        // Should have 3 separate text overlays due to large gaps
        let textItems = controller.overlayItems.filter { $0.kind == .text }
        #expect(textItems.count == 3, "Large gaps should produce 3 separate text overlays, got \(textItems.count)")

        // Find overlay containing blockId1 (in SwiftUI: y ≈ 1.0 - 0.9 - 0.02 = 0.08)
        let overlayWithBlock1 = controller.overlayItems.first { $0.sourceTextBlockIds.contains(blockId1) }!
        #expect(overlayWithBlock1.sourceTextBlockIds.count == 1)

        // Resize to cover blockId1 AND blockId2's SwiftUI area
        // blockId2 in SwiftUI: y = 1.0 - 0.5 - 0.02 = 0.48
        // So resize to span y=0.05 to y=0.55
        controller.resizeOverlay(id: overlayWithBlock1.id, to: CGRect(x: 0.05, y: 0.05, width: 0.6, height: 0.50))

        let updated = controller.overlayItems.first { $0.id == overlayWithBlock1.id }!

        // Should now contain both blockId1 and blockId2
        #expect(updated.sourceTextBlockIds.contains(blockId1), "Should still contain blockId1")
        #expect(updated.sourceTextBlockIds.contains(blockId2), "Should now also contain blockId2")
        #expect(!updated.sourceTextBlockIds.contains(blockId3), "Should not contain blockId3")
    }

    @Test("Move text overlay updates sourceTextBlockIds", .tags(.core))
    func moveTextOverlayReassociates() {
        let controller = OverlayInteractionController()
        let blockId1 = UUID()
        let blockId2 = UUID()
        // Two text blocks far apart (won't be grouped together)
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: blockId1, text: "Block A", bounds: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.02)),
            (id: blockId2, text: "Block B", bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.02)),
        ]
        controller.buildOverlayItems(textBlocks: textBlocks, figures: [])

        // Find overlay containing blockId1
        let overlayA = controller.overlayItems.first { $0.sourceTextBlockIds.contains(blockId1) }!
        #expect(!overlayA.sourceTextBlockIds.contains(blockId2))

        // Move overlay down to cover blockId2's area instead
        // blockId2 in SwiftUI: y = 1.0 - 0.2 - 0.02 = 0.78
        // overlayA currently at SwiftUI y ≈ 0.18
        // Move dy = +0.60 to reach y ≈ 0.78
        controller.moveOverlay(id: overlayA.id, dx: 0.0, dy: 0.60)

        let movedOverlay = controller.overlayItems.first { $0.id == overlayA.id }!

        // After moving, should now contain blockId2 instead of blockId1
        #expect(movedOverlay.sourceTextBlockIds.contains(blockId2),
                "After moving to blockId2's area, should contain blockId2")
        #expect(!movedOverlay.sourceTextBlockIds.contains(blockId1),
                "After moving away from blockId1's area, should not contain blockId1")
    }

    // MARK: - UC-5b Deelstap 2: Overlay-tekst Classificatie

    @Test("TC-5b.6: buildOverlayItems with overlay classification → text gets overlay classification", .tags(.core))
    func overlayTextClassification() {
        let controller = OverlayInteractionController()
        let blockId = UUID()
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: blockId, text: "Text on figure", bounds: CGRect(x: 0.2, y: 0.5, width: 0.3, height: 0.02)),
        ]
        let figs = [figure("Figure 1", x: 0.1, y: 0.2, w: 0.5, h: 0.5)]

        let classifications: [UUID: OverlayInteractionController.TextClassification] = [
            blockId: (classification: .overlay, figureIndex: 0)
        ]

        controller.buildOverlayItems(textBlocks: textBlocks, figures: figs, textClassifications: classifications)

        let textItem = controller.overlayItems.first { $0.sourceTextBlockIds.contains(blockId) }!
        #expect(textItem.textOverlayClassification == .overlay)
    }

    @Test("TC-5b.7: buildOverlayItems with pageText classification → text gets pageText", .tags(.core))
    func pageTextClassification() {
        let controller = OverlayInteractionController()
        let blockId = UUID()
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: blockId, text: "Regular text", bounds: CGRect(x: 0.1, y: 0.9, width: 0.3, height: 0.02)),
        ]
        let figs = [figure("Figure 1", x: 0.1, y: 0.2, w: 0.5, h: 0.3)]

        // No classification for this block → treated as page text
        controller.buildOverlayItems(textBlocks: textBlocks, figures: figs)

        let textItem = controller.overlayItems.first { $0.sourceTextBlockIds.contains(blockId) }!
        // Page text has nil classification (default, grouped via TextBlockGrouper)
        #expect(textItem.textOverlayClassification == nil)
    }

    @Test("TC-5b.8: Overlay-text has associatedFigureOverlayId linked to correct figure", .tags(.core))
    func overlayTextLinkedToFigure() {
        let controller = OverlayInteractionController()
        let blockId = UUID()
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: blockId, text: "Label on photo", bounds: CGRect(x: 0.2, y: 0.4, width: 0.2, height: 0.02)),
        ]
        let figs = [
            figure("Figure 1", x: 0.1, y: 0.1, w: 0.2, h: 0.2),
            figure("Figure 2", x: 0.1, y: 0.3, w: 0.5, h: 0.4),
        ]
        let classifications: [UUID: OverlayInteractionController.TextClassification] = [
            blockId: (classification: .overlay, figureIndex: 1)
        ]

        controller.buildOverlayItems(textBlocks: textBlocks, figures: figs, textClassifications: classifications)

        let textItem = controller.overlayItems.first { $0.sourceTextBlockIds.contains(blockId) }!
        let figure2Overlay = controller.overlayItems.first { $0.sourceFigureIndex == 1 }!
        #expect(textItem.associatedFigureOverlayId == figure2Overlay.id)
    }

    @Test("TC-5b.9: Page-text has no associatedFigureOverlayId", .tags(.core))
    func pageTextNoAssociatedFigure() {
        let controller = OverlayInteractionController()
        let blockId = UUID()
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: blockId, text: "Body text", bounds: CGRect(x: 0.1, y: 0.9, width: 0.3, height: 0.02)),
        ]
        controller.buildOverlayItems(textBlocks: textBlocks, figures: [
            figure("Figure 1", x: 0.5, y: 0.2, w: 0.3, h: 0.3),
        ])

        let textItem = controller.overlayItems.first { $0.sourceTextBlockIds.contains(blockId) }!
        #expect(textItem.associatedFigureOverlayId == nil)
    }

    @Test("TC-5b.10: Overlay-text is not grouped with page-text", .tags(.core))
    func overlayTextNotGroupedWithPageText() {
        let controller = OverlayInteractionController()
        let overlayBlockId = UUID()
        let pageBlockId = UUID()
        // Two text blocks close together — normally would be grouped
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: overlayBlockId, text: "Overlay text", bounds: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.02)),
            (id: pageBlockId, text: "Page text", bounds: CGRect(x: 0.1, y: 0.48, width: 0.3, height: 0.02)),
        ]
        let figs = [figure("Figure 1", x: 0.05, y: 0.3, w: 0.5, h: 0.4)]
        let classifications: [UUID: OverlayInteractionController.TextClassification] = [
            overlayBlockId: (classification: .overlay, figureIndex: 0)
        ]

        controller.buildOverlayItems(textBlocks: textBlocks, figures: figs, textClassifications: classifications)

        let overlayItem = controller.overlayItems.first { $0.sourceTextBlockIds.contains(overlayBlockId) }!
        let pageItem = controller.overlayItems.first { $0.sourceTextBlockIds.contains(pageBlockId) }!

        // Should be separate overlays
        #expect(overlayItem.id != pageItem.id, "Overlay-text and page-text should be separate overlays")
        #expect(overlayItem.textOverlayClassification == .overlay)
        #expect(pageItem.textOverlayClassification == nil)
    }

    @Test("TC-5b.11: Exclude overlay-text → excludedTextBlockIds contains its source IDs", .tags(.core))
    func excludeOverlayText() {
        let controller = OverlayInteractionController()
        let overlayBlockId = UUID()
        let pageBlockId = UUID()
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: overlayBlockId, text: "Text on fig", bounds: CGRect(x: 0.2, y: 0.5, width: 0.2, height: 0.02)),
            (id: pageBlockId, text: "Body text", bounds: CGRect(x: 0.1, y: 0.9, width: 0.3, height: 0.02)),
        ]
        let classifications: [UUID: OverlayInteractionController.TextClassification] = [
            overlayBlockId: (classification: .overlay, figureIndex: 0)
        ]
        controller.buildOverlayItems(
            textBlocks: textBlocks,
            figures: [figure("Figure 1", x: 0.1, y: 0.3, w: 0.5, h: 0.4)],
            textClassifications: classifications
        )

        let overlayItem = controller.overlayItems.first { $0.sourceTextBlockIds.contains(overlayBlockId) }!
        controller.toggleOverlayExclusion(id: overlayItem.id)

        #expect(controller.excludedTextBlockIds.contains(overlayBlockId))
        #expect(!controller.excludedTextBlockIds.contains(pageBlockId))
    }

    @Test("TC-5b.12: Text without figures → all classifications are nil (pageText)", .tags(.core))
    func textWithoutFiguresAllPageText() {
        let controller = OverlayInteractionController()
        controller.buildOverlayItems(textBlocks: [
            textBlock("Line 1", x: 0.1, y: 0.8, w: 0.3, h: 0.02),
            textBlock("Line 2", x: 0.1, y: 0.5, w: 0.3, h: 0.02),
        ], figures: [])

        let textItems = controller.overlayItems.filter { $0.kind == .text }
        #expect(textItems.allSatisfy { $0.textOverlayClassification == nil })
        #expect(textItems.allSatisfy { $0.associatedFigureOverlayId == nil })
    }

    @Test("Multiple overlay-text blocks on same figure are grouped into one overlay", .tags(.core))
    func overlayTextGroupedPerFigure() {
        let controller = OverlayInteractionController()
        let blockId1 = UUID()
        let blockId2 = UUID()
        let blockId3 = UUID()
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: blockId1, text: "Title on photo", bounds: CGRect(x: 0.2, y: 0.6, width: 0.3, height: 0.02)),
            (id: blockId2, text: "Subtitle on photo", bounds: CGRect(x: 0.2, y: 0.55, width: 0.3, height: 0.02)),
            (id: blockId3, text: "Body text below", bounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.02)),
        ]
        let figs = [figure("Figure 1", x: 0.1, y: 0.4, w: 0.6, h: 0.5)]
        let classifications: [UUID: OverlayInteractionController.TextClassification] = [
            blockId1: (classification: .overlay, figureIndex: 0),
            blockId2: (classification: .edgeOverlay, figureIndex: 0),
        ]

        controller.buildOverlayItems(textBlocks: textBlocks, figures: figs, textClassifications: classifications)

        // Should have 1 page-text overlay, 1 figure overlay, 1 grouped overlay-text overlay
        let overlayTextItems = controller.overlayItems.filter { $0.textOverlayClassification != nil }
        #expect(overlayTextItems.count == 1, "Two overlay-text blocks on same figure should produce 1 overlay, got \(overlayTextItems.count)")

        let grouped = overlayTextItems[0]
        #expect(grouped.sourceTextBlockIds.contains(blockId1))
        #expect(grouped.sourceTextBlockIds.contains(blockId2))
        #expect(!grouped.sourceTextBlockIds.contains(blockId3))
        // Strongest classification wins: overlay > edgeOverlay
        #expect(grouped.textOverlayClassification == .overlay)
    }

    @Test("Overlay-text on different figures produces separate overlays", .tags(.core))
    func overlayTextSeparatePerFigure() {
        let controller = OverlayInteractionController()
        let blockId1 = UUID()
        let blockId2 = UUID()
        let textBlocks: [(id: UUID, text: String, bounds: CGRect)] = [
            (id: blockId1, text: "Text on fig 1", bounds: CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.02)),
            (id: blockId2, text: "Text on fig 2", bounds: CGRect(x: 0.6, y: 0.8, width: 0.2, height: 0.02)),
        ]
        let figs = [
            figure("Figure 1", x: 0.05, y: 0.7, w: 0.4, h: 0.2),
            figure("Figure 2", x: 0.55, y: 0.7, w: 0.4, h: 0.2),
        ]
        let classifications: [UUID: OverlayInteractionController.TextClassification] = [
            blockId1: (classification: .overlay, figureIndex: 0),
            blockId2: (classification: .overlay, figureIndex: 1),
        ]

        controller.buildOverlayItems(textBlocks: textBlocks, figures: figs, textClassifications: classifications)

        let overlayTextItems = controller.overlayItems.filter { $0.textOverlayClassification != nil }
        #expect(overlayTextItems.count == 2, "Text on different figures should produce 2 separate overlays")

        let fig1Overlay = controller.overlayItems.first { $0.sourceFigureIndex == 0 }!
        let fig2Overlay = controller.overlayItems.first { $0.sourceFigureIndex == 1 }!
        let text1 = overlayTextItems.first { $0.sourceTextBlockIds.contains(blockId1) }!
        let text2 = overlayTextItems.first { $0.sourceTextBlockIds.contains(blockId2) }!

        #expect(text1.associatedFigureOverlayId == fig1Overlay.id)
        #expect(text2.associatedFigureOverlayId == fig2Overlay.id)
    }
}
