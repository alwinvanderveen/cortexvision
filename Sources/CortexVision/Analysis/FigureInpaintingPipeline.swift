import CoreGraphics
import Foundation

/// Orchestrates the full inpainting workflow: mask generation → crop → resize → inpaint → composite.
///
/// When a user excludes overlay-text from a figure, this pipeline:
/// 1. Generates a binary mask from the text block bounds
/// 2. Crops the figure region (with padding) from the source image
/// 3. Resizes crop + mask to 512×512 for LaMa
/// 4. Runs LaMa inpainting
/// 5. Resizes result back to original crop size
/// 6. Composites the inpainted region back into the source image
public final class FigureInpaintingPipeline: @unchecked Sendable {

    private let inpainter: LaMaInpainter
    private let maskGenerator: TextMaskGenerator
    private let debug: Bool

    public init(inpainter: LaMaInpainter, maskGenerator: TextMaskGenerator = TextMaskGenerator(), debug: Bool = false) {
        self.inpainter = inpainter
        self.maskGenerator = maskGenerator
        self.debug = debug
    }

    /// Convenience initializer that loads the bundled LaMa model.
    /// Returns nil if the model is not available (graceful degradation).
    public convenience init?() {
        let debug = ProcessInfo.processInfo.environment["FIGURE_DEBUG"] == "1"
        guard let inpainter = try? LaMaInpainter() else { return nil }
        self.init(inpainter: inpainter, debug: debug)
    }

    /// Removes text from a figure by inpainting the text regions.
    ///
    /// - Parameters:
    ///   - image: The full source captured image.
    ///   - figureBounds: Normalized bounds of the figure in Vision coordinates (bottom-left origin).
    ///   - textBounds: Normalized bounds of text blocks to remove, in Vision coordinates.
    /// - Returns: A new figure CGImage with text removed, or nil if inpainting fails.
    public func removeText(
        from image: CGImage,
        figureBounds: CGRect,
        textBounds: [CGRect]
    ) -> CGImage? {
        guard !textBounds.isEmpty else { return nil }

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        // Convert figure bounds from Vision coords (bottom-left origin) to CGImage coords (top-left origin)
        let figurePixelRect = CGRect(
            x: figureBounds.origin.x * imgW,
            y: (1.0 - figureBounds.origin.y - figureBounds.height) * imgH,
            width: figureBounds.width * imgW,
            height: figureBounds.height * imgH
        ).integral

        let clampedFigure = figurePixelRect.intersection(
            CGRect(x: 0, y: 0, width: imgW, height: imgH)
        )
        guard !clampedFigure.isEmpty else { return nil }

        if debug {
            print("[INPAINT-PIPELINE] image=\(image.width)×\(image.height)")
            print("[INPAINT-PIPELINE] figureBounds=\(figureBounds)")
            print("[INPAINT-PIPELINE] figurePixelRect=\(figurePixelRect)")
            print("[INPAINT-PIPELINE] clampedFigure=\(clampedFigure)")
        }

        // Crop figure region from source image
        guard let figureCrop = image.cropping(to: clampedFigure) else { return nil }

        if debug {
            print("[INPAINT-PIPELINE] figureCrop=\(figureCrop.width)×\(figureCrop.height)")
        }

        // Generate mask relative to the figure crop
        // Text bounds need to be remapped from full-image normalized to figure-crop normalized
        let relativeTextBounds = textBounds.compactMap { textRect -> CGRect? in
            // Vision coords → CGImage coords (flip Y)
            let textPixel = CGRect(
                x: textRect.origin.x * imgW,
                y: (1.0 - textRect.origin.y - textRect.height) * imgH,
                width: textRect.width * imgW,
                height: textRect.height * imgH
            )
            let intersection = textPixel.intersection(clampedFigure)
            guard !intersection.isEmpty else { return nil }

            // Convert to normalized coords relative to the figure crop
            // Both figure and text pixel rects are in CGImage coords (top-left origin).
            // TextMaskGenerator draws in CGContext (bottom-left origin), so flip Y for the mask.
            let relX = (intersection.origin.x - clampedFigure.origin.x) / clampedFigure.width
            let relY = (intersection.origin.y - clampedFigure.origin.y) / clampedFigure.height
            let relW = intersection.width / clampedFigure.width
            let relH = intersection.height / clampedFigure.height
            // Flip Y for CGContext bottom-left origin
            return CGRect(x: relX, y: 1.0 - relY - relH, width: relW, height: relH)
        }

        if debug {
            for (i, rb) in relativeTextBounds.enumerated() {
                print("[INPAINT-PIPELINE] relativeText[\(i)]=\(rb)")
            }
        }

        guard !relativeTextBounds.isEmpty else { return nil }

        // Generate text mask at figure crop size
        let cropSize = CGSize(width: clampedFigure.width, height: clampedFigure.height)
        guard let textMask = maskGenerator.generateMask(textBounds: relativeTextBounds, imageSize: cropSize) else {
            return nil
        }

        // Enhance mask: add highly-saturated UI element pixels (buttons/badges)
        // near text regions. These have distinctive colors (red, blue, green buttons)
        // that differ from typical photo content.
        let mask = enhanceMaskWithUIElements(
            textMask: textMask,
            figureCrop: figureCrop,
            textBounds: relativeTextBounds
        )

        if debug {
            print("[INPAINT-PIPELINE] mask=\(mask.width)×\(mask.height)")
            // Count white pixels in mask
            if let ctx = CGContext(data: nil, width: mask.width, height: mask.height,
                                   bitsPerComponent: 8, bytesPerRow: mask.width,
                                   space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                ctx.draw(mask, in: CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
                if let data = ctx.data {
                    let ptr = data.bindMemory(to: UInt8.self, capacity: mask.width * mask.height)
                    var whiteCount = 0
                    for i in 0..<(mask.width * mask.height) { if ptr[i] > 128 { whiteCount += 1 } }
                    let pct = Double(whiteCount) / Double(mask.width * mask.height) * 100
                    print("[INPAINT-PIPELINE] mask white pixels: \(whiteCount) (\(String(format: "%.1f", pct))%)")
                }
            }
        }

        // Run LaMa inpainting (handles resize to 512×512 internally)
        guard let inpainted = try? inpainter.inpaint(image: figureCrop, mask: mask) else {
            if debug { print("[INPAINT-PIPELINE] LaMa inference FAILED") }
            return nil
        }

        // Resize inpainted result back to original figure crop size
        let cropW = Int(clampedFigure.width)
        let cropH = Int(clampedFigure.height)
        guard let resized = resizeCGImage(inpainted, to: CGSize(width: cropW, height: cropH)) else {
            return nil
        }

        if debug {
            print("[INPAINT-PIPELINE] result=\(resized.width)×\(resized.height)")
        }

        return resized
    }

    // MARK: - UI Element Detection

    /// Enhances the text mask by detecting highly-saturated UI element pixels
    /// (buttons, badges, labels) near text regions.
    ///
    /// Strategy: within a search radius around each text bound, find pixels that are
    /// highly saturated (strong single-channel dominance) — these are UI elements, not photo content.
    /// Photo content has low saturation or complex patterns, so it won't be falsely masked.
    private func enhanceMaskWithUIElements(
        textMask: CGImage,
        figureCrop: CGImage,
        textBounds: [CGRect]  // normalized, bottom-left origin
    ) -> CGImage {
        let w = figureCrop.width
        let h = figureCrop.height
        guard w > 0, h > 0 else { return textMask }

        // Render figure to RGBA bitmap
        guard let imgCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return textMask }
        imgCtx.draw(figureCrop, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let imgData = imgCtx.data else { return textMask }
        let imgPtr = imgData.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // Render existing mask to mutable bitmap
        guard let maskCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return textMask }
        maskCtx.draw(textMask, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let maskData = maskCtx.data else { return textMask }
        let maskPtr = maskData.bindMemory(to: UInt8.self, capacity: w * h)

        // Magic wand: from each text mask border pixel, sample the adjacent color
        // and flood-fill into connected pixels of similar color.
        // This naturally finds UI elements (buttons/badges) around the text.
        let colorThreshold = 80.0  // max RGB distance to consider "same color" (buttons have gradients)
        var addedPixels = 0

        // Collect mask border pixels and their outward neighbor colors
        var seeds: [(x: Int, y: Int, r: Double, g: Double, b: Double)] = []
        for py in 0..<h {
            for px in 0..<w {
                guard maskPtr[py * w + px] > 128 else { continue }
                // Check if this is a border pixel (has an unmasked neighbor)
                for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    let nx = px + dx, ny = py + dy
                    if nx >= 0, nx < w, ny >= 0, ny < h, maskPtr[ny * w + nx] == 0 {
                        let offset = (ny * w + nx) * 4
                        seeds.append((
                            x: nx, y: ny,
                            r: Double(imgPtr[offset]),
                            g: Double(imgPtr[offset + 1]),
                            b: Double(imgPtr[offset + 2])
                        ))
                    }
                }
            }
        }

        // Group seeds by similar color to find dominant border colors
        // (e.g., the red of a button that surrounds the text)
        var colorClusters: [(r: Double, g: Double, b: Double, count: Int)] = []
        for seed in seeds {
            var matched = false
            for i in 0..<colorClusters.count {
                let diff = abs(seed.r - colorClusters[i].r) + abs(seed.g - colorClusters[i].g) + abs(seed.b - colorClusters[i].b)
                if diff < colorThreshold {
                    let n = Double(colorClusters[i].count)
                    colorClusters[i].r = (colorClusters[i].r * n + seed.r) / (n + 1)
                    colorClusters[i].g = (colorClusters[i].g * n + seed.g) / (n + 1)
                    colorClusters[i].b = (colorClusters[i].b * n + seed.b) / (n + 1)
                    colorClusters[i].count += 1
                    matched = true
                    break
                }
            }
            if !matched {
                colorClusters.append((r: seed.r, g: seed.g, b: seed.b, count: 1))
            }
        }

        // Only flood-fill for significant clusters (>10% of border pixels)
        // that are clearly NOT photo-like (high saturation)
        let minClusterSize = max(5, seeds.count / 50)  // 2% of border pixels suffices for small buttons
        let significantClusters = colorClusters.filter { cluster in
            guard cluster.count >= minClusterSize else { return false }
            let maxC = max(cluster.r, cluster.g, cluster.b)
            let minC = min(cluster.r, cluster.g, cluster.b)
            let sat = maxC > 10 ? (maxC - minC) / maxC : 0
            return sat > 0.7 && maxC > 100  // Only strongly saturated bright colors (buttons/badges)
        }

        if debug {
            print("[INPAINT-PIPELINE] Magic wand: \(seeds.count) border seeds, \(colorClusters.count) clusters, \(significantClusters.count) significant (min \(minClusterSize) seeds)")
            for c in colorClusters.sorted(by: { $0.count > $1.count }).prefix(5) {
                let maxC = max(c.r, c.g, c.b)
                let minC = min(c.r, c.g, c.b)
                let sat = maxC > 10 ? (maxC - minC) / maxC : 0
                print("[INPAINT-PIPELINE]   cluster RGB=(\(String(format: "%.0f,%.0f,%.0f", c.r, c.g, c.b))) count=\(c.count) sat=\(String(format: "%.2f", sat))")
            }
        }

        // BFS flood-fill from mask border into color-matching pixels
        var queue: [(Int, Int)] = []

        // Seed all unmasked border-adjacent pixels
        for seed in seeds {
            guard maskPtr[seed.y * w + seed.x] == 0 else { continue }
            // Check if this pixel matches any significant UI color cluster
            for cluster in significantClusters {
                let diff = abs(seed.r - cluster.r) + abs(seed.g - cluster.g) + abs(seed.b - cluster.b)
                if diff < colorThreshold {
                    maskPtr[seed.y * w + seed.x] = 255
                    queue.append((seed.x, seed.y))
                    addedPixels += 1
                    break
                }
            }
        }

        // BFS: expand into connected pixels of similar color
        var head = 0
        let maxExpand = w * h / 10  // safety: max 10% of image
        while head < queue.count, addedPixels < maxExpand {
            let (cx, cy) = queue[head]
            head += 1
            for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,-1),(-1,1),(1,1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, nx < w, ny >= 0, ny < h, maskPtr[ny * w + nx] == 0 else { continue }

                let offset = (ny * w + nx) * 4
                let pr = Double(imgPtr[offset])
                let pg = Double(imgPtr[offset + 1])
                let pb = Double(imgPtr[offset + 2])

                // Check if pixel color matches any significant cluster
                for cluster in significantClusters {
                    let diff = abs(pr - cluster.r) + abs(pg - cluster.g) + abs(pb - cluster.b)
                    if diff < colorThreshold {
                        maskPtr[ny * w + nx] = 255
                        queue.append((nx, ny))
                        addedPixels += 1
                        break
                    }
                }
            }
        }

        if debug && addedPixels > 0 {
            let pct = Double(addedPixels) / Double(w * h) * 100
            print("[INPAINT-PIPELINE] Magic wand: \(addedPixels) UI pixels added (\(String(format: "%.1f", pct))%)")
        }

        if addedPixels == 0 { return textMask }
        return maskCtx.makeImage() ?? textMask
    }

    // MARK: - Helpers

    private func resizeCGImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
