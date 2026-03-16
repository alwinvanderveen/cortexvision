import CoreGraphics
import Foundation

/// A candidate UI element blob detected in the residue analysis.
public struct CandidateBlob: Equatable {
    /// Pixel-level bounding box in the figure crop (top-left origin).
    public let bounds: CGRect
    /// Number of high-saturation pixels in this blob.
    public let pixelCount: Int
    /// Compactness: pixelCount / bounding box area. Solid UI elements > 0.4.
    public let compactness: Double
    /// Internal uniformity (0..1). High = solid color, low = textured photo.
    public let uniformity: Double
    /// Boundary contrast: average color difference at blob edge vs external neighbors.
    public let boundaryContrast: Double
    /// Fraction of the figure area this blob covers.
    public let relativeArea: Double
    /// Whether pass-1 merged originally separate fragments into this blob (UI-element signal).
    public let mergedAfterPass1: Bool

    /// Multi-signal confidence score (0..1). All signals are always evaluated.
    public var confidence: Double {
        let totalWeight = 6.0
        var score = 0.0

        if compactness > 0.4 { score += 1 }      // solid shape
        if uniformity > 0.5 { score += 1 }        // solid color
        if boundaryContrast > 15 { score += 1 }   // sharp edge against photo
        if relativeArea < 0.05 { score += 1 }     // reasonable size for UI element
        if mergedAfterPass1 { score += 2 }         // fragments merged = structural UI confirmation (2×)

        return score / totalWeight
    }
}

/// Debug information for a single analyzed component.
public struct ResidueAnalysisDebugInfo {
    public let componentBounds: CGRect
    public let pixelCount: Int
    public let compactness: Double
    public let uniformity: Double
    public let boundaryContrast: Double
    public let relativeArea: Double
    public let mergedAfterPass1: Bool
    public let confidence: Double
    public let accepted: Bool
    public let rejectReason: String?
}

/// Analyzes a figure for residual UI element backgrounds (buttons, badges, labels)
/// using a two-image comparison strategy:
///
/// 1. Detect high-saturation components on the ORIGINAL image (where the button is fully intact)
/// 2. Verify on the PASS-1 image that text-removal caused fragment merging (UI-element confirmation)
/// 3. Use the original's blob shape for the mask (not the degraded pass-1 version)
///
/// This avoids the problem of analyzing LaMa's blended output where UI elements
/// have reduced saturation/uniformity in the former text region.
public struct ResidueAnalyzer {

    private let minConfidence: Double
    private let searchRadiusFactor: CGFloat
    private let debug: Bool

    public init(
        minConfidence: Double = 0.67,  // requires merge signal OR 4/4 other signals
        searchRadiusFactor: CGFloat = 4.0,
        debug: Bool = false
    ) {
        self.minConfidence = minConfidence
        self.searchRadiusFactor = searchRadiusFactor
        self.debug = debug || ProcessInfo.processInfo.environment["FIGURE_DEBUG"] == "1"
    }

    /// Analyzes the original and pass-1 figure crops for UI element residue near text bounds.
    ///
    /// - Parameters:
    ///   - originalCrop: The figure crop BEFORE any inpainting.
    ///   - pass1Result: The figure crop AFTER pass-1 (text-only) inpainting.
    ///   - textBounds: Text block bounds relative to the figure crop, normalized (0..1), bottom-left origin.
    /// - Returns: Accepted candidate blobs and debug info.
    public func analyze(
        originalCrop: CGImage,
        pass1Result: CGImage,
        textBounds: [CGRect]
    ) -> (candidates: [CandidateBlob], debugInfo: [ResidueAnalysisDebugInfo]) {
        let w = originalCrop.width
        let h = originalCrop.height
        let figureArea = Double(w * h)
        guard w > 0, h > 0, !textBounds.isEmpty else { return ([], []) }

        // Render ORIGINAL to bitmap — this is where UI elements are fully intact
        guard let origCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return ([], []) }
        origCtx.draw(originalCrop, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let origData = origCtx.data else { return ([], []) }
        let origPtr = origData.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // Render PASS-1 to bitmap — for fragment-merge verification
        guard let p1Ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return ([], []) }
        // Pass-1 may be a different size (512→resized), render to same dimensions
        let p1W = pass1Result.width, p1H = pass1Result.height
        let useW = min(w, p1W), useH = min(h, p1H)
        p1Ctx.draw(pass1Result, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let p1Data = p1Ctx.data else { return ([], []) }
        let p1Ptr = p1Data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // Build saturation mask on the ORIGINAL image
        var satMask = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            let off = i * 4
            let r = Double(origPtr[off]), g = Double(origPtr[off+1]), b = Double(origPtr[off+2])
            let maxC = max(r, g, b), minC = min(r, g, b)
            let sat = maxC > 10 ? (maxC - minC) / maxC : 0
            let val = maxC / 255.0
            satMask[i] = sat > 0.4 && val > 0.25
        }

        // For each text bound, find connected components in the search ROI
        var allCandidates: [CandidateBlob] = []
        var allDebug: [ResidueAnalysisDebugInfo] = []
        var processedPixels = Set<Int>()

        for tb in textBounds {
            let textH = tb.height * CGFloat(h)
            let radius = textH * searchRadiusFactor

            // Convert text bound from normalized bottom-left to pixel top-left
            let tbPx = Int(tb.origin.x * CGFloat(w))
            let tbPy = h - Int((tb.origin.y + tb.height) * CGFloat(h))
            let tbPw = max(1, Int(tb.width * CGFloat(w)))
            let tbPh = max(1, Int(tb.height * CGFloat(h)))

            let roiX = max(0, tbPx - Int(radius))
            let roiY = max(0, tbPy - Int(radius))
            let roiX2 = min(w, tbPx + tbPw + Int(radius))
            let roiY2 = min(h, tbPy + tbPh + Int(radius))

            // BFS connected components on the ORIGINAL's saturation mask
            for startY in roiY..<roiY2 {
                for startX in roiX..<roiX2 {
                    let idx = startY * w + startX
                    guard satMask[idx], !processedPixels.contains(idx) else { continue }

                    var queue = [(startX, startY)]
                    processedPixels.insert(idx)
                    var minX = startX, maxX = startX, minY = startY, maxY = startY
                    var sumR = 0.0, sumG = 0.0, sumB = 0.0
                    var sumR2 = 0.0, sumG2 = 0.0, sumB2 = 0.0
                    var head = 0

                    while head < queue.count {
                        let (cx, cy) = queue[head]; head += 1
                        let off = (cy * w + cx) * 4
                        let r = Double(origPtr[off]), g = Double(origPtr[off+1]), b = Double(origPtr[off+2])
                        sumR += r; sumG += g; sumB += b
                        sumR2 += r*r; sumG2 += g*g; sumB2 += b*b
                        minX = min(minX, cx); maxX = max(maxX, cx)
                        minY = min(minY, cy); maxY = max(maxY, cy)

                        for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                            let nx = cx + dx, ny = cy + dy
                            guard nx >= roiX, nx < roiX2, ny >= roiY, ny < roiY2 else { continue }
                            let ni = ny * w + nx
                            guard satMask[ni], !processedPixels.contains(ni) else { continue }
                            processedPixels.insert(ni)
                            queue.append((nx, ny))
                        }
                    }

                    let area = queue.count
                    guard area >= 50 else { continue }

                    let bboxW = maxX - minX + 1, bboxH = maxY - minY + 1
                    let compactness = Double(area) / Double(bboxW * bboxH)

                    let n = Double(area)
                    let avgVar = ((sumR2/n - (sumR/n)*(sumR/n)) +
                                  (sumG2/n - (sumG/n)*(sumG/n)) +
                                  (sumB2/n - (sumB/n)*(sumB/n))) / 3.0
                    let uniformity = 1.0 / (1.0 + avgVar / 2000.0)

                    let bContrast = boundaryContrast(
                        queue: queue, ptr: origPtr, w: w, h: h,
                        processedPixels: processedPixels
                    )

                    // Fragment-merge verification: count components in same bounding box on pass-1
                    let mergedAfterPass1 = verifyMerge(
                        bboxX: minX, bboxY: minY, bboxW: bboxW, bboxH: bboxH,
                        origPtr: origPtr, p1Ptr: p1Ptr, w: w, h: h,
                        origComponentCount: countFragments(
                            x: minX, y: minY, w: bboxW, h: bboxH,
                            ptr: origPtr, imgW: w, imgH: h
                        )
                    )

                    let relArea = Double(area) / figureArea
                    let bounds = CGRect(x: minX, y: minY, width: bboxW, height: bboxH)

                    let candidate = CandidateBlob(
                        bounds: bounds, pixelCount: area,
                        compactness: compactness, uniformity: uniformity,
                        boundaryContrast: bContrast, relativeArea: relArea,
                        mergedAfterPass1: mergedAfterPass1
                    )

                    var rejectReason: String? = nil
                    if candidate.confidence < minConfidence {
                        rejectReason = "confidence \(String(format: "%.2f", candidate.confidence)) < \(minConfidence)"
                    } else if relArea > 0.05 {
                        rejectReason = "relative area \(String(format: "%.3f", relArea)) > 5%"
                    }

                    let accepted = rejectReason == nil

                    allDebug.append(ResidueAnalysisDebugInfo(
                        componentBounds: bounds, pixelCount: area,
                        compactness: compactness, uniformity: uniformity,
                        boundaryContrast: bContrast, relativeArea: relArea,
                        mergedAfterPass1: mergedAfterPass1,
                        confidence: candidate.confidence,
                        accepted: accepted, rejectReason: rejectReason
                    ))

                    if debug {
                        let status = accepted ? "ACCEPT" : "REJECT(\(rejectReason ?? ""))"
                        print("[RESIDUE] bounds=(\(minX),\(minY) \(bboxW)×\(bboxH)) area=\(area) compact=\(String(format: "%.2f", compactness)) uniform=\(String(format: "%.2f", uniformity)) bContrast=\(String(format: "%.1f", bContrast)) relArea=\(String(format: "%.4f", relArea)) merged=\(mergedAfterPass1) conf=\(String(format: "%.2f", candidate.confidence)) → \(status)")
                    }

                    if accepted { allCandidates.append(candidate) }
                }
            }
        }

        if debug {
            print("[RESIDUE] total: \(allDebug.count) components, \(allCandidates.count) accepted")
        }

        return (candidates: allCandidates, debugInfo: allDebug)
    }

    // MARK: - Fragment Merge Verification

    /// Counts high-saturation fragments in a bounding box region.
    private func countFragments(x: Int, y: Int, w: Int, h: Int,
                                 ptr: UnsafePointer<UInt8>, imgW: Int, imgH: Int) -> Int {
        var visited = [Bool](repeating: false, count: w * h)
        var fragments = 0

        for ry in 0..<h {
            for rx in 0..<w {
                let px = x + rx, py = y + ry
                guard px < imgW, py < imgH else { continue }
                let localIdx = ry * w + rx
                guard !visited[localIdx] else { continue }

                let off = (py * imgW + px) * 4
                let r = Double(ptr[off]), g = Double(ptr[off+1]), b = Double(ptr[off+2])
                let maxC = max(r, g, b), minC = min(r, g, b)
                let sat = maxC > 10 ? (maxC - minC) / maxC : 0
                guard sat > 0.4, maxC / 255.0 > 0.25 else { continue }

                // BFS this fragment
                fragments += 1
                var queue = [(rx, ry)]
                visited[localIdx] = true
                var qHead = 0
                while qHead < queue.count {
                    let (cx, cy) = queue[qHead]; qHead += 1
                    for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                        let ni = ny * w + nx
                        guard !visited[ni] else { continue }
                        let npx = x + nx, npy = y + ny
                        guard npx < imgW, npy < imgH else { continue }
                        let noff = (npy * imgW + npx) * 4
                        let nr = Double(ptr[noff]), ng = Double(ptr[noff+1]), nb = Double(ptr[noff+2])
                        let nmaxC = max(nr, ng, nb), nminC = min(nr, ng, nb)
                        let nsat = nmaxC > 10 ? (nmaxC - nminC) / nmaxC : 0
                        guard nsat > 0.4, nmaxC / 255.0 > 0.25 else { continue }
                        visited[ni] = true
                        queue.append((nx, ny))
                    }
                }
            }
        }
        return fragments
    }

    /// Verifies that pass-1 merged originally separate fragments in the same bounding box.
    /// This is a strong UI-element signal: text removal causes button fragments to merge,
    /// but photo content fragments do not merge after text removal.
    private func verifyMerge(bboxX: Int, bboxY: Int, bboxW: Int, bboxH: Int,
                              origPtr: UnsafePointer<UInt8>,
                              p1Ptr: UnsafePointer<UInt8>,
                              w: Int, h: Int,
                              origComponentCount: Int) -> Bool {
        let p1Count = countFragments(x: bboxX, y: bboxY, w: bboxW, h: bboxH,
                                      ptr: p1Ptr, imgW: w, imgH: h)
        // Merge confirmed if pass-1 has fewer fragments than original
        return p1Count < origComponentCount
    }

    // MARK: - Boundary Contrast

    private func boundaryContrast(
        queue: [(Int, Int)], ptr: UnsafePointer<UInt8>,
        w: Int, h: Int, processedPixels: Set<Int>
    ) -> Double {
        var totalDiff = 0.0, count = 0
        let step = max(1, queue.count / 200)
        for i in stride(from: 0, to: queue.count, by: step) {
            let (cx, cy) = queue[i]
            let off = (cy * w + cx) * 4
            let r = Double(ptr[off]), g = Double(ptr[off+1]), b = Double(ptr[off+2])
            for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                let ni = ny * w + nx
                if processedPixels.contains(ni) { continue }
                let noff = ni * 4
                totalDiff += abs(r - Double(ptr[noff])) + abs(g - Double(ptr[noff+1])) + abs(b - Double(ptr[noff+2]))
                count += 1
            }
        }
        return count > 0 ? totalDiff / Double(count) / 3.0 : 0
    }
}
