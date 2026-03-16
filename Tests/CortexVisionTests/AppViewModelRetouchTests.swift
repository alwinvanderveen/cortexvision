import Testing
import CoreGraphics
import Foundation
@testable import CortexVision
@testable import CortexVisionApp

@MainActor
@Suite("AppViewModel — Overlay text retouch preview")
struct AppViewModelRetouchTests {

    private struct FakeRetoucher: FigureRetouching {
        let r: UInt8
        let g: UInt8
        let b: UInt8

        func removeText(from image: CGImage, figureBounds: CGRect, textBounds: [CGRect]) -> CGImage? {
            guard !textBounds.isEmpty,
                  let baseCrop = FigurePreviewComposer.cropFigure(from: image, figureBounds: figureBounds),
                  let context = CGContext(
                    data: nil,
                    width: baseCrop.width,
                    height: baseCrop.height,
                    bitsPerComponent: 8,
                    bytesPerRow: baseCrop.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            context.setFillColor(
                CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
            )
            context.fill(CGRect(x: 0, y: 0, width: baseCrop.width, height: baseCrop.height))
            return context.makeImage()
        }
    }

    private func makeSourceImage(width: Int, height: Int, figureBounds: CGRect) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let pixelRect = CGRect(
            x: figureBounds.origin.x * CGFloat(width),
            y: (1.0 - figureBounds.origin.y - figureBounds.height) * CGFloat(height),
            width: figureBounds.width * CGFloat(width),
            height: figureBounds.height * CGFloat(height)
        ).integral
        let cgRect = CGRect(
            x: pixelRect.origin.x,
            y: CGFloat(height) - pixelRect.maxY,
            width: pixelRect.width,
            height: pixelRect.height
        )
        context.setFillColor(CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(cgRect)
        return context.makeImage()!
    }

    private func pixelRGB(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = context.data!.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let flippedY = image.height - 1 - y
        let offset = (flippedY * image.width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2])
    }

    private func configuredViewModel() -> (viewModel: AppViewModel, figureRect: CGRect, figureCenter: CGPoint) {
        let figureBounds = CGRect(x: 0.20, y: 0.25, width: 0.40, height: 0.35)
        let textBounds = CGRect(x: 0.28, y: 0.40, width: 0.14, height: 0.06)
        let sourceImage = makeSourceImage(width: 200, height: 160, figureBounds: figureBounds)
        let figureImage = FigurePreviewComposer.cropFigure(from: sourceImage, figureBounds: figureBounds)
        let figure = DetectedFigure(bounds: figureBounds, label: "Figure 1", extractedImage: figureImage)
        let textBlock = TextBlock(id: UUID(), text: "Video", confidence: 0.99, bounds: textBounds)

        let viewModel = AppViewModel(figureRetoucher: FakeRetoucher(r: 20, g: 40, b: 220))
        viewModel.capturedImage = sourceImage
        viewModel.previewImage = sourceImage
        viewModel.ocrResult = OCRResult(textBlocks: [textBlock])
        viewModel.figureResult = FigureDetectionResult(figures: [figure])
        viewModel.overlayController.buildOverlayItems(
            textBlocks: [(id: textBlock.id, text: textBlock.text, bounds: textBlock.bounds)],
            figures: [figure],
            textClassifications: [textBlock.id: (classification: .overlay, figureIndex: 0)]
        )
        viewModel.overlayItems = viewModel.overlayController.overlayItems

        let figurePixelRect = FigurePreviewComposer.pixelRect(for: figureBounds, in: sourceImage)
        let center = CGPoint(x: figurePixelRect.midX, y: figurePixelRect.midY)
        return (viewModel, figurePixelRect, center)
    }

    private func configuredTwoFigureViewModel() -> (viewModel: AppViewModel, topCenter: CGPoint, bottomCenter: CGPoint) {
        let topBounds = CGRect(x: 0.18, y: 0.62, width: 0.34, height: 0.20)
        let bottomBounds = CGRect(x: 0.20, y: 0.18, width: 0.36, height: 0.24)

        let context = CGContext(
            data: nil,
            width: 220,
            height: 180,
            bitsPerComponent: 8,
            bytesPerRow: 220 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 220, height: 180))

        let topRect = FigurePreviewComposer.pixelRect(
            for: topBounds,
            in: solidImage(width: 220, height: 180, r: 0, g: 0, b: 0)
        )
        let bottomRect = FigurePreviewComposer.pixelRect(
            for: bottomBounds,
            in: solidImage(width: 220, height: 180, r: 0, g: 0, b: 0)
        )
        context.setFillColor(CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: topRect.origin.x, y: CGFloat(180) - topRect.maxY, width: topRect.width, height: topRect.height))
        context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: bottomRect.origin.x, y: CGFloat(180) - bottomRect.maxY, width: bottomRect.width, height: bottomRect.height))
        let sourceImage = context.makeImage()!

        let topFigure = DetectedFigure(bounds: topBounds, label: "Figure 1", extractedImage: FigurePreviewComposer.cropFigure(from: sourceImage, figureBounds: topBounds))
        let bottomFigure = DetectedFigure(bounds: bottomBounds, label: "Figure 2", extractedImage: FigurePreviewComposer.cropFigure(from: sourceImage, figureBounds: bottomBounds))

        let viewModel = AppViewModel(figureRetoucher: FakeRetoucher(r: 20, g: 40, b: 220))
        viewModel.capturedImage = sourceImage
        viewModel.previewImage = sourceImage
        viewModel.figureResult = FigureDetectionResult(figures: [topFigure, bottomFigure])
        viewModel.overlayController.buildOverlayItems(textBlocks: [], figures: [topFigure, bottomFigure])
        viewModel.overlayItems = viewModel.overlayController.overlayItems

        return (
            viewModel,
            CGPoint(x: topRect.midX, y: topRect.midY),
            CGPoint(x: bottomRect.midX, y: bottomRect.midY)
        )
    }

    private func configuredTwoFigureOverlayViewModel() -> (viewModel: AppViewModel, topCenter: CGPoint, bottomCenter: CGPoint) {
        let (viewModel, topCenter, bottomCenter) = configuredTwoFigureViewModel()
        let overlayBlock = TextBlock(
            id: UUID(),
            text: "Video",
            confidence: 0.99,
            bounds: CGRect(x: 0.24, y: 0.68, width: 0.12, height: 0.05)
        )
        let figures = viewModel.figureResult!.figures
        viewModel.ocrResult = OCRResult(textBlocks: [overlayBlock])
        viewModel.overlayController.buildOverlayItems(
            textBlocks: [(id: overlayBlock.id, text: overlayBlock.text, bounds: overlayBlock.bounds)],
            figures: figures,
            textClassifications: [overlayBlock.id: (classification: .overlay, figureIndex: 0)]
        )
        viewModel.overlayItems = viewModel.overlayController.overlayItems
        return (viewModel, topCenter, bottomCenter)
    }

    private func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(
            CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test("TC-5b.44: Excluding overlay-text updates preview and associated figure image", .tags(.core))
    func excludingOverlayTextUpdatesPreview() {
        let (viewModel, _, center) = configuredViewModel()
        let textOverlay = viewModel.overlayItems.first {
            $0.kind == .text && $0.textOverlayClassification == .overlay
        }!

        viewModel.toggleOverlayExclusion(id: textOverlay.id)

        #expect(viewModel.excludedTextBlockIds.count == 1)

        let preview = viewModel.previewImage!
        let previewPixel = pixelRGB(preview, x: Int(center.x), y: Int(center.y))
        #expect(previewPixel.b > 180, "Preview figure region should be recomposited with retouched pixels")
        #expect(previewPixel.r < 80, "Preview figure region should no longer show the original red crop")

        let updatedFigure = viewModel.figureResult!.figures[0].extractedImage!
        let figurePixel = pixelRGB(updatedFigure, x: updatedFigure.width / 2, y: updatedFigure.height / 2)
        #expect(figurePixel.b > 180, "Results panel thumbnail should use the retouched figure image")
        #expect(figurePixel.r < 80, "Retouched figure image should replace the original crop")
    }

    @Test("TC-5b.45: Re-including overlay-text restores original preview and figure image", .tags(.core))
    func reincludingOverlayTextRestoresOriginal() {
        let (viewModel, _, center) = configuredViewModel()
        let textOverlay = viewModel.overlayItems.first {
            $0.kind == .text && $0.textOverlayClassification == .overlay
        }!

        viewModel.toggleOverlayExclusion(id: textOverlay.id)
        viewModel.toggleOverlayExclusion(id: textOverlay.id)

        #expect(viewModel.excludedTextBlockIds.isEmpty)

        let preview = viewModel.previewImage!
        let previewPixel = pixelRGB(preview, x: Int(center.x), y: Int(center.y))
        #expect(previewPixel.r > 180, "Preview should restore the original figure pixels after re-include")
        #expect(previewPixel.b < 80, "Preview should no longer show the retouched pixels after re-include")

        let restoredFigure = viewModel.figureResult!.figures[0].extractedImage!
        let figurePixel = pixelRGB(restoredFigure, x: restoredFigure.width / 2, y: restoredFigure.height / 2)
        #expect(figurePixel.r > 180, "Figure thumbnail should restore the original crop after re-include")
        #expect(figurePixel.b < 80, "Restored figure thumbnail should no longer show retouched pixels")
    }

    @Test("TC-5b.46: Figure exclusion toggle does not alter preview figure positions", .tags(.core))
    func figureExclusionDoesNotRetouchPreview() {
        let (viewModel, topCenter, bottomCenter) = configuredTwoFigureViewModel()
        let topFigureOverlay = viewModel.overlayItems.first {
            $0.kind == .figure && $0.sourceFigureIndex == 0
        }!
        let originalPreview = viewModel.previewImage!
        let originalTopPixel = pixelRGB(originalPreview, x: Int(topCenter.x), y: Int(topCenter.y))
        let originalBottomPixel = pixelRGB(originalPreview, x: Int(bottomCenter.x), y: Int(bottomCenter.y))

        viewModel.toggleOverlayExclusion(id: topFigureOverlay.id)

        let preview = viewModel.previewImage!
        let topPixel = pixelRGB(preview, x: Int(topCenter.x), y: Int(topCenter.y))
        let bottomPixel = pixelRGB(preview, x: Int(bottomCenter.x), y: Int(bottomCenter.y))

        #expect(topPixel == originalTopPixel,
                "Figure exclusion should not alter the preview pixels at the first figure position")
        #expect(bottomPixel == originalBottomPixel,
                "Figure exclusion should not alter the preview pixels at the second figure position")
    }

    @Test("TC-5b.47: Retouching one figure leaves other preview figures unchanged", .tags(.core))
    func retouchingOneFigureLeavesOtherPreviewFiguresUnchanged() {
        let (viewModel, _, _) = configuredTwoFigureOverlayViewModel()
        let textOverlay = viewModel.overlayItems.first {
            $0.kind == .text && $0.textOverlayClassification == .overlay
        }!
        let targetFigure = viewModel.figureResult!.figures[0]
        let unaffectedFigure = viewModel.figureResult!.figures[1]
        let originalPreview = viewModel.previewImage!
        let originalUnaffectedCrop = FigurePreviewComposer.cropFigure(
            from: originalPreview,
            figureBounds: unaffectedFigure.bounds
        )!
        let originalUnaffectedPixel = pixelRGB(
            originalUnaffectedCrop,
            x: originalUnaffectedCrop.width / 2,
            y: originalUnaffectedCrop.height / 2
        )

        viewModel.toggleOverlayExclusion(id: textOverlay.id)

        let preview = viewModel.previewImage!
        let targetCrop = FigurePreviewComposer.cropFigure(from: preview, figureBounds: targetFigure.bounds)!
        let unaffectedCrop = FigurePreviewComposer.cropFigure(from: preview, figureBounds: unaffectedFigure.bounds)!
        let targetPixel = pixelRGB(targetCrop, x: targetCrop.width / 2, y: targetCrop.height / 2)
        let unaffectedPixel = pixelRGB(
            unaffectedCrop,
            x: unaffectedCrop.width / 2,
            y: unaffectedCrop.height / 2
        )

        #expect(targetPixel.b > 180,
                "The targeted figure should show the retouched preview after overlay-text exclusion")
        #expect(targetPixel.r < 80,
                "The targeted figure bounds should no longer show the original crop after retouch")
        #expect(unaffectedPixel == originalUnaffectedPixel,
                "Retouching one figure must not change unrelated figure bounds in the left preview")
    }

    @Test("TC-5b.48: FigurePreviewComposer composites replacement crop into matching figure bounds", .tags(.core))
    func figurePreviewComposerTargetsMatchingFigureBounds() {
        let (viewModel, _, _) = configuredTwoFigureViewModel()
        let sourceImage = viewModel.capturedImage!
        let topFigure = viewModel.figureResult!.figures[0]
        let bottomFigure = viewModel.figureResult!.figures[1]

        let replacementCrop = solidImage(
            width: topFigure.extractedImage!.width,
            height: topFigure.extractedImage!.height,
            r: 20,
            g: 40,
            b: 220
        )

        let composed = FigurePreviewComposer.compositeFigure(
            replacementCrop,
            into: sourceImage,
            figureBounds: topFigure.bounds
        )!

        let recompositedTop = FigurePreviewComposer.cropFigure(from: composed, figureBounds: topFigure.bounds)!
        let recompositedBottom = FigurePreviewComposer.cropFigure(from: composed, figureBounds: bottomFigure.bounds)!

        let topPixel = pixelRGB(
            recompositedTop,
            x: recompositedTop.width / 2,
            y: recompositedTop.height / 2
        )
        let bottomPixel = pixelRGB(
            recompositedBottom,
            x: recompositedBottom.width / 2,
            y: recompositedBottom.height / 2
        )

        #expect(topPixel.b > 180, "Replacement crop should appear inside the targeted figure bounds")
        #expect(topPixel.r < 80, "Targeted figure bounds should no longer show the original crop")
        #expect(bottomPixel.g > 150, "Unrelated figure bounds should retain the original lower figure")
        #expect(bottomPixel.r < 80, "Unrelated figure bounds must not receive the replacement crop")
    }
}
