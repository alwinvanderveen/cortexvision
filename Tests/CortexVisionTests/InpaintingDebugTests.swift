import Testing
import CoreGraphics
import Foundation
import AppKit
@testable import CortexVision

@Suite("Inpainting Debug — Visual verification")
struct InpaintingDebugTests {

    /// Reads RGBA pixel at (x, y) where y=0 is TOP of image (bitmap memory order).
    private func readPixelTopOrigin(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let w = image.width, h = image.height
        let context = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data = context.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // Bitmap memory: row 0 = top of image
        let offset = (y * w + x) * 4
        return (r: data[offset], g: data[offset + 1], b: data[offset + 2])
    }

    /// Computes average RGB over a region where y=0 is TOP.
    private func averageRGBTopOrigin(_ image: CGImage, x: Int, y: Int, w: Int, h: Int) -> (r: Double, g: Double, b: Double) {
        let imgW = image.width, imgH = image.height
        let context = CGContext(
            data: nil, width: imgW, height: imgH,
            bitsPerComponent: 8, bytesPerRow: imgW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
        let data = context.data!.bindMemory(to: UInt8.self, capacity: imgW * imgH * 4)

        var totalR = 0.0, totalG = 0.0, totalB = 0.0, count = 0
        for py in y..<min(y + h, imgH) {
            for px in x..<min(x + w, imgW) {
                let offset = (py * imgW + px) * 4
                totalR += Double(data[offset])
                totalG += Double(data[offset + 1])
                totalB += Double(data[offset + 2])
                count += 1
            }
        }
        guard count > 0 else { return (0, 0, 0) }
        return (r: totalR / Double(count), g: totalG / Double(count), b: totalB / Double(count))
    }

    // MARK: - Direct LaMa test with pixel-level mask

    @Test("LaMa: orientation preserved (green marker stays at top-left)", .tags(.figures))
    func lamaOrientationPreserved() throws {
        let inpainter = try LaMaInpainter()
        let size = 512

        // Create image: red background + green marker at top-left + black rect in center
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Red background
        ctx.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        // Green marker at TOP-LEFT: in CGContext bottom-left origin, top = y=height-markerH
        ctx.setFillColor(CGColor(red: 0, green: 0.8, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: size - 50, width: 50, height: 50))
        // Black "text" in center
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 180, y: 200, width: 150, height: 80))
        let image = ctx.makeImage()!

        // Verify input orientation: bitmap (0,0) = top-left should be green
        let inputTopLeft = readPixelTopOrigin(image, x: 25, y: 25)
        #expect(inputTopLeft.g > 150, "Input top-left should be green: \(inputTopLeft)")

        // Create mask directly as bitmap (row 0 = top, matching bitmap order)
        let maskCtx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        // Black mask (keep everything)
        maskCtx.setFillColor(gray: 0, alpha: 1)
        maskCtx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        // White where "text" is: CGContext y=200 bottom-left = bitmap row (512-200-80)=232
        // In CGContext coords, fill at same position as the black rect in the image
        maskCtx.setFillColor(gray: 1, alpha: 1)
        maskCtx.fill(CGRect(x: 170, y: 190, width: 170, height: 100))  // slightly larger than text
        let mask = maskCtx.makeImage()!

        // Run LaMa
        let result = try inpainter.inpaint(image: image, mask: mask)

        // Check orientation: green should still be at bitmap top-left
        let resultTopLeft = readPixelTopOrigin(result, x: 25, y: 25)
        let resultBottomRight = readPixelTopOrigin(result, x: size - 25, y: size - 25)

        print("DEBUG orient: input top-left=\(inputTopLeft)")
        print("DEBUG orient: result top-left=\(resultTopLeft)")
        print("DEBUG orient: result bottom-right=\(resultBottomRight)")

        #expect(resultTopLeft.g > 100, "Output top-left should be green (not flipped): \(resultTopLeft)")
        #expect(resultBottomRight.g < 100, "Output bottom-right should NOT be green: \(resultBottomRight)")
    }

    @Test("LaMa: black text rectangle is inpainted with background color", .tags(.figures))
    func lamaTextInpainted() throws {
        let inpainter = try LaMaInpainter()
        let size = 512

        // Red background + black center rectangle
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 180, y: 200, width: 150, height: 80))
        let image = ctx.makeImage()!

        // Verify: center of image in bitmap coords should be black
        // CGContext y=200 bottom-left → bitmap row = 512-200-80=232, center = 232+40=272
        let inputCenter = averageRGBTopOrigin(image, x: 200, y: 252, w: 110, h: 40)
        print("DEBUG text: input center (should be black) = \(inputCenter)")
        #expect(inputCenter.r < 30, "Input center should be black: R=\(inputCenter.r)")

        // Mask covering the text (same CGContext coords → same bitmap alignment)
        let maskCtx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        maskCtx.setFillColor(gray: 0, alpha: 1)
        maskCtx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        maskCtx.setFillColor(gray: 1, alpha: 1)
        maskCtx.fill(CGRect(x: 170, y: 190, width: 170, height: 100))
        let mask = maskCtx.makeImage()!

        let result = try inpainter.inpaint(image: image, mask: mask)

        // After inpainting: center should no longer be black, should be closer to red
        let outputCenter = averageRGBTopOrigin(result, x: 200, y: 252, w: 110, h: 40)
        print("DEBUG text: output center (should be red-ish) = \(outputCenter)")

        #expect(outputCenter.r > 80, "Inpainted center R should be >80: \(outputCenter.r)")
        let brightness = (outputCenter.r + outputCenter.g + outputCenter.b) / 3
        #expect(brightness > 40, "Inpainted center should not be black: brightness=\(brightness)")
    }

    @Test("Pipeline: full removeText preserves orientation and removes text", .tags(.figures))
    func pipelineFullTest() throws {
        guard let pipeline = FigureInpaintingPipeline() else {
            Issue.record("LaMa model not available")
            return
        }

        let w = 800, h = 600
        let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Blue background
        ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Green marker at top-left (CGContext: y=h-50)
        ctx.setFillColor(CGColor(red: 0, green: 0.8, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h - 50, width: 50, height: 50))
        // White "text" in center (CGContext: y=250)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 200, y: 250, width: 400, height: 60))
        let image = ctx.makeImage()!

        // Figure = full image, text in Vision normalized coords
        let figureBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        // Text at CGContext y=250 → Vision y = 250/600 = 0.417
        let textBounds = [CGRect(x: 200.0/800, y: 250.0/600, width: 400.0/800, height: 60.0/600)]

        guard let result = pipeline.removeText(from: image, figureBounds: figureBounds, textBounds: textBounds) else {
            Issue.record("Pipeline returned nil")
            return
        }

        #expect(result.width == w)
        #expect(result.height == h)

        // Green marker at top-left in bitmap
        let topLeft = readPixelTopOrigin(result, x: 25, y: 25)
        print("DEBUG pipeline: top-left = \(topLeft)")
        #expect(topLeft.g > 100, "Pipeline should preserve orientation: \(topLeft)")

        // Text region in bitmap: CGContext y=250 → bitmap row = 600-250-60=290, center=320
        let textRegion = averageRGBTopOrigin(result, x: 250, y: 300, w: 300, h: 30)
        print("DEBUG pipeline: text region (should be blue-ish) = \(textRegion)")
        // Should be closer to blue background (25, 51, 179) than white (255, 255, 255)
        #expect(textRegion.b > textRegion.r, "Inpainted text should be blue-ish, not white: \(textRegion)")
    }

    // MARK: - Real image regression: testMultipleImageNews2

    private func loadTestImage(_ name: String) -> CGImage? {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imagePath = projectRoot
            .appendingPathComponent("Image")
            .appendingPathComponent("\(name).png")
        guard let nsImage = NSImage(contentsOf: imagePath),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
    }

    @Test("Real image: testMultipleImageNews2 — OCR + figure detect + inpaint removes overlay text", .tags(.figures))
    func realImageInpaintNews2() async throws {
        guard let image = loadTestImage("testMultipleImageNews2") else {
            Issue.record("Could not load testMultipleImageNews2.png")
            return
        }
        guard let pipeline = FigureInpaintingPipeline() else {
            Issue.record("LaMa model not available")
            return
        }

        // Run OCR
        let ocrEngine = OCREngine()
        let ocrResult = try await ocrEngine.recognizeText(in: image)
        print("REAL: OCR blocks: \(ocrResult.textBlocks.count)")

        // Run figure detection
        let figureDetector = FigureDetector()
        let figureResult = try await figureDetector.detectFigures(
            in: image,
            textBounds: ocrResult.textBlocks.map(\.bounds)
        )
        print("REAL: Figures: \(figureResult.figures.count)")
        #expect(figureResult.figures.count >= 2, "Should detect at least 2 figures")

        // Classify text blocks against figures
        let analyzer = HeuristicOverlayTextAnalyzer()
        let pageBgColor = sampleBg(image)

        var overlayTextByFigure: [Int: [(id: UUID, bounds: CGRect)]] = [:]
        for block in ocrResult.textBlocks {
            for (figIdx, figure) in figureResult.figures.enumerated() {
                guard block.bounds.intersects(figure.bounds) else { continue }
                let cls = analyzer.classify(
                    text: block.bounds, figure: figure.bounds,
                    in: image, pageBgColor: pageBgColor
                )
                if cls == .overlay || cls == .edgeOverlay {
                    overlayTextByFigure[figIdx, default: []].append((id: block.id, bounds: block.bounds))
                    print("REAL: text '\(block.text.prefix(30))' → \(cls) on figure \(figIdx)")
                    break
                }
            }
        }

        #expect(!overlayTextByFigure.isEmpty, "Should find overlay text on at least one figure")

        // Inpaint each figure with overlay text
        for (figIdx, textBlocks) in overlayTextByFigure {
            let figure = figureResult.figures[figIdx]
            let textBounds = textBlocks.map(\.bounds)

            print("REAL: Inpainting figure \(figIdx) (\(figure.label)) with \(textBounds.count) text blocks")

            guard let inpainted = pipeline.removeText(
                from: image,
                figureBounds: figure.bounds,
                textBounds: textBounds
            ) else {
                Issue.record("Inpainting failed for figure \(figIdx)")
                continue
            }

            print("REAL: Inpainted \(figure.label): \(inpainted.width)×\(inpainted.height)")

            // Verify dimensions match original figure
            if let original = figure.extractedImage {
                let widthDiff = abs(inpainted.width - original.width)
                let heightDiff = abs(inpainted.height - original.height)
                #expect(widthDiff <= 2, "Width diff should be ≤2px: \(widthDiff)")
                #expect(heightDiff <= 2, "Height diff should be ≤2px: \(heightDiff)")
            }

            // Verify text regions are no longer dark/contrasting
            // Sample the text areas in the inpainted result
            for (i, tb) in textBounds.enumerated() {
                // Convert text Vision bounds to pixel coords in inpainted figure
                // Text bounds are full-image Vision coords; figure is a crop
                let figPixelX = figure.bounds.origin.x * CGFloat(image.width)
                let figPixelY = (1.0 - figure.bounds.origin.y - figure.bounds.height) * CGFloat(image.height)
                let textPixelX = tb.origin.x * CGFloat(image.width)
                let textPixelY = (1.0 - tb.origin.y - tb.height) * CGFloat(image.height)

                let relX = Int(textPixelX - figPixelX)
                let relY = Int(textPixelY - figPixelY)
                let relW = Int(tb.width * CGFloat(image.width))
                let relH = Int(tb.height * CGFloat(image.height))

                guard relX >= 0, relY >= 0,
                      relX + relW <= inpainted.width,
                      relY + relH <= inpainted.height else {
                    print("REAL: text[\(i)] out of bounds, skipping")
                    continue
                }

                // Sample the inpainted text area
                let textRGB = averageRGBTopOrigin(inpainted, x: relX, y: relY, w: relW, h: relH)

                // Sample the surrounding area (just above the text) for comparison
                let aboveY = max(0, relY - relH * 2)
                let surroundRGB = averageRGBTopOrigin(inpainted, x: relX, y: aboveY, w: relW, h: relH)

                print("REAL: fig[\(figIdx)] text[\(i)] inpainted RGB=(\(String(format: "%.0f,%.0f,%.0f", textRGB.r, textRGB.g, textRGB.b))) surround RGB=(\(String(format: "%.0f,%.0f,%.0f", surroundRGB.r, surroundRGB.g, surroundRGB.b)))")

                // The inpainted text region should be somewhat similar to surrounding area
                let diffR = abs(textRGB.r - surroundRGB.r)
                let diffG = abs(textRGB.g - surroundRGB.g)
                let diffB = abs(textRGB.b - surroundRGB.b)
                let avgDiff = (diffR + diffG + diffB) / 3
                print("REAL: fig[\(figIdx)] text[\(i)] avg color diff from surround: \(String(format: "%.1f", avgDiff))")

                // Inpainting should bring the text region closer to surrounding colors.
                // Threshold 100 allows for complex backgrounds while catching failures.
                #expect(avgDiff < 100, "Inpainted text region should be similar to surroundings, avgDiff=\(String(format: "%.1f", avgDiff))")
            }
        }

        // === Pixel-level before/after comparison for each inpainted figure ===
        for (figIdx, textBlocks) in overlayTextByFigure {
            let figure = figureResult.figures[figIdx]
            guard let original = figure.extractedImage,
                  let inpainted = pipeline.removeText(
                    from: image,
                    figureBounds: figure.bounds,
                    textBounds: textBlocks.map(\.bounds)
                  ) else { continue }

            // Render both to same-sized bitmaps for pixel comparison
            let w = min(original.width, inpainted.width)
            let h = min(original.height, inpainted.height)
            guard w > 0, h > 0 else { continue }

            let origData = renderToBitmap(original, width: w, height: h)
            let inpData = renderToBitmap(inpainted, width: w, height: h)
            guard let origPtr = origData, let inpPtr = inpData else { continue }

            // Classify each pixel as: text/button region (changed) or photo region (should be preserved)
            var changedPixels = 0
            var preservedPixels = 0
            var totalChangeDiff = 0.0
            var totalPreserveDiff = 0.0
            var redPixelsBefore = 0
            var redPixelsAfter = 0

            for py in 0..<h {
                for px in 0..<w {
                    let offset = (py * w + px) * 4
                    let origR = Double(origPtr[offset])
                    let origG = Double(origPtr[offset + 1])
                    let origB = Double(origPtr[offset + 2])
                    let inpR = Double(inpPtr[offset])
                    let inpG = Double(inpPtr[offset + 1])
                    let inpB = Double(inpPtr[offset + 2])

                    let pixelDiff = (abs(origR - inpR) + abs(origG - inpG) + abs(origB - inpB)) / 3

                    // Count distinctly red pixels (button indicator)
                    if origR > 150 && origG < 80 && origB < 80 { redPixelsBefore += 1 }
                    if inpR > 150 && inpG < 80 && inpB < 80 { redPixelsAfter += 1 }

                    if pixelDiff > 15 {
                        // This pixel changed significantly
                        changedPixels += 1
                        totalChangeDiff += pixelDiff
                    } else {
                        preservedPixels += 1
                        totalPreserveDiff += pixelDiff
                    }
                }
            }

            let totalPixels = w * h
            let changedPct = Double(changedPixels) / Double(totalPixels) * 100
            let preservedPct = Double(preservedPixels) / Double(totalPixels) * 100
            let avgPreserveDiff = preservedPixels > 0 ? totalPreserveDiff / Double(preservedPixels) : 0
            let redReduction = redPixelsBefore > 0 ? (1.0 - Double(redPixelsAfter) / Double(redPixelsBefore)) * 100 : 100

            print("REAL: fig[\(figIdx)] pixel comparison:")
            print("  changed: \(changedPixels) (\(String(format: "%.1f", changedPct))%)")
            print("  preserved: \(preservedPixels) (\(String(format: "%.1f", preservedPct))%)")
            print("  avg preserve diff: \(String(format: "%.1f", avgPreserveDiff))")
            print("  red pixels: before=\(redPixelsBefore) after=\(redPixelsAfter) reduction=\(String(format: "%.0f", redReduction))%")

            // Assertions:
            // 1. Most of the figure should be preserved (>70% unchanged)
            #expect(preservedPct > 70, "fig[\(figIdx)]: >70% of pixels should be preserved, got \(String(format: "%.1f", preservedPct))%")

            // 2. Changed region should be <30% (only text/button areas)
            #expect(changedPct < 30, "fig[\(figIdx)]: <30% of pixels should change, got \(String(format: "%.1f", changedPct))%")

            // 3. Preserved pixels should be very close to original
            #expect(avgPreserveDiff < 5, "fig[\(figIdx)]: preserved pixels should be close to original, avgDiff=\(String(format: "%.1f", avgPreserveDiff))")

            // 4. Red button pixels should be mostly gone (>80% reduction)
            // Only check for figures with significant red content (>1000 pixels = actual button)
            if redPixelsBefore > 1000 {
                #expect(redReduction > 80, "fig[\(figIdx)]: red button pixels should be >80% reduced, got \(String(format: "%.0f", redReduction))%")
            }

            origPtr.deallocate()
            inpPtr.deallocate()
        }
    }

    /// Renders CGImage to raw RGBA bitmap (row 0 = top). Caller must deallocate.
    private func renderToBitmap(_ image: CGImage, width: Int, height: Int) -> UnsafeMutablePointer<UInt8>? {
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        guard let ctx = CGContext(
            data: data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            data.deallocate()
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private func sampleBg(_ image: CGImage) -> (r: Double, g: Double, b: Double) {
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (255, 255, 255) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = ctx.data else { return (255, 255, 255) }
        let ptr = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        return FigureDetector.sampleBackgroundColor(ptr: ptr, width: image.width, height: image.height)
    }
}
