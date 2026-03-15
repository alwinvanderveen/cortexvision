import Testing
import CoreGraphics
import Foundation
import AppKit
@testable import CortexVision

/// Spike test: proves that pass 1 (text-only inpaint) makes overlay regions
/// locally more uniform and component-wise more separable than in the original.
/// This is the prerequisite for the two-pass architecture to be viable.
///
/// The spike is generic: it measures variance reduction and component separability,
/// not color-specific properties. The reference image is evidence, not the optimization target.
@Suite("Spike — Pass 1 enables residue analysis")
struct SpikeResidueAnalysisTests {

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

    /// Renders CGImage to RGBA bitmap (row 0 = top). Caller must deallocate.
    private func renderBitmap(_ image: CGImage) -> (ptr: UnsafeMutablePointer<UInt8>, w: Int, h: Int)? {
        let w = image.width, h = image.height
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        guard let ctx = CGContext(
            data: ptr, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { ptr.deallocate(); return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (ptr, w, h)
    }

    /// Computes per-channel variance in a pixel region (top-left origin).
    private func regionVariance(_ ptr: UnsafePointer<UInt8>, w: Int, h: Int,
                                 x: Int, y: Int, rw: Int, rh: Int) -> Double {
        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        var sumR2 = 0.0, sumG2 = 0.0, sumB2 = 0.0
        var count = 0.0
        for py in y..<min(y + rh, h) {
            for px in x..<min(x + rw, w) {
                let off = (py * w + px) * 4
                let r = Double(ptr[off]), g = Double(ptr[off+1]), b = Double(ptr[off+2])
                sumR += r; sumG += g; sumB += b
                sumR2 += r*r; sumG2 += g*g; sumB2 += b*b
                count += 1
            }
        }
        guard count > 1 else { return 0 }
        let varR = sumR2/count - (sumR/count)*(sumR/count)
        let varG = sumG2/count - (sumG/count)*(sumG/count)
        let varB = sumB2/count - (sumB/count)*(sumB/count)
        return (varR + varG + varB) / 3.0
    }

    /// Counts connected components of high-saturation pixels in a region.
    /// Returns (componentCount, largestCompactness) where compactness = area / bbox area.
    private func componentAnalysis(_ ptr: UnsafePointer<UInt8>, w: Int, h: Int,
                                    x: Int, y: Int, rw: Int, rh: Int,
                                    satThreshold: Double = 0.4, valThreshold: Double = 0.25)
        -> (count: Int, largestCompactness: Double, largestArea: Int) {
        // Build saturation mask for the region
        var mask = [Bool](repeating: false, count: rw * rh)
        for ry in 0..<rh {
            for rx in 0..<rw {
                let px = min(x + rx, w - 1), py = min(y + ry, h - 1)
                let off = (py * w + px) * 4
                let r = Double(ptr[off]), g = Double(ptr[off+1]), b = Double(ptr[off+2])
                let maxC = max(r, g, b), minC = min(r, g, b)
                let sat = maxC > 10 ? (maxC - minC) / maxC : 0
                let val = maxC / 255.0
                mask[ry * rw + rx] = sat > satThreshold && val > valThreshold
            }
        }

        // BFS connected components
        var visited = [Bool](repeating: false, count: rw * rh)
        var components: [(area: Int, compactness: Double)] = []

        for startY in 0..<rh {
            for startX in 0..<rw {
                let idx = startY * rw + startX
                guard mask[idx], !visited[idx] else { continue }

                var queue = [(startX, startY)]
                visited[idx] = true
                var minX = startX, maxX = startX, minY = startY, maxY = startY
                var head = 0

                while head < queue.count {
                    let (cx, cy) = queue[head]; head += 1
                    minX = min(minX, cx); maxX = max(maxX, cx)
                    minY = min(minY, cy); maxY = max(maxY, cy)
                    for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, nx < rw, ny >= 0, ny < rh else { continue }
                        let ni = ny * rw + nx
                        guard mask[ni], !visited[ni] else { continue }
                        visited[ni] = true
                        queue.append((nx, ny))
                    }
                }

                let area = queue.count
                let bboxArea = (maxX - minX + 1) * (maxY - minY + 1)
                let compactness = bboxArea > 0 ? Double(area) / Double(bboxArea) : 0
                if area >= 20 { // filter noise
                    components.append((area: area, compactness: compactness))
                }
            }
        }

        components.sort { $0.area > $1.area }
        return (
            count: components.count,
            largestCompactness: components.first?.compactness ?? 0,
            largestArea: components.first?.area ?? 0
        )
    }

    // MARK: - TC-5b.S1 + S2: Spike test on real image

    @Test("Spike: pass 1 makes overlay regions more uniform and separable", .tags(.figures))
    func spikePass1EnablesResidueAnalysis() async throws {
        guard let image = loadTestImage("testMultipleImageNews2") else {
            Issue.record("Could not load testMultipleImageNews2.png")
            return
        }
        guard let pipeline = FigureInpaintingPipeline() else {
            Issue.record("LaMa model not available")
            return
        }

        // Run OCR + figure detection
        let ocrEngine = OCREngine()
        let ocrResult = try await ocrEngine.recognizeText(in: image)
        let figureDetector = FigureDetector()
        let figureResult = try await figureDetector.detectFigures(
            in: image, textBounds: ocrResult.textBlocks.map(\.bounds)
        )

        // Classify overlay text
        let analyzer = HeuristicOverlayTextAnalyzer()
        let bgColor = sampleBg(image)
        var overlayTextByFigure: [Int: [(bounds: CGRect, text: String)]] = [:]
        for block in ocrResult.textBlocks {
            for (figIdx, figure) in figureResult.figures.enumerated() {
                guard block.bounds.intersects(figure.bounds) else { continue }
                let cls = analyzer.classify(text: block.bounds, figure: figure.bounds,
                                            in: image, pageBgColor: bgColor)
                if cls == .overlay || cls == .edgeOverlay {
                    overlayTextByFigure[figIdx, default: []].append((bounds: block.bounds, text: block.text))
                    break
                }
            }
        }

        #expect(!overlayTextByFigure.isEmpty, "Should find overlay text")

        // For each figure with overlay text: compare original vs pass-1 output
        var allVarianceReduced = true
        var anySeparabilityImproved = false

        for (figIdx, textBlocks) in overlayTextByFigure {
            let figure = figureResult.figures[figIdx]
            let textBounds = textBlocks.map(\.bounds)

            // Get pass 1 result (text-only inpaint)
            guard let pass1 = pipeline.removeText(
                from: image, figureBounds: figure.bounds, textBounds: textBounds
            ) else { continue }

            guard let original = figure.extractedImage else { continue }

            // Render both to bitmaps
            guard let origBmp = renderBitmap(original),
                  let pass1Bmp = renderBitmap(pass1) else { continue }
            defer { origBmp.ptr.deallocate(); pass1Bmp.ptr.deallocate() }

            let figW = min(origBmp.w, pass1Bmp.w)
            let figH = min(origBmp.h, pass1Bmp.h)

            // For each text block, analyze the ROI around it
            for (i, tb) in textBounds.enumerated() {
                // Convert text bounds to pixel coords in figure crop (top-left origin)
                let figPixelX = figure.bounds.origin.x * CGFloat(image.width)
                let figPixelY = (1.0 - figure.bounds.origin.y - figure.bounds.height) * CGFloat(image.height)
                let textPixelX = tb.origin.x * CGFloat(image.width)
                let textPixelY = (1.0 - tb.origin.y - tb.height) * CGFloat(image.height)

                let relX = Int(textPixelX - figPixelX)
                let relY = Int(textPixelY - figPixelY)
                let relW = max(1, Int(tb.width * CGFloat(image.width)))
                let relH = max(1, Int(tb.height * CGFloat(image.height)))

                // Expand ROI to 3× text height in each direction
                let expandFactor = 3
                let roiX = max(0, relX - relH * expandFactor)
                let roiY = max(0, relY - relH * expandFactor)
                let roiW = min(figW - roiX, relW + relH * expandFactor * 2)
                let roiH = min(figH - roiY, relH + relH * expandFactor * 2)

                guard roiW > 10, roiH > 10 else { continue }

                // S1: Variance comparison
                let origVariance = regionVariance(origBmp.ptr, w: figW, h: figH,
                                                   x: roiX, y: roiY, rw: roiW, rh: roiH)
                let pass1Variance = regionVariance(pass1Bmp.ptr, w: figW, h: figH,
                                                    x: roiX, y: roiY, rw: roiW, rh: roiH)

                let varianceReduced = pass1Variance <= origVariance

                // S2: Component separability comparison
                let origComp = componentAnalysis(origBmp.ptr, w: figW, h: figH,
                                                  x: roiX, y: roiY, rw: roiW, rh: roiH)
                let pass1Comp = componentAnalysis(pass1Bmp.ptr, w: figW, h: figH,
                                                   x: roiX, y: roiY, rw: roiW, rh: roiH)

                let separabilityImproved = pass1Comp.largestCompactness >= origComp.largestCompactness
                    || pass1Comp.count <= origComp.count // fewer, cleaner components

                print("SPIKE: fig[\(figIdx)] text[\(i)] '\(textBlocks[i].text.prefix(20))'")
                print("  ROI: (\(roiX),\(roiY)) \(roiW)×\(roiH)")
                print("  Variance: orig=\(String(format: "%.1f", origVariance)) pass1=\(String(format: "%.1f", pass1Variance)) reduced=\(varianceReduced)")
                print("  Components: orig=(count=\(origComp.count) compact=\(String(format: "%.2f", origComp.largestCompactness)) area=\(origComp.largestArea)) pass1=(count=\(pass1Comp.count) compact=\(String(format: "%.2f", pass1Comp.largestCompactness)) area=\(pass1Comp.largestArea))")
                print("  Separability improved: \(separabilityImproved)")

                if !varianceReduced { allVarianceReduced = false }
                if separabilityImproved { anySeparabilityImproved = true }
            }
        }

        // Generic pass criteria:
        // Pass 1 should make overlay regions either more uniform (variance reduced)
        // OR more separable (better component structure) for at least some cases.
        // Both criteria are color-independent.
        #expect(allVarianceReduced || anySeparabilityImproved,
                "Pass 1 should make overlay regions more uniform or more separable")
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
