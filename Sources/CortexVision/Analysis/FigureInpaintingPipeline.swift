import CoreGraphics
import Foundation

/// Orchestrates the two-pass inpainting workflow for overlay removal on figures.
///
/// Pass 1: Text-only mask → LaMa removes text glyphs.
/// Residue analysis: OCR-anchored multi-signal detection of remaining UI element backgrounds.
/// Pass 2 (conditional): Expanded mask (text + UI blobs) → LaMa on original crop.
/// Validation: local (context-ring) + global (preserve metrics). Failure → fallback to pass 1.
///
/// The pipeline is generic: it works for any UI overlay color, shape, and text offset.
/// No architecture or threshold depends on a specific reference image.
public final class FigureInpaintingPipeline: @unchecked Sendable {

    private struct ExpandedMaskArtifacts {
        let mask: CGImage
        let expandedBounds: [CGRect]
    }

    private let inpainter: LaMaInpainter
    private let maskGenerator: TextMaskGenerator
    private let residueAnalyzer: ResidueAnalyzer
    private let debug: Bool

    public init(
        inpainter: LaMaInpainter,
        maskGenerator: TextMaskGenerator = TextMaskGenerator(),
        residueAnalyzer: ResidueAnalyzer? = nil,
        debug: Bool = false
    ) {
        self.inpainter = inpainter
        self.maskGenerator = maskGenerator
        self.debug = debug
        self.residueAnalyzer = residueAnalyzer ?? ResidueAnalyzer(debug: debug)
    }

    /// Convenience initializer that loads the bundled LaMa model.
    /// Returns nil if the model is not available (graceful degradation).
    public convenience init?() {
        let debug = ProcessInfo.processInfo.environment["FIGURE_DEBUG"] == "1"
        guard let inpainter = try? LaMaInpainter() else { return nil }
        self.init(inpainter: inpainter, debug: debug)
    }

    /// Removes overlay content (text + UI element backgrounds) from a figure.
    ///
    /// - Parameters:
    ///   - image: The full source captured image.
    ///   - figureBounds: Normalized bounds of the figure in Vision coordinates (bottom-left origin).
    ///   - textBounds: Normalized bounds of text blocks to remove, in Vision coordinates.
    /// - Returns: A new figure CGImage with overlays removed, or nil if inpainting fails.
    public func removeText(
        from image: CGImage,
        figureBounds: CGRect,
        textBounds: [CGRect]
    ) -> CGImage? {
        guard !textBounds.isEmpty else { return nil }

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        // Convert figure bounds from Vision coords (bottom-left) to CGImage coords (top-left)
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

        // Crop figure region from source image
        guard let figureCrop = image.cropping(to: clampedFigure) else { return nil }

        // Remap text bounds to figure-crop-relative coordinates
        let relativeTextBounds = textBounds.compactMap { textRect -> CGRect? in
            let textPixel = CGRect(
                x: textRect.origin.x * imgW,
                y: (1.0 - textRect.origin.y - textRect.height) * imgH,
                width: textRect.width * imgW,
                height: textRect.height * imgH
            )
            let intersection = textPixel.intersection(clampedFigure)
            guard !intersection.isEmpty else { return nil }

            let relX = (intersection.origin.x - clampedFigure.origin.x) / clampedFigure.width
            let relY = (intersection.origin.y - clampedFigure.origin.y) / clampedFigure.height
            let relW = intersection.width / clampedFigure.width
            let relH = intersection.height / clampedFigure.height
            // Flip Y for CGContext bottom-left origin (TextMaskGenerator uses CGContext)
            return CGRect(x: relX, y: 1.0 - relY - relH, width: relW, height: relH)
        }

        guard !relativeTextBounds.isEmpty else { return nil }

        // === PASS 1: Text-only inpaint ===
        let cropSize = CGSize(width: clampedFigure.width, height: clampedFigure.height)
        guard let textMask = maskGenerator.generateMask(textBounds: relativeTextBounds, imageSize: cropSize) else {
            return nil
        }

        guard let pass1Result = try? inpainter.inpaint(image: figureCrop, mask: textMask) else {
            if debug { print("[PIPELINE] Pass 1 LaMa inference failed") }
            return nil
        }

        let cropW = Int(clampedFigure.width)
        let cropH = Int(clampedFigure.height)
        guard let pass1Resized = resizeCGImage(pass1Result, to: CGSize(width: cropW, height: cropH)) else {
            return nil
        }

        if debug {
            print("[PIPELINE] Pass 1 complete: \(pass1Resized.width)×\(pass1Resized.height)")
        }

        // === RESIDUE ANALYSIS on ORIGINAL + pass-1 comparison ===
        let (candidates, debugInfo) = residueAnalyzer.analyze(
            originalCrop: figureCrop,
            pass1Result: pass1Resized,
            textBounds: relativeTextBounds
        )

        if debug {
            print("[PIPELINE] Residue analysis: \(debugInfo.count) components, \(candidates.count) accepted")
        }

        // Fast path: no UI element residue detected → return pass 1
        guard !candidates.isEmpty else {
            return pass1Resized
        }

        // Pre-validate: filter out candidates with low area (likely photo noise, not UI elements).
        // The merge-signal and multi-signal scoring already filtered most false positives.
        // Large blobs with merge confirmation are the strongest candidates.
        let validatedCandidates = candidates.filter { candidate in
            // Require minimum area to be worth a pass-2 mask entry
            if candidate.pixelCount < 200 && !candidate.mergedAfterPass1 {
                if debug {
                    print("[PIPELINE] Pre-validation: blob \(Int(candidate.bounds.origin.x)),\(Int(candidate.bounds.origin.y)) rejected (too small without merge: \(candidate.pixelCount)px)")
                }
                return false
            }
            return true
        }

        guard !validatedCandidates.isEmpty else {
            if debug { print("[PIPELINE] All candidates rejected by pre-validation, using pass 1") }
            return pass1Resized
        }

        if debug {
            print("[PIPELINE] \(validatedCandidates.count)/\(candidates.count) candidates passed pre-validation")
        }

        // === PASS 2: Expanded mask on ORIGINAL crop ===
        guard let expandedArtifacts = mergeBlobs(textMask: textMask, candidates: validatedCandidates,
                                                 imageSize: cropSize) else {
            return pass1Resized
        }

        if debug {
            let maskPixels = countWhitePixels(expandedArtifacts.mask)
            let totalPixels = expandedArtifacts.mask.width * expandedArtifacts.mask.height
            let pct = Double(maskPixels) / Double(totalPixels) * 100
            print("[PIPELINE] Expanded mask: \(maskPixels) white pixels (\(String(format: "%.1f", pct))%)")
        }

        guard let pass2Result = try? inpainter.inpaint(image: figureCrop, mask: expandedArtifacts.mask) else {
            if debug { print("[PIPELINE] Pass 2 LaMa inference failed, falling back to pass 1") }
            return pass1Resized
        }

        guard let pass2Resized = resizeCGImage(pass2Result, to: CGSize(width: cropW, height: cropH)) else {
            return pass1Resized
        }

        // === VALIDATION GATE ===
        if !validatePass2(
            original: figureCrop,
            pass1: pass1Resized,
            pass2: pass2Resized,
            expandedMask: expandedArtifacts.mask,
            expandedBounds: expandedArtifacts.expandedBounds
        ) {
            if debug { print("[PIPELINE] Validation failed, falling back to pass 1") }
            return pass1Resized
        }

        if debug {
            print("[PIPELINE] Pass 2 accepted")
        }

        return pass2Resized
    }

    // MARK: - Mask Merging

    /// Merges candidate blob bounding boxes into the text mask and records the real
    /// expanded support used for pass 2. Validation must reason about the same support.
    private func mergeBlobs(textMask: CGImage, candidates: [CandidateBlob],
                            imageSize: CGSize) -> ExpandedMaskArtifacts? {
        let w = Int(imageSize.width), h = Int(imageSize.height)
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // Draw existing text mask
        ctx.draw(textMask, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Add candidate blob bounding boxes with small margin (pixel coords, top-left origin)
        // The margin ensures the full UI element is covered including anti-aliased edges.
        // CGContext drawing uses bottom-left origin, so flip Y.
        ctx.setFillColor(gray: 1, alpha: 1)
        let imageBounds = CGRect(x: 0, y: 0, width: w, height: h)
        var expandedBounds: [CGRect] = []
        for candidate in candidates {
            let b = candidate.bounds
            // 25% margin compensates for anti-aliased edges and parts of the UI element
            // that fall outside the detected high-saturation blob (e.g., button bottom half
            // that extends below the text-anchored search ROI)
            let marginX = max(10.0, b.width * 0.25)
            let marginY = max(10.0, b.height * 0.25)
            let expandedRect = CGRect(
                x: b.origin.x - marginX,
                y: b.origin.y - marginY,
                width: b.width + marginX * 2,
                height: b.height + marginY * 2
            ).intersection(imageBounds)
            guard !expandedRect.isEmpty else { continue }

            let expandedX = expandedRect.origin.x
            let expandedY = expandedRect.origin.y
            let expandedW = expandedRect.width
            let expandedH = expandedRect.height
            let flippedY = CGFloat(h) - expandedY - expandedH
            ctx.fill(CGRect(x: expandedX, y: flippedY, width: expandedW, height: expandedH))
            expandedBounds.append(expandedRect.integral)
        }

        guard let mask = ctx.makeImage() else { return nil }
        return ExpandedMaskArtifacts(mask: mask, expandedBounds: expandedBounds)
    }

    // MARK: - Validation Gate

    /// Measures incremental pass-2 damage in a ring around the support area.
    ///
    /// This intentionally compares pass 1 vs pass 2, not original vs pass 2.
    /// The question here is whether the SECOND pass introduced collateral changes
    /// outside the support it was explicitly allowed to modify.
    static func localIncrementalDamage(
        pass1: CGImage,
        pass2: CGImage,
        supportMask: CGImage,
        focusBounds: CGRect,
        outerMargin: CGFloat = 20,
        diffThreshold: Double = 20
    ) -> Double? {
        let w = min(pass1.width, pass2.width, supportMask.width)
        let h = min(pass1.height, pass2.height, supportMask.height)
        guard w > 0, h > 0 else { return nil }

        func renderRGBA(_ image: CGImage) -> UnsafeMutablePointer<UInt8>? {
            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
            guard let ctx = CGContext(
                data: ptr, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                ptr.deallocate()
                return nil
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return ptr
        }

        func renderMask(_ image: CGImage) -> UnsafeMutablePointer<UInt8>? {
            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h)
            guard let ctx = CGContext(
                data: ptr, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                ptr.deallocate()
                return nil
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return ptr
        }

        guard let pass1Bmp = renderRGBA(pass1),
              let pass2Bmp = renderRGBA(pass2),
              let maskBmp = renderMask(supportMask) else { return nil }
        defer {
            pass1Bmp.deallocate()
            pass2Bmp.deallocate()
            maskBmp.deallocate()
        }

        let ringRect = focusBounds.insetBy(dx: -outerMargin, dy: -outerMargin)
        let minX = max(0, Int(floor(ringRect.minX)))
        let minY = max(0, Int(floor(ringRect.minY)))
        let maxX = min(w, Int(ceil(ringRect.maxX)))
        let maxY = min(h, Int(ceil(ringRect.maxY)))
        guard minX < maxX, minY < maxY else { return nil }

        var damage = 0
        var total = 0

        for py in minY..<maxY {
            for px in minX..<maxX {
                // Only inspect the ring band outside the candidate's own support rectangle.
                if px >= Int(floor(focusBounds.minX)) && px < Int(ceil(focusBounds.maxX)) &&
                   py >= Int(floor(focusBounds.minY)) && py < Int(ceil(focusBounds.maxY)) {
                    continue
                }

                // Skip any pixel explicitly covered by the expanded support mask.
                if maskBmp[py * w + px] > 128 {
                    continue
                }

                total += 1
                let off = (py * w + px) * 4
                let diff = (
                    abs(Double(pass1Bmp[off]) - Double(pass2Bmp[off])) +
                    abs(Double(pass1Bmp[off + 1]) - Double(pass2Bmp[off + 1])) +
                    abs(Double(pass1Bmp[off + 2]) - Double(pass2Bmp[off + 2]))
                ) / 3.0
                if diff > diffThreshold {
                    damage += 1
                }
            }
        }

        guard total > 0 else { return 0 }
        return Double(damage) / Double(total) * 100.0
    }

    /// Validates pass 2 result: checks for collateral damage outside the expanded mask.
    private func validatePass2(
        original: CGImage,
        pass1: CGImage,
        pass2: CGImage,
        expandedMask: CGImage,
        expandedBounds: [CGRect]
    ) -> Bool {
        let w = min(original.width, pass1.width, pass2.width)
        let h = min(original.height, pass1.height, pass2.height)
        guard w > 0, h > 0 else { return false }

        guard let origBmp = renderBitmap(original, w: w, h: h),
              let pass2Bmp = renderBitmap(pass2, w: w, h: h) else { return false }
        defer { origBmp.deallocate(); pass2Bmp.deallocate() }

        // Global check: overall preserve metrics
        var preservedCount = 0
        var totalPreserveDiff = 0.0

        for i in 0..<(w * h) {
            let off = i * 4
            let diff = (abs(Double(origBmp[off]) - Double(pass2Bmp[off])) +
                        abs(Double(origBmp[off+1]) - Double(pass2Bmp[off+1])) +
                        abs(Double(origBmp[off+2]) - Double(pass2Bmp[off+2]))) / 3.0
            if diff < 15 {
                preservedCount += 1
                totalPreserveDiff += diff
            }
        }

        let preservedPct = Double(preservedCount) / Double(w * h) * 100
        let avgPreserveDiff = preservedCount > 0 ? totalPreserveDiff / Double(preservedCount) : 999

        if debug {
            print("[PIPELINE] Validation: preserved=\(String(format: "%.1f", preservedPct))% avgDiff=\(String(format: "%.1f", avgPreserveDiff))")
        }

        if preservedPct < 70 || avgPreserveDiff > 5 {
            return false
        }

        // Local check: compare pass 1 vs pass 2 only in a ring around each expanded support.
        // Intended pass-2 changes inside the support must not be counted as collateral damage.
        for expandedBound in expandedBounds {
            guard let damagePct = Self.localIncrementalDamage(
                pass1: pass1,
                pass2: pass2,
                supportMask: expandedMask,
                focusBounds: expandedBound,
                outerMargin: 20
            ) else {
                continue
            }
            if debug {
                print(
                    "[PIPELINE] Local validation: support \(Int(expandedBound.origin.x)),\(Int(expandedBound.origin.y)) "
                    + "\(Int(expandedBound.width))×\(Int(expandedBound.height)) ring damage="
                    + "\(String(format: "%.1f", damagePct))%"
                )
            }
            if damagePct > 30 {
                return false
            }
        }

        return true
    }

    // MARK: - Helpers

    private func renderBitmap(_ image: CGImage, w: Int, h: Int) -> UnsafeMutablePointer<UInt8>? {
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        guard let ctx = CGContext(
            data: ptr, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { ptr.deallocate(); return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ptr
    }

    private func resizeCGImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0 else { return nil }
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func countWhitePixels(_ mask: CGImage) -> Int {
        let w = mask.width, h = mask.height
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w,
                                   space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return 0 }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h)
        var count = 0
        for i in 0..<(w * h) { if ptr[i] > 128 { count += 1 } }
        return count
    }
}
