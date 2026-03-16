import CoreGraphics
import Foundation

/// A candidate UI element blob detected in the residue analysis.
public struct CandidateBlob: Equatable {
    /// Pixel-level bounding box in the figure crop (top-left origin).
    public let bounds: CGRect
    /// Exact pixel support of the detected component in top-left image coordinates.
    public let pixelIndices: [Int]
    /// Number of pixels in the component support.
    public let pixelCount: Int
    /// Dilation radius applied when the component is merged into the pass-2 support mask.
    public let dilationRadius: Int
    /// Compactness: pixelCount / bounding-box area. Solid UI elements trend upward.
    public let compactness: Double
    /// Internal uniformity (0..1). Higher means flatter color / lower texture.
    public let uniformity: Double
    /// Boundary contrast: average edge difference against external neighbors.
    public let boundaryContrast: Double
    /// Fraction of the figure area this blob covers.
    public let relativeArea: Double
    /// Proximity of the candidate to the nearest OCR anchor within the search radius.
    public let anchorProximity: Double
    /// Fraction of the OCR text anchor covered by the candidate bbox.
    public let textCoverage: Double
    /// Whether pass 1 reduced the fragment count inside this component's bounding box.
    public let mergedAfterPass1: Bool
    /// Relative reduction of fragment count inside the candidate bbox after pass 1.
    public let fragmentReduction: Double
    /// Increase in largest-component compactness inside the candidate bbox after pass 1.
    public let compactnessGain: Double
    /// Relative reduction of raw pixel variance inside the candidate bbox after pass 1.
    public let varianceReduction: Double

    /// Continuous score that describes how much pass 1 made the candidate easier to separate.
    public var pass1DeltaScore: Double {
        let fragmentScore = min(1, max(0, fragmentReduction))
        let compactnessScore = min(1, max(0, compactnessGain) / 0.20)
        let varianceScore = min(1, max(0, varianceReduction) / 0.35)
        return fragmentScore * 0.45 + compactnessScore * 0.30 + varianceScore * 0.25
    }

    /// Multi-signal confidence score (0..1).
    public var confidence: Double {
        let compactnessScore = CandidateBlob.normalize(compactness, floor: 0.20, ceiling: 0.60)
        let uniformityScore = CandidateBlob.normalize(uniformity, floor: 0.45, ceiling: 0.85)
        let contrastScore = min(1, max(0, boundaryContrast / 40.0))
        let sizeScore = relativeArea <= 0.05 ? 1.0 : max(0, 1.0 - ((relativeArea - 0.05) / 0.05))
        let anchorScore = min(1, max(0, anchorProximity))
        let textCoverageScore = min(1, max(0, textCoverage))
        let mergeBonus = mergedAfterPass1 ? 1.0 : 0.0

        return compactnessScore * 0.18
            + uniformityScore * 0.08
            + contrastScore * 0.06
            + sizeScore * 0.08
            + anchorScore * 0.28
            + textCoverageScore * 0.16
            + pass1DeltaScore * 0.10
            + mergeBonus * 0.06
    }

    private static func normalize(_ value: Double, floor: Double, ceiling: Double) -> Double {
        guard ceiling > floor else { return value >= ceiling ? 1 : 0 }
        return min(1, max(0, (value - floor) / (ceiling - floor)))
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
    public let anchorProximity: Double
    public let textCoverage: Double
    public let mergedAfterPass1: Bool
    public let fragmentReduction: Double
    public let compactnessGain: Double
    public let varianceReduction: Double
    public let pass1DeltaScore: Double
    public let confidence: Double
    public let accepted: Bool
    public let rejectReason: String?
}

/// Analyzes a figure for residual UI element backgrounds (buttons, badges, labels)
/// using original-image component detection plus pass-1 delta scoring.
///
/// The original crop contributes precise candidate geometry.
/// The pass-1 crop contributes evidence that text removal made the region more
/// coherent, less fragmented, or less textured.
public struct ResidueAnalyzer {

    private struct TextAnchor {
        let rect: CGRect
        let textHeight: CGFloat
        let searchRadius: CGFloat
    }

    private struct PixelComponent {
        let id: Int
        let pixelIndices: [Int]
        let bounds: CGRect
        let pixelCount: Int
        let compactness: Double
        let uniformity: Double
        let boundaryContrast: Double
    }

    private struct FragmentStats {
        let count: Int
        let largestCompactness: Double
        let largestArea: Int
    }

    private let minConfidence: Double
    private let searchRadiusFactor: CGFloat
    private let debug: Bool

    public init(
        minConfidence: Double = 0.50,
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

        guard let origPtr = renderBitmap(originalCrop, width: w, height: h),
              let pass1Ptr = renderBitmap(pass1Result, width: w, height: h) else { return ([], []) }
        defer {
            origPtr.deallocate()
            pass1Ptr.deallocate()
        }

        let anchors = buildTextAnchors(textBounds: textBounds, width: w, height: h)
        let satMask = buildSaturationMask(ptr: origPtr, width: w, height: h, satThreshold: 0.40, valueThreshold: 0.25)
        let components = extractComponents(mask: satMask, ptr: origPtr, width: w, height: h)

        var candidates: [CandidateBlob] = []
        var debugInfo: [ResidueAnalysisDebugInfo] = []

        for component in components where component.pixelCount >= 50 {
            guard let anchor = nearestAnchor(for: component.bounds, anchors: anchors) else { continue }

            let bounds = component.bounds
            let relArea = Double(component.pixelCount) / figureArea
            let anchorDistance = rectDistance(bounds, anchor.rect)
            let anchorProximity = anchor.searchRadius > 0
                ? max(0, 1.0 - Double(anchorDistance / anchor.searchRadius))
                : 0
            let textCoverage = textCoverage(of: bounds, in: anchor.rect)
            let originalFragments = fragmentStats(
                rect: bounds,
                ptr: origPtr,
                width: w,
                height: h,
                satThreshold: 0.40,
                valueThreshold: 0.25
            )
            let pass1Fragments = fragmentStats(
                rect: bounds,
                ptr: pass1Ptr,
                width: w,
                height: h,
                satThreshold: 0.25,
                valueThreshold: 0.18
            )
            let originalVariance = regionVariance(rect: bounds, ptr: origPtr, width: w, height: h)
            let pass1Variance = regionVariance(rect: bounds, ptr: pass1Ptr, width: w, height: h)

            let fragmentReduction = max(
                0,
                Double(originalFragments.count - pass1Fragments.count) / Double(max(originalFragments.count, 1))
            )
            let compactnessGain = max(0, pass1Fragments.largestCompactness - originalFragments.largestCompactness)
            let varianceReduction = originalVariance > 1
                ? max(0, (originalVariance - pass1Variance) / originalVariance)
                : 0
            let mergedAfterPass1 = pass1Fragments.count < originalFragments.count

            let candidate = CandidateBlob(
                bounds: bounds,
                pixelIndices: component.pixelIndices,
                pixelCount: component.pixelCount,
                dilationRadius: dilationRadius(for: component, anchor: anchor),
                compactness: component.compactness,
                uniformity: component.uniformity,
                boundaryContrast: component.boundaryContrast,
                relativeArea: relArea,
                anchorProximity: anchorProximity,
                textCoverage: textCoverage,
                mergedAfterPass1: mergedAfterPass1,
                fragmentReduction: fragmentReduction,
                compactnessGain: compactnessGain,
                varianceReduction: varianceReduction
            )

            var rejectReason: String? = nil
            if candidate.confidence < minConfidence {
                rejectReason = "confidence \(String(format: "%.2f", candidate.confidence)) < \(minConfidence)"
            } else if relArea > 0.05 {
                rejectReason = "relative area \(String(format: "%.3f", relArea)) > 5%"
            }

            let accepted = rejectReason == nil
            debugInfo.append(
                ResidueAnalysisDebugInfo(
                    componentBounds: bounds,
                    pixelCount: component.pixelCount,
                    compactness: component.compactness,
                    uniformity: component.uniformity,
                    boundaryContrast: component.boundaryContrast,
                    relativeArea: relArea,
                    anchorProximity: anchorProximity,
                    textCoverage: textCoverage,
                    mergedAfterPass1: mergedAfterPass1,
                    fragmentReduction: fragmentReduction,
                    compactnessGain: compactnessGain,
                    varianceReduction: varianceReduction,
                    pass1DeltaScore: candidate.pass1DeltaScore,
                    confidence: candidate.confidence,
                    accepted: accepted,
                    rejectReason: rejectReason
                )
            )

            if debug {
                let status = accepted ? "ACCEPT" : "REJECT(\(rejectReason ?? ""))"
                print(
                    "[RESIDUE] bounds=(\(Int(bounds.origin.x)),\(Int(bounds.origin.y)) \(Int(bounds.width))×\(Int(bounds.height))) "
                    + "area=\(component.pixelCount) compact=\(String(format: "%.2f", component.compactness)) "
                    + "uniform=\(String(format: "%.2f", component.uniformity)) "
                    + "bContrast=\(String(format: "%.1f", component.boundaryContrast)) "
                    + "relArea=\(String(format: "%.4f", relArea)) "
                    + "anchor=\(String(format: "%.2f", anchorProximity)) "
                    + "textCov=\(String(format: "%.2f", textCoverage)) "
                    + "fragRed=\(String(format: "%.2f", fragmentReduction)) "
                    + "compGain=\(String(format: "%.2f", compactnessGain)) "
                    + "varRed=\(String(format: "%.2f", varianceReduction)) "
                    + "delta=\(String(format: "%.2f", candidate.pass1DeltaScore)) "
                    + "conf=\(String(format: "%.2f", candidate.confidence)) → \(status)"
                )
            }

            if accepted {
                candidates.append(candidate)
            }
        }

        if debug {
            print("[RESIDUE] total: \(debugInfo.count) components, \(candidates.count) accepted")
        }

        return (candidates, debugInfo)
    }

    // MARK: - Rendering

    private func renderBitmap(_ image: CGImage, width: Int, height: Int) -> UnsafeMutablePointer<UInt8>? {
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        guard let ctx = CGContext(
            data: ptr,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            ptr.deallocate()
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ptr
    }

    // MARK: - Text Anchors

    private func buildTextAnchors(textBounds: [CGRect], width: Int, height: Int) -> [TextAnchor] {
        textBounds.map { tb in
            let x = tb.origin.x * CGFloat(width)
            let y = CGFloat(height) - ((tb.origin.y + tb.height) * CGFloat(height))
            let w = max(1, tb.width * CGFloat(width))
            let h = max(1, tb.height * CGFloat(height))
            let rect = CGRect(x: x, y: y, width: w, height: h)
            return TextAnchor(rect: rect, textHeight: h, searchRadius: h * searchRadiusFactor)
        }
    }

    private func nearestAnchor(for bounds: CGRect, anchors: [TextAnchor]) -> TextAnchor? {
        var best: TextAnchor?
        var bestDistance = Double.greatestFiniteMagnitude

        for anchor in anchors {
            let distance = rectDistance(bounds, anchor.rect)
            guard distance <= anchor.searchRadius else { continue }
            if distance < bestDistance {
                bestDistance = distance
                best = anchor
            }
        }

        return best
    }

    private func rectDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx: CGFloat
        if a.maxX < b.minX {
            dx = b.minX - a.maxX
        } else if b.maxX < a.minX {
            dx = a.minX - b.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if a.maxY < b.minY {
            dy = b.minY - a.maxY
        } else if b.maxY < a.minY {
            dy = a.minY - b.maxY
        } else {
            dy = 0
        }

        return hypot(dx, dy)
    }

    private func textCoverage(of componentBounds: CGRect, in textRect: CGRect) -> Double {
        let intersection = componentBounds.intersection(textRect)
        guard !intersection.isEmpty else { return 0 }
        let textArea = textRect.width * textRect.height
        guard textArea > 0 else { return 0 }
        return min(1, max(0, (intersection.width * intersection.height) / textArea))
    }

    // MARK: - Original-image Evidence

    private func buildSaturationMask(
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        satThreshold: Double,
        valueThreshold: Double
    ) -> [Bool] {
        var mask = [Bool](repeating: false, count: width * height)
        for idx in 0..<(width * height) {
            let off = idx * 4
            let r = Double(ptr[off])
            let g = Double(ptr[off + 1])
            let b = Double(ptr[off + 2])
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let sat = maxC > 10 ? (maxC - minC) / maxC : 0
            let val = maxC / 255.0
            mask[idx] = sat > satThreshold && val > valueThreshold
        }
        return mask
    }

    private func extractComponents(
        mask: [Bool],
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int
    ) -> [PixelComponent] {
        var labels = [Int](repeating: -1, count: width * height)
        var rawComponents: [(pixels: [Int], minX: Int, maxX: Int, minY: Int, maxY: Int)] = []

        for startIndex in 0..<(width * height) {
            guard mask[startIndex], labels[startIndex] == -1 else { continue }

            let componentId = rawComponents.count
            var queue = [startIndex]
            var pixels: [Int] = []
            labels[startIndex] = componentId
            var head = 0

            let startX = startIndex % width
            let startY = startIndex / width
            var minX = startX, maxX = startX, minY = startY, maxY = startY

            while head < queue.count {
                let index = queue[head]
                head += 1
                pixels.append(index)

                let x = index % width
                let y = index / width
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)

                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let neighbor = ny * width + nx
                    guard mask[neighbor], labels[neighbor] == -1 else { continue }
                    labels[neighbor] = componentId
                    queue.append(neighbor)
                }
            }

            rawComponents.append((pixels: pixels, minX: minX, maxX: maxX, minY: minY, maxY: maxY))
        }

        var result: [PixelComponent] = []
        result.reserveCapacity(rawComponents.count)

        for (componentId, raw) in rawComponents.enumerated() {
            let pixelCount = raw.pixels.count
            guard pixelCount >= 50 else { continue }

            var sumR = 0.0, sumG = 0.0, sumB = 0.0
            var sumR2 = 0.0, sumG2 = 0.0, sumB2 = 0.0
            for index in raw.pixels {
                let off = index * 4
                let r = Double(ptr[off])
                let g = Double(ptr[off + 1])
                let b = Double(ptr[off + 2])
                sumR += r
                sumG += g
                sumB += b
                sumR2 += r * r
                sumG2 += g * g
                sumB2 += b * b
            }

            let n = Double(pixelCount)
            let avgVar = ((sumR2 / n - pow(sumR / n, 2))
                        + (sumG2 / n - pow(sumG / n, 2))
                        + (sumB2 / n - pow(sumB / n, 2))) / 3.0
            let uniformity = 1.0 / (1.0 + avgVar / 2000.0)

            let bboxW = raw.maxX - raw.minX + 1
            let bboxH = raw.maxY - raw.minY + 1
            let compactness = Double(pixelCount) / Double(bboxW * bboxH)
            let bounds = CGRect(x: raw.minX, y: raw.minY, width: bboxW, height: bboxH)

            result.append(
                PixelComponent(
                    id: componentId,
                    pixelIndices: raw.pixels,
                    bounds: bounds,
                    pixelCount: pixelCount,
                    compactness: compactness,
                    uniformity: uniformity,
                    boundaryContrast: boundaryContrast(
                        componentId: componentId,
                        pixelIndices: raw.pixels,
                        labels: labels,
                        ptr: ptr,
                        width: width,
                        height: height
                    )
                )
            )
        }

        return result
    }

    private func boundaryContrast(
        componentId: Int,
        pixelIndices: [Int],
        labels: [Int],
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int
    ) -> Double {
        let step = max(1, pixelIndices.count / 200)
        var totalDiff = 0.0
        var count = 0

        for i in stride(from: 0, to: pixelIndices.count, by: step) {
            let index = pixelIndices[i]
            let x = index % width
            let y = index / width
            let off = index * 4
            let r = Double(ptr[off])
            let g = Double(ptr[off + 1])
            let b = Double(ptr[off + 2])

            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let nx = x + dx
                let ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let neighbor = ny * width + nx
                guard labels[neighbor] != componentId else { continue }

                let noff = neighbor * 4
                totalDiff += abs(r - Double(ptr[noff]))
                    + abs(g - Double(ptr[noff + 1]))
                    + abs(b - Double(ptr[noff + 2]))
                count += 1
            }
        }

        return count > 0 ? totalDiff / Double(count) / 3.0 : 0
    }

    // MARK: - Pass-1 Delta Analysis

    private func regionVariance(
        rect: CGRect,
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int
    ) -> Double {
        let minX = max(0, Int(floor(rect.minX)))
        let minY = max(0, Int(floor(rect.minY)))
        let maxX = min(width, Int(ceil(rect.maxX)))
        let maxY = min(height, Int(ceil(rect.maxY)))
        guard minX < maxX, minY < maxY else { return 0 }

        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        var sumR2 = 0.0, sumG2 = 0.0, sumB2 = 0.0
        var count = 0.0

        for py in minY..<maxY {
            for px in minX..<maxX {
                let off = (py * width + px) * 4
                let r = Double(ptr[off])
                let g = Double(ptr[off + 1])
                let b = Double(ptr[off + 2])
                sumR += r
                sumG += g
                sumB += b
                sumR2 += r * r
                sumG2 += g * g
                sumB2 += b * b
                count += 1
            }
        }

        guard count > 1 else { return 0 }
        let varR = sumR2 / count - pow(sumR / count, 2)
        let varG = sumG2 / count - pow(sumG / count, 2)
        let varB = sumB2 / count - pow(sumB / count, 2)
        return (varR + varG + varB) / 3.0
    }

    private func fragmentStats(
        rect: CGRect,
        ptr: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        satThreshold: Double,
        valueThreshold: Double
    ) -> FragmentStats {
        let minX = max(0, Int(floor(rect.minX)))
        let minY = max(0, Int(floor(rect.minY)))
        let maxX = min(width, Int(ceil(rect.maxX)))
        let maxY = min(height, Int(ceil(rect.maxY)))
        guard minX < maxX, minY < maxY else {
            return FragmentStats(count: 0, largestCompactness: 0, largestArea: 0)
        }

        let regionW = maxX - minX
        let regionH = maxY - minY
        var visited = [Bool](repeating: false, count: regionW * regionH)
        var components: [(area: Int, compactness: Double)] = []

        for startY in 0..<regionH {
            for startX in 0..<regionW {
                let localIndex = startY * regionW + startX
                guard !visited[localIndex] else { continue }

                let px = minX + startX
                let py = minY + startY
                let pixelIndex = py * width + px
                guard pixelMatches(ptr: ptr, index: pixelIndex, satThreshold: satThreshold, valueThreshold: valueThreshold) else {
                    continue
                }

                visited[localIndex] = true
                var queue = [(startX, startY)]
                var head = 0
                var minLocalX = startX, maxLocalX = startX, minLocalY = startY, maxLocalY = startY

                while head < queue.count {
                    let (cx, cy) = queue[head]
                    head += 1
                    minLocalX = min(minLocalX, cx)
                    maxLocalX = max(maxLocalX, cx)
                    minLocalY = min(minLocalY, cy)
                    maxLocalY = max(maxLocalY, cy)

                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nx = cx + dx
                        let ny = cy + dy
                        guard nx >= 0, nx < regionW, ny >= 0, ny < regionH else { continue }
                        let neighborLocal = ny * regionW + nx
                        guard !visited[neighborLocal] else { continue }

                        let neighborPixel = (minY + ny) * width + (minX + nx)
                        guard pixelMatches(ptr: ptr, index: neighborPixel, satThreshold: satThreshold, valueThreshold: valueThreshold) else {
                            continue
                        }

                        visited[neighborLocal] = true
                        queue.append((nx, ny))
                    }
                }

                let area = queue.count
                guard area >= 20 else { continue }
                let bboxArea = (maxLocalX - minLocalX + 1) * (maxLocalY - minLocalY + 1)
                let compactness = bboxArea > 0 ? Double(area) / Double(bboxArea) : 0
                components.append((area: area, compactness: compactness))
            }
        }

        components.sort { lhs, rhs in
            if lhs.area == rhs.area {
                return lhs.compactness > rhs.compactness
            }
            return lhs.area > rhs.area
        }

        return FragmentStats(
            count: components.count,
            largestCompactness: components.first?.compactness ?? 0,
            largestArea: components.first?.area ?? 0
        )
    }

    private func pixelMatches(
        ptr: UnsafePointer<UInt8>,
        index: Int,
        satThreshold: Double,
        valueThreshold: Double
    ) -> Bool {
        let off = index * 4
        let r = Double(ptr[off])
        let g = Double(ptr[off + 1])
        let b = Double(ptr[off + 2])
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let sat = maxC > 10 ? (maxC - minC) / maxC : 0
        let val = maxC / 255.0
        return sat > satThreshold && val > valueThreshold
    }

    // MARK: - Support Growth

    private func dilationRadius(for component: PixelComponent, anchor: TextAnchor) -> Int {
        let componentScale = max(component.bounds.width, component.bounds.height) * 0.10
        let textScale = anchor.textHeight * 0.45
        return max(3, min(14, Int(round(max(componentScale, textScale)))))
    }
}
