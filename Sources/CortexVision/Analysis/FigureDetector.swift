import CoreGraphics
import CoreVideo
import Foundation
import Vision

// MARK: - Spatial Relationship Classification

/// Classifies the spatial relationship between a figure and a text block.
/// Used by the expansion pipeline to determine which edges are constrained by text.
public enum TextFigureRelation: Equatable, Sendable {
    /// Text is to the right of the figure (shares vertical span, separated horizontally)
    case adjacentRight
    /// Text is to the left of the figure
    case adjacentLeft
    /// Text is above the figure (Vision coords: higher Y)
    case adjacentAbove
    /// Text is below the figure (Vision coords: lower Y)
    case adjacentBelow
    /// Text is ON the figure (overlay) — the pixels behind the text are figure content,
    /// not page background. This text should be kept as part of the figure, not trimmed.
    case overlayOnFigure
    /// Text intersects the figure region substantially
    case overlapping
    /// Text is far from the figure, no meaningful relationship
    case disjoint
}

/// Edges that can be blocked by adjacent text.
public enum ExpansionEdge: Hashable, Sendable {
    case top, bottom, left, right
}

/// Detects figures (charts, diagrams, photos, tables) in a captured image using
/// Apple's foreground instance mask (subject lifting) API for pixel-perfect detection,
/// with attention-based saliency as fallback. Excludes regions that overlap with known
/// text and regions with low visual complexity (uniform color).
public final class FigureDetector: Sendable {
    /// Minimum figure area as a fraction of the total image (0..1). Default: 3%.
    private let minimumAreaFraction: CGFloat

    /// Overlap threshold for merging overlapping detections (0..1). Default: 50%.
    private let mergeOverlapThreshold: CGFloat

    /// Overlap threshold for text exclusion: if this fraction of a figure overlaps text, exclude it.
    private let textOverlapExclusionThreshold: CGFloat

    /// Minimum confidence for saliency detections (0..1). Default: 0.3.
    private let minimumSaliencyConfidence: Float

    /// Minimum color variance (standard deviation) to consider a region as a figure.
    /// Regions with uniform color (like white background) are excluded.
    private let minimumColorVariance: CGFloat

    /// Enable pipeline debug output. Set to true to print per-pass diagnostics.
    /// Enable pipeline debug output. Set to true or use FIGURE_DEBUG=1 env var.
    public let debug: Bool

    public init(
        minimumAreaFraction: CGFloat = 0.03,
        mergeOverlapThreshold: CGFloat = 0.5,
        textOverlapExclusionThreshold: CGFloat = 0.4,
        minimumSaliencyConfidence: Float = 0.0,
        minimumColorVariance: CGFloat = 20.0,
        debug: Bool? = nil
    ) {
        self.minimumAreaFraction = minimumAreaFraction
        self.mergeOverlapThreshold = mergeOverlapThreshold
        self.textOverlapExclusionThreshold = textOverlapExclusionThreshold
        self.minimumSaliencyConfidence = minimumSaliencyConfidence
        self.minimumColorVariance = minimumColorVariance
        self.debug = debug ?? (ProcessInfo.processInfo.environment["FIGURE_DEBUG"] == "1")
    }

    private func dbg(_ msg: @autoclosure () -> String) {
        guard debug else { return }
        print("[FigureDetector] \(msg())")
    }

    /// Detect figures in an image, excluding regions covered by text.
    ///
    /// Uses `VNGenerateForegroundInstanceMaskRequest` (Apple's subject lifting API)
    /// for pixel-perfect figure detection. Falls back to saliency-based detection
    /// if the instance mask approach finds no figures.
    ///
    /// - Parameters:
    ///   - image: The captured image to analyze.
    ///   - textBounds: Normalized bounding boxes of recognized text blocks (from OCR).
    /// - Returns: A `FigureDetectionResult` with detected figures, each with extracted CGImage.
    public func detectFigures(
        in image: CGImage,
        textBounds: [CGRect] = []
    ) async throws -> FigureDetectionResult {
        // === HYBRID PIPELINE (Gate 8: detection quality over performance) ===
        //
        // Both detection methods run in parallel and results are merged:
        //   1. DocLayout-YOLO — trained on documents, excels at standard figures/tables.
        //   2. Vision (saliency + instance mask) — catches hero banners, photo backgrounds,
        //      dark backgrounds, and mixed-media content.
        //
        // Merging strategy: DocLayout candidates are added to the Vision pipeline's
        // candidate list. Overlapping detections are merged. This ensures no regression
        // on existing tests while adding DocLayout's document-analysis capability.

        dbg("=== PIPELINE START (image \(image.width)×\(image.height)) ===")
        dbg("textBounds (\(textBounds.count)): \(textBounds.map { "(\(String(format:"%.3f %.3f %.3f %.3f", $0.minX, $0.minY, $0.width, $0.height)))" }.joined(separator: " "))")

        let subjectBounds = (try? await findSubjectBounds(in: image, textBounds: textBounds)) ?? []
        dbg("subjectBounds (\(subjectBounds.count)): \(subjectBounds.map { "(\(String(format:"%.3f %.3f %.3f %.3f", $0.minX, $0.minY, $0.width, $0.height)))" }.joined(separator: " "))")

        // --- DocLayout-YOLO candidates ---
        let docLayoutCandidates = docLayoutToCandidates(
            detectWithDocLayout(in: image, textBounds: textBounds)
        )

        // --- Vision pipeline (saliency + instance mask) with DocLayout candidates merged ---
        return try await detectWithSaliency(
            in: image, textBounds: textBounds, subjectBounds: subjectBounds,
            additionalCandidates: docLayoutCandidates
        )
    }

    // MARK: - DocLayout-YOLO Detection

    /// Attempts figure detection using the DocLayout-YOLO model via ONNX Runtime.
    /// Returns an empty array if the model is unavailable or finds no figures.
    private func detectWithDocLayout(in image: CGImage, textBounds: [CGRect]) -> [LayoutDetection] {
        guard let detector = try? DocLayoutDetector() else { return [] }
        guard let detections = try? detector.detect(in: image, confidenceThreshold: 0.15) else { return [] }
        return detections.filter { LayoutClass.figureClasses.contains($0.layoutClass) }
    }

    /// Converts DocLayout detections (top-left origin) to FigureCandidates (Vision bottom-left origin).
    private func docLayoutToCandidates(_ detections: [LayoutDetection]) -> [FigureCandidate] {
        detections.map { detection in
            FigureCandidate(
                bounds: CGRect(
                    x: detection.bounds.origin.x,
                    y: 1.0 - detection.bounds.origin.y - detection.bounds.height,
                    width: detection.bounds.width,
                    height: detection.bounds.height
                ),
                source: .saliency,
                confidence: Double(detection.confidence),
                evidence: [.salient, .distinctFromBackground]
            )
        }
    }

    // MARK: - Subject Detection (Instance Mask)

    /// Uses VNGenerateForegroundInstanceMaskRequest to find foreground subject bounding
    /// boxes. Runs on the original image (no text erasure) to avoid creating artifacts
    /// on non-white backgrounds. Text-overlapping instances are filtered via spatial
    /// classification instead.
    /// Returns normalized bounding boxes in Vision coordinates (bottom-left origin).
    private func findSubjectBounds(
        in image: CGImage,
        textBounds: [CGRect]
    ) async throws -> [CGRect] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let obs = request.results?.first else { return [] }
        let allInstances = obs.allInstances
        guard !allInstances.isEmpty else { return [] }

        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        var bounds: [CGRect] = []
        for instance in allInstances {
            let mask = try obs.generateScaledMaskForImage(
                forInstances: IndexSet([instance]), from: handler
            )
            if let rect = boundingBoxFromMask(mask, imageWidth: imageWidth, imageHeight: imageHeight),
               rect.width * rect.height >= minimumAreaFraction {
                // Filter out instances that are mostly text
                let textOverlap = textOverlapFraction(region: rect, textBounds: textBounds)
                if textOverlap < 0.4 {
                    bounds.append(rect)
                }
            }
        }

        return bounds
    }

    /// Computes the normalized bounding box (Vision coordinates, bottom-left origin)
    /// of non-zero pixels in a grayscale mask CVPixelBuffer.
    private func boundingBoxFromMask(
        _ mask: CVPixelBuffer, imageWidth: CGFloat, imageHeight: CGFloat
    ) -> CGRect? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else { return nil }

        // The mask from generateScaledMaskForImage uses OneComponent32Float pixel format.
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size
        let ptr = baseAddress.assumingMemoryBound(to: Float32.self)

        var minX = maskWidth
        var maxX = 0
        var minY = maskHeight
        var maxY = 0

        for y in 0..<maskHeight {
            let rowOffset = y * floatsPerRow
            for x in 0..<maskWidth {
                if ptr[rowOffset + x] > 0 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minX <= maxX, minY <= maxY else { return nil }

        // Convert pixel coordinates to normalized Vision coordinates (bottom-left origin).
        // The mask is in top-left origin (like CGImage), so we need to flip Y.
        let normX = CGFloat(minX) / CGFloat(maskWidth)
        let normW = CGFloat(maxX - minX + 1) / CGFloat(maskWidth)
        let normH = CGFloat(maxY - minY + 1) / CGFloat(maskHeight)
        let normY = 1.0 - CGFloat(maxY + 1) / CGFloat(maskHeight)

        return CGRect(x: normX, y: normY, width: normW, height: normH)
    }

    // MARK: - Saliency-Based Detection

    /// Primary detection using attention-based saliency to find rectangular figure regions.
    /// Subject bounds from instance mask are used to expand saliency regions so that
    /// foreground subjects at edges are not cut off.
    private func detectWithSaliency(
        in image: CGImage,
        textBounds: [CGRect],
        subjectBounds: [CGRect] = [],
        additionalCandidates: [FigureCandidate] = []
    ) async throws -> FigureDetectionResult {
        // === PASS 1: Evidence Gathering ===
        var candidates = try await pass1_gatherEvidence(
            image: image, textBounds: textBounds, subjectBounds: subjectBounds
        )
        dbg("PASS1 candidates (\(candidates.count)):")
        for (i, c) in candidates.enumerated() {
            dbg("  [\(i)] src=\(c.source) conf=\(String(format:"%.2f",c.confidence)) ev=\(c.evidence) bounds=(\(String(format:"%.3f %.3f %.3f %.3f",c.bounds.minX,c.bounds.minY,c.bounds.width,c.bounds.height)))")
        }

        // Merge DocLayout-YOLO candidates that don't overlap with existing candidates
        for docCandidate in additionalCandidates {
            let dominated = candidates.contains { existing in
                let inter = existing.bounds.intersection(docCandidate.bounds)
                guard !inter.isNull else { return false }
                let interArea = inter.width * inter.height
                let docArea = docCandidate.bounds.width * docCandidate.bounds.height
                return docArea > 0 && interArea / docArea > 0.5
            }
            if !dominated {
                candidates.append(docCandidate)
            }
        }

        // === PASS 2: Classification & Filtering ===
        let filtered = pass2_classifyAndFilter(
            candidates: candidates, textBounds: textBounds, subjectBounds: subjectBounds
        )
        dbg("PASS2 filtered (\(filtered.count)):")
        for (i, c) in filtered.enumerated() {
            dbg("  [\(i)] bounds=(\(String(format:"%.3f %.3f %.3f %.3f",c.bounds.minX,c.bounds.minY,c.bounds.width,c.bounds.height)))")
        }

        // === PASS 3: Boundary Refinement ===
        let refined = pass3_refineBoundaries(
            candidates: filtered, image: image, textBounds: textBounds, subjectBounds: subjectBounds
        )

        dbg("PASS3 refined (\(refined.count)):")
        for (i, c) in refined.enumerated() {
            dbg("  [\(i)] bounds=(\(String(format:"%.3f %.3f %.3f %.3f",c.bounds.minX,c.bounds.minY,c.bounds.width,c.bounds.height)))")
        }

        // === PASS 4: Extraction & Post-Processing ===
        var result = pass4_extractAndValidate(
            candidates: refined, image: image, textBounds: textBounds, subjectBounds: subjectBounds
        )
        dbg("PASS4 figures (\(result.figures.count)):")
        for (i, f) in result.figures.enumerated() {
            dbg("  [\(i)] bounds=(\(String(format:"%.3f %.3f %.3f %.3f",f.bounds.minX,f.bounds.minY,f.bounds.width,f.bounds.height))) img=\(f.extractedImage.map { "\($0.width)×\($0.height)" } ?? "nil")")
        }

        // === PASS 5: Content-analysis fallback ===
        // When saliency points at the wrong region and PASS4 yields 0 figures,
        // scan the full image for content regions that saliency missed.
        if result.figures.isEmpty {
            dbg("PASS5 content-analysis fallback (no figures from primary pipeline)")
            let fullRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
            let fullMap = FigureDetector.buildContentMap(
                in: image, region: fullRegion, textBounds: textBounds
            )
            let contentRegions = FigureDetector.findContentRegions(in: fullMap)
            let minArea = minimumAreaFraction
            let fallbackCandidates = contentRegions
                .filter { $0.width * $0.height >= minArea }
                .map { FigureCandidate(
                    bounds: $0, source: .saliency, confidence: 0.0,
                    evidence: [.salient]
                )}

            dbg("  contentRegions: \(contentRegions.count), viable: \(fallbackCandidates.count)")
            for (i, c) in fallbackCandidates.enumerated() {
                dbg("  [\(i)] bounds=(\(String(format:"%.3f %.3f %.3f %.3f",c.bounds.minX,c.bounds.minY,c.bounds.width,c.bounds.height)))")
            }

            if !fallbackCandidates.isEmpty {
                let fallbackResult = pass4_extractAndValidate(
                    candidates: fallbackCandidates, image: image,
                    textBounds: textBounds, subjectBounds: subjectBounds
                )
                dbg("  PASS5 figures: \(fallbackResult.figures.count)")
                if !fallbackResult.figures.isEmpty {
                    result = fallbackResult
                }
            }
        }

        dbg("=== PIPELINE END ===")
        return result
    }

    // MARK: - Pass 1: Evidence Gathering

    /// Collects all detection signals: saliency regions, instance mask subjects.
    /// Builds initial FigureCandidate list. No filtering — just evidence collection.
    private func pass1_gatherEvidence(
        image: CGImage,
        textBounds: [CGRect],
        subjectBounds: [CGRect]
    ) async throws -> [FigureCandidate] {
        let salientRegions = try await findSalientRegions(in: image)

        var candidates: [FigureCandidate] = []

        // Saliency candidates: filter text overlap, trim, size filter
        let nonTextRegions = excludeTextRegions(salientRegions, textBounds: textBounds)
        let trimmedRegions = nonTextRegions.map { trimTextFromRegion($0, textBounds: textBounds) }
        let sizedRegions = trimmedRegions.filter { $0.width * $0.height >= minimumAreaFraction }

        for bounds in sizedRegions {
            candidates.append(FigureCandidate(
                bounds: bounds,
                source: .saliency,
                confidence: 0.5,
                evidence: [.salient]
            ))
        }

        // Cross-reference: boost confidence for saliency candidates with subject overlap
        for i in 0..<candidates.count {
            let hasSubject = subjectBounds.contains { subject in
                let inter = candidates[i].bounds.intersection(subject)
                guard !inter.isNull else { return false }
                let sArea = subject.width * subject.height
                return sArea > 0 && (inter.width * inter.height) / sArea > 0.20
            }
            if hasSubject {
                candidates[i].evidence.insert(.hasSubject)
                candidates[i].confidence += 0.3
            }
        }

        // Subject fallback: add uncovered instance mask subjects as candidates.
        // This catches figures that saliency misses (e.g. bottom-positioned photos)
        // because instance mask is position-agnostic.
        for subject in subjectBounds {
            let coveredBySaliency = candidates.contains { candidate in
                let inter = candidate.bounds.intersection(subject)
                guard !inter.isNull else { return false }
                let sArea = subject.width * subject.height
                return sArea > 0 && (inter.width * inter.height) / sArea > 0.20
            }
            if !coveredBySaliency {
                candidates.append(FigureCandidate(
                    bounds: subject,
                    source: .promoted,
                    confidence: 0.4,
                    evidence: [.hasSubject]
                ))
            }
        }

        return candidates
    }

    // MARK: - Pass 2: Classification & Filtering

    /// Classifies text relationships, merges overlapping candidates, filters low-confidence.
    private func pass2_classifyAndFilter(
        candidates: [FigureCandidate],
        textBounds: [CGRect],
        subjectBounds: [CGRect]
    ) -> [FigureCandidate] {
        var result = candidates

        // Merge overlapping candidate bounds
        let mergedBounds = mergeOverlapping(result.map(\.bounds))
        result = mergedBounds.map { bounds in
            // Find the candidate with highest confidence for this merged region
            let matching = candidates.filter { !$0.bounds.intersection(bounds).isNull }
            let best = matching.max(by: { $0.confidence < $1.confidence }) ?? candidates[0]
            return FigureCandidate(
                bounds: bounds,
                source: best.source,
                confidence: best.confidence,
                evidence: best.evidence
            )
        }

        // Classify text relationships for each candidate
        for i in 0..<result.count {
            result[i].textRelations = textBounds.map { text in
                (text: text, relation: FigureDetector.classifyTextRelation(
                    figure: result[i].bounds, text: text
                ))
            }
        }

        return result
    }

    // MARK: - Pass 3: Hypothesis-and-Validate Boundary Detection

    /// For each candidate, builds a content map, generates multiple boundary hypotheses,
    /// scores them, and picks the best one. This replaces the fragile seed-and-grow approach
    /// with a method that works regardless of figure position, size, or background color.
    private func pass3_refineBoundaries(
        candidates: [FigureCandidate],
        image: CGImage,
        textBounds: [CGRect],
        subjectBounds: [CGRect]
    ) -> [FigureCandidate] {
        var result = candidates

        for i in 0..<result.count {
            // 3A: Build content map with 20% padding around candidate,
            // expanded to include overlapping subject bounds (subjects may extend
            // beyond the saliency-based candidate, e.g. bottom of a circular photo).
            let padding: CGFloat = 0.20
            var padded = CGRect(
                x: max(0, result[i].bounds.minX - result[i].bounds.width * padding),
                y: max(0, result[i].bounds.minY - result[i].bounds.height * padding),
                width: min(1.0, result[i].bounds.width * (1 + 2 * padding)),
                height: min(1.0, result[i].bounds.height * (1 + 2 * padding))
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

            // Expand padded region to include overlapping subjects
            for subject in subjectBounds {
                let inter = result[i].bounds.intersection(subject)
                guard !inter.isNull else { continue }
                let sArea = subject.width * subject.height
                guard sArea > 0, (inter.width * inter.height) / sArea > 0.10 else { continue }
                padded = padded.union(subject).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            }

            let contentMap = FigureDetector.buildContentMap(
                in: image, region: padded, textBounds: textBounds
            )

            // 3B: Generate hypotheses
            let hypotheses = FigureDetector.generateHypotheses(
                candidate: result[i],
                contentMap: contentMap,
                textBounds: textBounds,
                subjectBounds: subjectBounds
            )

            if debug {
                dbg("PASS3[\(i)] padded=(\(String(format:"%.3f %.3f %.3f %.3f",padded.minX,padded.minY,padded.width,padded.height)))")
                for gy in stride(from: 0, to: contentMap.gridHeight, by: 2) {
                    var row = ""
                    for gx in stride(from: 0, to: contentMap.gridWidth, by: 2) {
                        switch contentMap.cells[gy][gx] {
                        case .background: row += "."
                        case .content: row += "#"
                        case .text: row += "T"
                        }
                    }
                    dbg("  map[\(String(format:"%02d",gy))]: \(row)")
                }
                let regions = FigureDetector.findContentRegions(in: contentMap)
                dbg("  contentRegions: \(regions.count)")
                for h in hypotheses {
                    dbg("  hyp \(h.strategy): score=\(String(format:"%.4f",h.score)) bounds=(\(String(format:"%.3f %.3f %.3f %.3f",h.bounds.minX,h.bounds.minY,h.bounds.width,h.bounds.height)))")
                }
            }

            // 3C: Pick the best-scoring hypothesis
            if let best = hypotheses.max(by: { $0.score < $1.score }) {
                dbg("  WINNER: \(best.strategy) score=\(String(format:"%.4f",best.score))")
                result[i].bounds = best.bounds
            }

            // 3D: Validate — trim text if any crept in
            let preTrim = result[i].bounds
            result[i].bounds = trimTextFromRegion(result[i].bounds, textBounds: textBounds)
            if debug && result[i].bounds != preTrim {
                dbg("  TRIM: h \(String(format:"%.3f",preTrim.height)) → \(String(format:"%.3f",result[i].bounds.height))")
            }
        }

        // Promote uncovered subjects via content map (not fixed-margin expansion)
        for subject in subjectBounds {
            let covered = result.contains { candidate in
                let inter = candidate.bounds.intersection(subject)
                guard !inter.isNull else { return false }
                let sArea = subject.width * subject.height
                return sArea > 0 && (inter.width * inter.height) / sArea > 0.20
            }
            if !covered {
                // Build content map around the subject to find the actual figure
                let subjectPadded = CGRect(
                    x: max(0, subject.minX - subject.width * 0.5),
                    y: max(0, subject.minY - subject.height * 0.5),
                    width: min(1.0, subject.width * 2.0),
                    height: min(1.0, subject.height * 2.0)
                ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

                let subjectMap = FigureDetector.buildContentMap(
                    in: image, region: subjectPadded, textBounds: textBounds
                )

                if let contentBox = subjectMap.contentBoundingBox() {
                    let score = FigureDetector.scoreHypothesis(contentBox, contentMap: subjectMap)
                    if score > 0.2 {
                        result.append(FigureCandidate(
                            bounds: contentBox,
                            source: .promoted,
                            confidence: 0.4,
                            evidence: [.hasSubject]
                        ))
                    }
                }
            }
        }

        // Final merge
        let mergedBounds = mergeOverlapping(result.map(\.bounds))
        result = mergedBounds.map { bounds in
            let matching = result.filter { !$0.bounds.intersection(bounds).isNull }
            let best = matching.max(by: { $0.confidence < $1.confidence }) ?? result[0]
            return FigureCandidate(
                bounds: bounds,
                source: best.source,
                confidence: best.confidence,
                evidence: best.evidence
            )
        }

        // Re-trim text after merge: mergeOverlapping uses union which can
        // re-expand bounds to include text that was trimmed in step 3D.
        for i in 0..<result.count {
            result[i].bounds = trimTextFromRegion(result[i].bounds, textBounds: textBounds)
        }

        return result
    }

    // MARK: - Pass 4: Extraction & Post-Processing

    /// Extracts pixel data, auto-crops, validates, and produces final DetectedFigure objects.
    private func pass4_extractAndValidate(
        candidates: [FigureCandidate],
        image: CGImage,
        textBounds: [CGRect],
        subjectBounds: [CGRect]
    ) -> FigureDetectionResult {
        var figures: [DetectedFigure] = []

        for candidate in candidates {
            let bounds = candidate.bounds

            // Check if instance mask confirms photo content (skip variance tightening)
            let hasSubjectOverlap = subjectBounds.contains { subject in
                let inter = bounds.intersection(subject)
                guard !inter.isNull else { return false }
                let sArea = subject.width * subject.height
                return sArea > 0 && (inter.width * inter.height) / sArea > 0.20
            }

            let pixelRect = CGRect(
                x: bounds.origin.x * CGFloat(image.width),
                y: (1.0 - bounds.origin.y - bounds.height) * CGFloat(image.height),
                width: bounds.width * CGFloat(image.width),
                height: bounds.height * CGFloat(image.height)
            )

            let clampedRect = pixelRect.intersection(
                CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            guard !clampedRect.isEmpty, let cropped = image.cropping(to: clampedRect) else {
                dbg("PASS4 reject: empty/crop failed for bounds=(\(String(format:"%.3f %.3f %.3f %.3f",bounds.minX,bounds.minY,bounds.width,bounds.height)))")
                continue
            }

            // Validation: minimum visual complexity
            let variance = colorVariance(of: cropped)
            if variance < minimumColorVariance {
                dbg("PASS4 reject: low variance \(String(format:"%.1f",variance)) < \(minimumColorVariance) for \(cropped.width)×\(cropped.height)")
                continue
            }

            // Auto-crop whitespace
            let (whiteCropped, whiteCropRect) = autoCropWhitespace(cropped)

            // Variance-based tightening (skip when subject confirms photo)
            let finalCropped: CGImage
            let finalCropRect: CGRect
            if hasSubjectOverlap {
                finalCropped = whiteCropped
                finalCropRect = whiteCropRect
            } else {
                let (tightCropped, varianceCropRect) = tightenByVariance(whiteCropped)
                finalCropped = tightCropped
                finalCropRect = CGRect(
                    x: whiteCropRect.origin.x + varianceCropRect.origin.x,
                    y: whiteCropRect.origin.y + varianceCropRect.origin.y,
                    width: varianceCropRect.width,
                    height: varianceCropRect.height
                )
            }

            // Recalculate normalized bounds
            let tightBounds: CGRect
            if finalCropped.width != cropped.width || finalCropped.height != cropped.height {
                let tightPixelX = clampedRect.origin.x + finalCropRect.origin.x
                let tightPixelY = clampedRect.origin.y + finalCropRect.origin.y
                tightBounds = CGRect(
                    x: tightPixelX / CGFloat(image.width),
                    y: 1.0 - (tightPixelY + finalCropRect.height) / CGFloat(image.height),
                    width: finalCropRect.width / CGFloat(image.width),
                    height: finalCropRect.height / CGFloat(image.height)
                )
            } else {
                tightBounds = bounds
            }

            figures.append(DetectedFigure(
                bounds: tightBounds,
                label: DetectedFigure.label(for: figures.count),
                extractedImage: finalCropped,
                isSelected: true
            ))
        }

        return FigureDetectionResult(figures: figures)
    }

    // MARK: - Saliency Detection

    private func findSalientRegions(in image: CGImage) async throws -> [CGRect] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateAttentionBasedSaliencyImageRequest { [minimumSaliencyConfidence] request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNSaliencyImageObservation],
                      let observation = results.first else {
                    continuation.resume(returning: [])
                    return
                }

                let regions = observation.salientObjects?
                    .filter { $0.confidence >= minimumSaliencyConfidence }
                    .map { $0.boundingBox } ?? []
                continuation.resume(returning: regions)
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Text Exclusion

    /// Filters out salient regions that are predominantly covered by text.
    func excludeTextRegions(_ regions: [CGRect], textBounds: [CGRect]) -> [CGRect] {
        guard !textBounds.isEmpty else { return regions }

        return regions.filter { region in
            let textOverlap = textOverlapFraction(region: region, textBounds: textBounds)
            return textOverlap < textOverlapExclusionThreshold
        }
    }

    /// Calculates what fraction of a region is covered by text bounding boxes.
    func textOverlapFraction(region: CGRect, textBounds: [CGRect]) -> CGFloat {
        guard region.width > 0, region.height > 0 else { return 0 }

        let regionArea = region.width * region.height
        var coveredArea: CGFloat = 0

        for textRect in textBounds {
            let intersection = region.intersection(textRect)
            if !intersection.isNull {
                coveredArea += intersection.width * intersection.height
            }
        }

        // Cap at 1.0 (overlapping text bounds could cause double-counting)
        return min(coveredArea / regionArea, 1.0)
    }

    // MARK: - Text Trimming

    /// Iteratively trims a saliency region to exclude text that was already detected by OCR.
    /// Each iteration finds text blocks still inside the region, picks the best edge cut
    /// to remove them, and repeats until text overlap is minimal or no further improvement
    /// is possible. This converges the bounds toward the actual figure content.
    func trimTextFromRegion(_ region: CGRect, textBounds: [CGRect]) -> CGRect {
        // Two-pass trimming: vertical first (top/bottom), then horizontal (left/right).
        // This ensures text BELOW a full-width hero is removed before any horizontal
        // cuts are evaluated. Without this, a left-side text column below the hero
        // would trigger a left cut that halves the hero image.
        var current = region

        // Pass 1: vertical cuts only (top/bottom)
        current = trimPass(current, textBounds: textBounds, directions: .vertical)

        // Pass 2: horizontal cuts only (left/right)
        current = trimPass(current, textBounds: textBounds, directions: .horizontal)

        return current
    }

    private enum TrimDirections {
        case vertical   // top and bottom cuts only
        case horizontal // left and right cuts only
    }

    private func trimPass(_ region: CGRect, textBounds: [CGRect], directions: TrimDirections) -> CGRect {
        var current = region
        let maxIterations = 4

        for _ in 0..<maxIterations {
            let overlap = textOverlapFraction(region: current, textBounds: textBounds)
            guard overlap > 0.05 else { break }

            let contained = textBounds.filter { text in
                let intersection = current.intersection(text)
                return !intersection.isNull && intersection.width * intersection.height > 0.0001
            }
            guard !contained.isEmpty else { break }

            let best = bestCutCandidate(region: current, textBlocks: contained,
                                        allText: textBounds, directions: directions)
            guard let candidate = best else { break }

            let newOverlap = textOverlapFraction(region: candidate, textBounds: textBounds)
            guard newOverlap < overlap else { break }

            current = candidate
        }

        return current
    }

    /// Finds the best single edge-cut that removes the most text from a region
    /// while preserving the most figure area. Returns nil if no viable cut exists.
    ///
    /// Only text blocks touching or very near an edge (within 30% of the dimension)
    /// can trigger a cut from that edge. A cut must retain at least 40% of the
    /// original dimension to prevent slicing through the figure.
    private func bestCutCandidate(region: CGRect, textBlocks: [CGRect], allText: [CGRect],
                                   directions: TrimDirections = .vertical) -> CGRect? {
        var candidates: [CGRect] = []

        // Maximum fraction of a dimension a single cut may remove
        let maxCutFraction: CGFloat = 0.6
        // Edge proximity threshold: text within this fraction of the edge can trigger a cut.
        // 35% (increased from 20%) allows trimming text that's further from the edge,
        // which is needed when saliency returns oversized regions (e.g. figure-in-middle
        // where text is ~25-30% from each edge).
        let edgeProximity: CGFloat = 0.35

        for text in textBlocks {
            let clipped = text.intersection(region)
            guard !clipped.isNull else { continue }

            if directions == .vertical {
                // Cut from bottom — text must touch or be near the bottom edge
                if clipped.minY - region.minY < region.height * edgeProximity {
                    let c = CGRect(x: region.minX, y: clipped.maxY,
                                   width: region.width,
                                   height: max(0, region.maxY - clipped.maxY))
                    if c.height > 0, c.height >= region.height * (1 - maxCutFraction) {
                        candidates.append(c)
                    }
                }
                // Cut from top — text must touch or be near the top edge
                if region.maxY - clipped.maxY < region.height * edgeProximity {
                    let c = CGRect(x: region.minX, y: region.minY,
                                   width: region.width,
                                   height: max(0, clipped.minY - region.minY))
                    if c.height > 0, c.height >= region.height * (1 - maxCutFraction) {
                        candidates.append(c)
                    }
                }
            }

            if directions == .horizontal {
                // Cut from left — text must touch or be near the left edge
                if clipped.minX - region.minX < region.width * edgeProximity {
                    let c = CGRect(x: clipped.maxX, y: region.minY,
                                   width: max(0, region.maxX - clipped.maxX),
                                   height: region.height)
                    if c.width > 0, c.width >= region.width * (1 - maxCutFraction) {
                        candidates.append(c)
                    }
                }
                // Cut from right — text must touch or be near the right edge
                if region.maxX - clipped.maxX < region.width * edgeProximity {
                    let c = CGRect(x: region.minX, y: region.minY,
                                   width: max(0, clipped.minX - region.minX),
                                   height: region.height)
                    if c.width > 0, c.width >= region.width * (1 - maxCutFraction) {
                        candidates.append(c)
                    }
                }
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Score by overlap reduction relative to area cost.
        // A candidate that halves overlap while keeping 80% area beats one that
        // eliminates overlap but keeps only 20% area.
        // Score = overlapReduction / areaCost, where both are fractions of original.
        var bestRect: CGRect?
        var bestScore: CGFloat = -1

        let regionOverlap = textOverlapFraction(region: region, textBounds: allText)
        let regionArea = region.width * region.height

        for candidate in candidates {
            let area = candidate.width * candidate.height
            guard area >= minimumAreaFraction else { continue }
            let overlap = textOverlapFraction(region: candidate, textBounds: allText)
            guard overlap < regionOverlap else { continue }

            let overlapReduction = regionOverlap - overlap
            let areaRetained = area / regionArea
            // Score: how much overlap is reduced per unit of area lost
            // Add areaRetained to favor keeping more area when overlap reduction is similar
            let score = overlapReduction * areaRetained + areaRetained * 0.1
            if score > bestScore {
                bestScore = score
                bestRect = candidate
            }
        }

        return bestRect
    }

    // MARK: - Variance-Based Tightening

    // MARK: - Snap-to-Edge

    /// If a region nearly spans the full width or height (>threshold), extend it to the
    /// full 0..1 range on that axis, provided no text blocks sit in the extended area.
    /// This compensates for saliency underestimation of uniform regions in full-width
    /// banners and heroes where one side has low visual activity.
    func snapToEdges(_ rect: CGRect, textBounds: [CGRect], threshold: CGFloat) -> CGRect {
        var result = rect

        // Use spatial classifier to determine which edges have adjacent text.
        // Any text block classified as adjacent to an edge blocks snapping in that direction.
        // This replaces the area-based significantTextInGap check which missed small text
        // (a few lines of body text don't cover 5% of a large gap area).
        let blocked = FigureDetector.blockedExpansionEdges(figure: rect, textBounds: textBounds)

        // Snap width to full if >threshold and no adjacent text blocking
        if rect.width >= threshold {
            let leftGap = rect.minX
            let rightGap = 1.0 - rect.maxX

            if leftGap > 0 && leftGap < 0.40 && !blocked.contains(.left) {
                result = CGRect(x: 0, y: result.minY, width: result.maxX, height: result.height)
            }
            if rightGap > 0 && rightGap < 0.40 && !blocked.contains(.right) {
                result = CGRect(x: result.minX, y: result.minY,
                                width: 1.0 - result.minX, height: result.height)
            }
        }

        // Snap height to full if >threshold and no adjacent text blocking.
        // For full-width figures (width snapped to ~1.0), use a lower height threshold
        // because banners/heroes often have light edges that saliency underestimates.
        let heightThreshold = result.width > 0.95 ? threshold * 0.5 : threshold
        if rect.height >= heightThreshold {
            let bottomGap = rect.minY
            let topGap = 1.0 - rect.maxY

            if bottomGap > 0 && bottomGap < 0.40 && !blocked.contains(.bottom) {
                result = CGRect(x: result.minX, y: 0, width: result.width, height: result.maxY)
            }
            if topGap > 0 && topGap < 0.40 && !blocked.contains(.top) {
                result = CGRect(x: result.minX, y: result.minY,
                                width: result.width, height: 1.0 - result.minY)
            }
        }

        return result
    }

    /// Checks if text blocks cover a significant fraction of a gap area.
    /// Small fragments (nav items, stray labels) are ignored.
    private func significantTextInGap(_ gapRect: CGRect, textBounds: [CGRect],
                                       minCoverage: CGFloat) -> Bool {
        let gapArea = gapRect.width * gapRect.height
        guard gapArea > 0 else { return false }
        var coveredArea: CGFloat = 0
        for text in textBounds {
            let intersection = text.intersection(gapRect)
            if !intersection.isNull {
                coveredArea += intersection.width * intersection.height
            }
        }
        return coveredArea / gapArea >= minCoverage
    }

    // MARK: - Directional Expansion

    /// Expands a figure region by `margin` on each edge, but only if no text block
    /// is adjacent to that edge. This prevents expanding back into text areas that
    /// were just trimmed, while still capturing figure content that saliency missed.
    func directionalExpand(_ rect: CGRect, textBounds: [CGRect], margin: CGFloat) -> CGRect {
        // Use spatial relationship classifier to determine blocked edges
        let blocked = FigureDetector.blockedExpansionEdges(figure: rect, textBounds: textBounds)

        let bottomM = blocked.contains(.bottom) ? 0.0 : margin
        let topM = blocked.contains(.top) ? 0.0 : margin
        let leftM = blocked.contains(.left) ? 0.0 : margin
        let rightM = blocked.contains(.right) ? 0.0 : margin

        let newX = max(0, rect.minX - leftM)
        let newY = max(0, rect.minY - bottomM)
        return CGRect(
            x: newX,
            y: newY,
            width: min(1.0 - newX, rect.width + leftM + rightM),
            height: min(1.0 - newY, rect.height + bottomM + topM)
        )
    }

    // MARK: - Subject-Aware Expansion

    /// Expands a saliency-detected figure region to include any overlapping foreground
    /// subjects detected by instance mask. This ensures subjects at the edges of the
    /// saliency region (e.g. hands, heads) are not cut off. The expansion is limited
    /// to directions without adjacent text to avoid bleeding into text areas.
    func expandToIncludeSubjects(_ rect: CGRect, subjectBounds: [CGRect], textBounds: [CGRect]) -> CGRect {
        guard !subjectBounds.isEmpty else { return rect }

        // Find subjects that overlap with this figure region
        let overlapping = subjectBounds.filter { subject in
            let intersection = rect.intersection(subject)
            // Subject overlaps if at least 20% of the subject is inside the figure region
            guard !intersection.isNull else { return false }
            let subjectArea = subject.width * subject.height
            guard subjectArea > 0 else { return false }
            return (intersection.width * intersection.height) / subjectArea > 0.20
        }

        guard !overlapping.isEmpty else { return rect }

        // Take the union of the saliency rect with all overlapping subject rects
        var expanded = rect
        for subject in overlapping {
            expanded = expanded.union(subject)
        }

        // Clamp to 0..1
        expanded = CGRect(
            x: max(0, expanded.minX),
            y: max(0, expanded.minY),
            width: min(1.0 - max(0, expanded.minX), expanded.width),
            height: min(1.0 - max(0, expanded.minY), expanded.height)
        )

        // Use spatial relationship classifier to determine which edges are constrained.
        // This correctly distinguishes "text beside figure" (blocks horizontal, not vertical)
        // from "text below figure" (blocks vertical, not horizontal).
        let blocked = FigureDetector.blockedExpansionEdges(
            figure: expanded, textBounds: textBounds
        )

        // Roll back expansion on blocked edges, but allow limited expansion
        // (up to 30% of the saliency dimension) toward the subject.
        let maxExpandFraction: CGFloat = 0.30
        var result = expanded
        if blocked.contains(.bottom) {
            let maxExpand = rect.height * maxExpandFraction
            let safeY = max(expanded.minY, rect.minY - maxExpand)
            result = CGRect(x: result.minX, y: safeY, width: result.width, height: result.maxY - safeY)
        }
        if blocked.contains(.top) {
            let maxExpand = rect.height * maxExpandFraction
            let safeMaxY = min(expanded.maxY, rect.maxY + maxExpand)
            result = CGRect(x: result.minX, y: result.minY, width: result.width, height: safeMaxY - result.minY)
        }
        if blocked.contains(.left) {
            let maxExpand = rect.width * maxExpandFraction
            let safeX = max(expanded.minX, rect.minX - maxExpand)
            result = CGRect(x: safeX, y: result.minY, width: result.maxX - safeX, height: result.height)
        }
        if blocked.contains(.right) {
            let maxExpand = rect.width * maxExpandFraction
            let safeMaxX = min(expanded.maxX, rect.maxX + maxExpand)
            result = CGRect(x: result.minX, y: result.minY, width: safeMaxX - result.minX, height: result.height)
        }

        return result
    }

    // MARK: - Subject Promotion Expansion

    /// Expands a subject bounding box by a percentage margin on each side to capture
    /// the full visual context around a detected foreground subject (e.g. sky, landscape
    /// around a person in a circular photo). Avoids expanding into text regions.
    private func expandSubjectForPromotion(
        _ subject: CGRect, margin: CGFloat, textBounds: [CGRect]
    ) -> CGRect {
        let expandW = subject.width * margin
        let expandH = subject.height * margin

        let newX = max(0, subject.minX - expandW)
        let newY = max(0, subject.minY - expandH)
        let newMaxX = min(1.0, subject.maxX + expandW)
        let newMaxY = min(1.0, subject.maxY + expandH)

        var expanded = CGRect(x: newX, y: newY, width: newMaxX - newX, height: newMaxY - newY)

        // Use spatial relationship classifier to pull back edges toward adjacent text
        let blocked = FigureDetector.blockedExpansionEdges(figure: expanded, textBounds: textBounds)

        if blocked.contains(.right) {
            // Find the nearest text block to the right and pull back to its left edge
            let rightText = textBounds
                .filter { FigureDetector.classifyTextRelation(figure: expanded, text: $0) == .adjacentRight }
                .min(by: { $0.minX < $1.minX })
            if let nearest = rightText {
                expanded = CGRect(x: expanded.minX, y: expanded.minY,
                                  width: nearest.minX - expanded.minX, height: expanded.height)
            }
        }
        if blocked.contains(.left) {
            let leftText = textBounds
                .filter { FigureDetector.classifyTextRelation(figure: expanded, text: $0) == .adjacentLeft }
                .max(by: { $0.maxX < $1.maxX })
            if let nearest = leftText {
                expanded = CGRect(x: nearest.maxX, y: expanded.minY,
                                  width: expanded.maxX - nearest.maxX, height: expanded.height)
            }
        }
        if blocked.contains(.top) {
            let topText = textBounds
                .filter { FigureDetector.classifyTextRelation(figure: expanded, text: $0) == .adjacentAbove }
                .min(by: { $0.minY < $1.minY })
            if let nearest = topText {
                expanded = CGRect(x: expanded.minX, y: expanded.minY,
                                  width: expanded.width, height: nearest.minY - expanded.minY)
            }
        }
        if blocked.contains(.bottom) {
            let bottomText = textBounds
                .filter { FigureDetector.classifyTextRelation(figure: expanded, text: $0) == .adjacentBelow }
                .max(by: { $0.maxY < $1.maxY })
            if let nearest = bottomText {
                expanded = CGRect(x: expanded.minX, y: nearest.maxY,
                                  width: expanded.width, height: expanded.maxY - nearest.maxY)
            }
        }

        return expanded
    }

    // MARK: - Variance-Based Tightening

    /// Scans columns and rows of the figure image for color variance. Edges with low
    /// variance (text-on-white or plain background) are cropped away, keeping only
    /// the sub-region with consistently high visual content (the actual photo/figure).
    func tightenByVariance(_ image: CGImage) -> (image: CGImage, cropRect: CGRect) {
        let width = image.width
        let height = image.height
        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        guard width > 20, height > 20 else { return (image, fullRect) }

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (image, fullRect) }

        context.draw(image, in: fullRect)
        guard let data = context.data else { return (image, fullRect) }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Compute variance for each column strip and row strip
        let colVariances = (0..<width).map { x in
            stripVariance(ptr: ptr, width: width, height: height, isColumn: true, index: x)
        }
        let rowVariances = (0..<height).map { y in
            stripVariance(ptr: ptr, width: width, height: height, isColumn: false, index: y)
        }

        // Find the threshold: use the median variance as a baseline.
        // Columns/rows with variance > 1.5x median are "high content" (figure).
        let sortedCol = colVariances.sorted()
        let sortedRow = rowVariances.sorted()
        let colMedian = sortedCol[sortedCol.count / 2]
        let rowMedian = sortedRow[sortedRow.count / 2]

        // Minimum variance to be considered "figure content"
        let colThreshold = max(colMedian * 1.5, 15.0)
        let rowThreshold = max(rowMedian * 1.5, 15.0)

        // Scan from each edge inward to find high-variance content
        var left = 0
        while left < width && colVariances[left] < colThreshold { left += 1 }
        var right = width - 1
        while right > left && colVariances[right] < colThreshold { right -= 1 }
        var top = 0
        while top < height && rowVariances[top] < rowThreshold { top += 1 }
        var bottom = height - 1
        while bottom > top && rowVariances[bottom] < rowThreshold { bottom -= 1 }

        // Ensure valid bounds
        guard left < right, top < bottom else { return (image, fullRect) }

        // Add margin (5% of the dimension) to avoid clipping photo edges
        let hMargin = max(4, (right - left) / 20)
        let vMargin = max(4, (bottom - top) / 20)
        let cropRect = CGRect(
            x: max(0, left - hMargin),
            y: max(0, top - vMargin),
            width: min(width - max(0, left - hMargin), right - left + 2 * hMargin),
            height: min(height - max(0, top - vMargin), bottom - top + 2 * vMargin)
        ).intersection(fullRect)

        // Only tighten if it removes at least 15% from width or height
        let minTightenFraction: CGFloat = 0.15
        let tightenedEnough = cropRect.width < CGFloat(width) * (1.0 - minTightenFraction)
            || cropRect.height < CGFloat(height) * (1.0 - minTightenFraction)

        // Protect the short dimension for banner/hero images (aspect ratio > 2:1):
        // do not tighten if it would lose more than 20% of the short side.
        // This prevents gradient edges of panoramic photos from being cropped.
        let vtAspectRatio = CGFloat(max(width, height)) / CGFloat(min(width, height))
        let shortSideProtected: Bool
        if vtAspectRatio > 2.0 {
            let shortSide = CGFloat(min(width, height))
            let croppedShort = min(cropRect.width, cropRect.height)
            shortSideProtected = (1.0 - croppedShort / shortSide) > 0.20
        } else {
            shortSideProtected = false
        }

        guard tightenedEnough, !shortSideProtected, !cropRect.isEmpty,
              cropRect.width > 10, cropRect.height > 10,
              let cropped = image.cropping(to: cropRect) else {
            return (image, fullRect)
        }

        return (cropped, cropRect)
    }

    /// Computes color variance along a single column or row strip.
    private func stripVariance(ptr: UnsafePointer<UInt8>, width: Int, height: Int,
                               isColumn: Bool, index: Int) -> Double {
        var sum: Double = 0
        var sumSq: Double = 0
        let count: Int
        let step: Int

        if isColumn {
            count = height
            step = max(1, height / 30)
        } else {
            count = width
            step = max(1, width / 30)
        }

        var samples = 0
        var i = 0
        while i < count {
            let offset: Int
            if isColumn {
                offset = (i * width + index) * 4
            } else {
                offset = (index * width + i) * 4
            }
            let brightness = (Double(ptr[offset]) + Double(ptr[offset + 1]) + Double(ptr[offset + 2])) / 3.0
            sum += brightness
            sumSq += brightness * brightness
            samples += 1
            i += step
        }

        guard samples > 1 else { return 0 }
        let mean = sum / Double(samples)
        let variance = sumSq / Double(samples) - mean * mean
        return max(0, variance).squareRoot()
    }

    // MARK: - Auto-Crop Whitespace

    /// Crops whitespace/background from the edges of a figure image by scanning rows and
    /// columns for brightness differences from the border color. This tightens the figure
    /// bounds to the actual visual content.
    /// Returns the cropped image and the crop rect in pixel coordinates relative to the input.
    func autoCropWhitespace(_ image: CGImage) -> (image: CGImage, cropRect: CGRect) {
        let width = image.width
        let height = image.height
        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        guard width > 4, height > 4 else { return (image, fullRect) }

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (image, fullRect) }

        context.draw(image, in: fullRect)
        guard let data = context.data else { return (image, fullRect) }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Threshold: a row/column is "content" if its average brightness differs
        // from the background by more than this amount. A lower threshold means more
        // aggressive trimming of light-colored edges (gradients fading to white).
        let threshold: Double = 20.0

        // Use the brightest edge as background reference. Backgrounds are typically
        // white or light-colored, so the brightest edge is most likely the background.
        let edgeBrightnesses = [
            rowBrightness(ptr: ptr, y: 0, width: width),
            rowBrightness(ptr: ptr, y: height - 1, width: width),
            colBrightness(ptr: ptr, x: 0, width: width, height: height),
            colBrightness(ptr: ptr, x: width - 1, width: width, height: height),
        ]
        let bgBrightness = edgeBrightnesses.max() ?? 255.0

        // Only auto-crop if the background is light (>200 brightness = near white/gray)
        guard bgBrightness > 200 else { return (image, fullRect) }

        // Scan from each edge inward to find the content boundary
        let top = scanFromTop(ptr: ptr, width: width, height: height,
                              bgBrightness: bgBrightness, threshold: threshold)
        let bottom = scanFromBottom(ptr: ptr, width: width, height: height,
                                    bgBrightness: bgBrightness, threshold: threshold)
        let left = scanFromLeft(ptr: ptr, width: width, height: height,
                                bgBrightness: bgBrightness, threshold: threshold)
        let right = scanFromRight(ptr: ptr, width: width, height: height,
                                  bgBrightness: bgBrightness, threshold: threshold)

        // Ensure valid bounds (edges didn't cross)
        guard left < right, top < bottom else { return (image, fullRect) }

        // Add margin to avoid clipping content at figure edges.
        // Use zero margin on edges with a clear whitespace gap (content boundary is sharp),
        // and a small margin where content reaches close to the image edge.
        let edgeMargin = max(2, min(width, height) / 50)
        let topGap = top
        let bottomGap = height - 1 - bottom
        let leftGap = left
        let rightGap = width - 1 - right
        let vThreshold = 4
        let hThreshold = 4
        let topMargin = topGap >= vThreshold ? 0 : edgeMargin
        let bottomMargin = bottomGap >= vThreshold ? 0 : edgeMargin
        let leftMargin = leftGap >= hThreshold ? 0 : edgeMargin
        let rightMargin = rightGap >= hThreshold ? 0 : edgeMargin
        let cropX = max(0, left - leftMargin)
        let cropY = max(0, top - topMargin)
        let cropRight = min(width - 1, right + rightMargin)
        let cropBottom = min(height - 1, bottom + bottomMargin)
        let cropRect = CGRect(
            x: cropX, y: cropY,
            width: cropRight - cropX + 1,
            height: cropBottom - cropY + 1
        )

        // Only crop if it removes some whitespace (at least 4 pixels from any edge)
        let croppedEnough = cropRect.width < CGFloat(width) - 4
            || cropRect.height < CGFloat(height) - 4

        // Protect short dimension for banner/panoramic images (aspect ratio > 2:1).
        // Only protect edges that contain gradient/photo content (brightness < 250).
        // Pure white edges (brightness >= 250) are safe to crop — they are padding, not content.
        let acAspectRatio = CGFloat(max(width, height)) / CGFloat(min(width, height))
        var safeCropRect = cropRect
        if acAspectRatio > 2.0 {
            let acShortSide = CGFloat(min(width, height))
            let acCroppedShort = min(safeCropRect.width, safeCropRect.height)
            let shortSideLoss = 1.0 - acCroppedShort / acShortSide
            if shortSideLoss > 0.10 {
                // Significant crop — check which edges are pure white vs photo content.
                // Only restore (undo crop on) edges that have non-white content.
                let pureWhiteThreshold = 240.0

                let topEdgeBrightness = rowBrightness(ptr: ptr, y: 0, width: width)
                let bottomEdgeBrightness = rowBrightness(ptr: ptr, y: height - 1, width: width)

                // If the top is NOT pure white (photo content), restore top crop
                if topEdgeBrightness < pureWhiteThreshold && top > 0 {
                    safeCropRect.size.height += safeCropRect.origin.y
                    safeCropRect.origin.y = 0
                }
                // If the bottom is NOT pure white (photo content), restore bottom crop
                if bottomEdgeBrightness < pureWhiteThreshold && bottom < height {
                    safeCropRect.size.height = CGFloat(height) - safeCropRect.origin.y
                }
            }
        }

        guard croppedEnough, !safeCropRect.isEmpty,
              safeCropRect.width > 4, safeCropRect.height > 4,
              let cropped = image.cropping(to: safeCropRect) else {
            return (image, fullRect)
        }

        return (cropped, safeCropRect)
    }

    private func rowBrightness(ptr: UnsafePointer<UInt8>, y: Int, width: Int) -> Double {
        var sum: Double = 0
        let step = max(1, width / 20) // sample ~20 pixels per row for speed
        var count = 0
        var x = 0
        while x < width {
            let offset = (y * width + x) * 4
            sum += (Double(ptr[offset]) + Double(ptr[offset + 1]) + Double(ptr[offset + 2])) / 3.0
            count += 1
            x += step
        }
        return count > 0 ? sum / Double(count) : 0
    }

    private func colBrightness(ptr: UnsafePointer<UInt8>, x: Int, width: Int, height: Int) -> Double {
        var sum: Double = 0
        let step = max(1, height / 20)
        var count = 0
        var y = 0
        while y < height {
            let offset = (y * width + x) * 4
            sum += (Double(ptr[offset]) + Double(ptr[offset + 1]) + Double(ptr[offset + 2])) / 3.0
            count += 1
            y += step
        }
        return count > 0 ? sum / Double(count) : 0
    }

    /// Checks if a row has enough non-background content (>5% of sampled pixels differ
    /// from background by more than threshold). This detects content for thin arcs of
    /// circular photos while ignoring scattered artifacts in otherwise white rows.
    private func rowHasContent(ptr: UnsafePointer<UInt8>, y: Int, width: Int,
                               bgBrightness: Double, threshold: Double) -> Bool {
        let sampleCount = 40
        let step = max(1, width / sampleCount)
        var contentPixels = 0
        var totalPixels = 0
        var x = 0
        while x < width {
            let offset = (y * width + x) * 4
            let brightness = (Double(ptr[offset]) + Double(ptr[offset + 1]) + Double(ptr[offset + 2])) / 3.0
            if abs(brightness - bgBrightness) > threshold {
                contentPixels += 1
            }
            totalPixels += 1
            x += step
        }
        // At least 5% of pixels must be non-background to count as content
        return totalPixels > 0 && Double(contentPixels) / Double(totalPixels) >= 0.05
    }

    /// Checks if a column has enough non-background content (>5% of sampled pixels).
    private func colHasContent(ptr: UnsafePointer<UInt8>, x: Int, width: Int, height: Int,
                               bgBrightness: Double, threshold: Double) -> Bool {
        let sampleCount = 40
        let step = max(1, height / sampleCount)
        var contentPixels = 0
        var totalPixels = 0
        var y = 0
        while y < height {
            let offset = (y * width + x) * 4
            let brightness = (Double(ptr[offset]) + Double(ptr[offset + 1]) + Double(ptr[offset + 2])) / 3.0
            if abs(brightness - bgBrightness) > threshold {
                contentPixels += 1
            }
            totalPixels += 1
            y += step
        }
        return totalPixels > 0 && Double(contentPixels) / Double(totalPixels) >= 0.05
    }

    private func scanFromTop(ptr: UnsafePointer<UInt8>, width: Int, height: Int,
                             bgBrightness: Double, threshold: Double) -> Int {
        for y in 0..<height {
            if rowHasContent(ptr: ptr, y: y, width: width, bgBrightness: bgBrightness, threshold: threshold) {
                return y
            }
        }
        return 0
    }

    private func scanFromBottom(ptr: UnsafePointer<UInt8>, width: Int, height: Int,
                                bgBrightness: Double, threshold: Double) -> Int {
        for y in stride(from: height - 1, through: 0, by: -1) {
            if rowHasContent(ptr: ptr, y: y, width: width, bgBrightness: bgBrightness, threshold: threshold) {
                return y
            }
        }
        return height - 1
    }

    private func scanFromLeft(ptr: UnsafePointer<UInt8>, width: Int, height: Int,
                              bgBrightness: Double, threshold: Double) -> Int {
        for x in 0..<width {
            if colHasContent(ptr: ptr, x: x, width: width, height: height, bgBrightness: bgBrightness, threshold: threshold) {
                return x
            }
        }
        return 0
    }

    private func scanFromRight(ptr: UnsafePointer<UInt8>, width: Int, height: Int,
                               bgBrightness: Double, threshold: Double) -> Int {
        for x in stride(from: width - 1, through: 0, by: -1) {
            if colHasContent(ptr: ptr, x: x, width: width, height: height, bgBrightness: bgBrightness, threshold: threshold) {
                return x
            }
        }
        return width - 1
    }

    // MARK: - Color Variance

    /// Computes the color variance (standard deviation of pixel brightness) of a CGImage.
    /// Low variance means uniform color (background), high variance means visual content.
    func colorVariance(of image: CGImage) -> CGFloat {
        let width = min(image.width, 100) // sample at reduced resolution for speed
        let height = min(image.height, 100)

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return 0 }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let pixelCount = width * height
        var rSum: Double = 0, gSum: Double = 0, bSum: Double = 0
        var rSumSq: Double = 0, gSumSq: Double = 0, bSumSq: Double = 0

        for i in 0..<pixelCount {
            let offset = i * 4
            let r = Double(ptr[offset])
            let g = Double(ptr[offset + 1])
            let b = Double(ptr[offset + 2])
            rSum += r; gSum += g; bSum += b
            rSumSq += r * r; gSumSq += g * g; bSumSq += b * b
        }

        let n = Double(pixelCount)
        let rVar = rSumSq / n - (rSum / n) * (rSum / n)
        let gVar = gSumSq / n - (gSum / n) * (gSum / n)
        let bVar = bSumSq / n - (bSum / n) * (bSum / n)
        // Use total color variance: captures gradients where individual channels
        // vary significantly even if overall brightness stays similar.
        return CGFloat((rVar + gVar + bVar).squareRoot())
    }

    // MARK: - Content Map Construction

    /// Builds a ContentMap for a region of the image by classifying each cell in a
    /// coarse grid as background, text, or content.
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - region: Normalized region (Vision coords) to analyze. Use (0,0,1,1) for full image.
    ///   - textBounds: OCR text bounding boxes.
    ///   - gridSize: Grid resolution (default 50x50 = 2500 samples).
    ///   - bgThreshold: Max RGB distance from background to count as background (default 20).
    /// - Returns: A ContentMap with cell classifications.
    static func buildContentMap(
        in image: CGImage,
        region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        textBounds: [CGRect],
        gridSize: Int = 50,
        bgThreshold: Double = 20.0
    ) -> ContentMap {
        let imgW = image.width
        let imgH = image.height

        guard let ctx = CGContext(
            data: nil, width: imgW, height: imgH,
            bitsPerComponent: 8, bytesPerRow: imgW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return ContentMap(gridWidth: gridSize, gridHeight: gridSize,
                              cells: Array(repeating: Array(repeating: .background, count: gridSize), count: gridSize),
                              region: region)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
        guard let data = ctx.data else {
            return ContentMap(gridWidth: gridSize, gridHeight: gridSize,
                              cells: Array(repeating: Array(repeating: .background, count: gridSize), count: gridSize),
                              region: region)
        }
        let ptr = data.bindMemory(to: UInt8.self, capacity: imgW * imgH * 4)

        let bgColor = sampleBackgroundColor(ptr: ptr, width: imgW, height: imgH)

        if ProcessInfo.processInfo.environment["FIGURE_DEBUG"] == "1" {
            print("[FigureDetector]   bgColor=(\(String(format:"%.0f %.0f %.0f",bgColor.r,bgColor.g,bgColor.b))) region=(\(String(format:"%.3f %.3f %.3f %.3f",region.minX,region.minY,region.width,region.height)))")
        }

        var cells = Array(repeating: Array(repeating: CellType.background, count: gridSize), count: gridSize)

        for gy in 0..<gridSize {
            for gx in 0..<gridSize {
                // Cell center in Vision coords
                let nx = region.minX + (CGFloat(gx) + 0.5) * region.width / CGFloat(gridSize)
                let ny = region.minY + region.height - (CGFloat(gy) + 0.5) * region.height / CGFloat(gridSize)

                // Check if cell is in a text bounding box
                let inText = textBounds.contains { $0.contains(CGPoint(x: nx, y: ny)) }
                if inText {
                    cells[gy][gx] = .text
                    continue
                }

                // Sample pixel at this cell's position
                let px = min(imgW - 1, max(0, Int(nx * CGFloat(imgW))))
                let py = min(imgH - 1, max(0, Int((1.0 - ny) * CGFloat(imgH))))
                let off = (py * imgW + px) * 4
                let r = Double(ptr[off])
                let g = Double(ptr[off + 1])
                let b = Double(ptr[off + 2])

                // Check if pixel matches background
                let dist = abs(r - bgColor.r) + abs(g - bgColor.g) + abs(b - bgColor.b)
                if dist <= bgThreshold * 3.0 {
                    cells[gy][gx] = .background
                } else {
                    cells[gy][gx] = .content
                }
            }
        }

        return ContentMap(gridWidth: gridSize, gridHeight: gridSize, cells: cells, region: region)
    }

    /// Finds connected regions of content cells in a ContentMap.
    /// Returns bounding boxes in Vision coordinates for each connected component.
    static func findContentRegions(in contentMap: ContentMap) -> [CGRect] {
        let gw = contentMap.gridWidth
        let gh = contentMap.gridHeight
        var visited = Array(repeating: Array(repeating: false, count: gw), count: gh)
        var regions: [CGRect] = []

        let cellW = contentMap.region.width / CGFloat(gw)
        let cellH = contentMap.region.height / CGFloat(gh)

        for startY in 0..<gh {
            for startX in 0..<gw {
                guard contentMap.cells[startY][startX] == .content, !visited[startY][startX] else { continue }

                // BFS to find connected content cells
                var queue = [(startX, startY)]
                visited[startY][startX] = true
                var minGX = startX, maxGX = startX, minGY = startY, maxGY = startY

                while !queue.isEmpty {
                    let (cx, cy) = queue.removeFirst()
                    minGX = min(minGX, cx); maxGX = max(maxGX, cx)
                    minGY = min(minGY, cy); maxGY = max(maxGY, cy)

                    for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, nx < gw, ny >= 0, ny < gh,
                              !visited[ny][nx],
                              contentMap.cells[ny][nx] == .content else { continue }
                        visited[ny][nx] = true
                        queue.append((nx, ny))
                    }
                }

                // Convert grid bounds to Vision coordinates
                let visionMinY = contentMap.region.maxY - CGFloat(maxGY + 1) * cellH
                let visionMaxY = contentMap.region.maxY - CGFloat(minGY) * cellH
                let regionRect = CGRect(
                    x: contentMap.region.minX + CGFloat(minGX) * cellW,
                    y: visionMinY,
                    width: CGFloat(maxGX - minGX + 1) * cellW,
                    height: visionMaxY - visionMinY
                )
                regions.append(regionRect)
            }
        }

        return regions
    }

    // MARK: - Hypothesis Generation & Scoring

    /// Generates boundary hypotheses for a candidate using multiple strategies.
    static func generateHypotheses(
        candidate: FigureCandidate,
        contentMap: ContentMap,
        textBounds: [CGRect],
        subjectBounds: [CGRect]
    ) -> [BoundaryHypothesis] {
        var hypotheses: [BoundaryHypothesis] = []

        // 1. Content-fit: use connected component analysis to find the content region
        //    that overlaps the candidate, rather than the global bounding box of all
        //    content cells (which can span disconnected regions like title bar + figure).
        let contentRegions = findContentRegions(in: contentMap)
        let overlappingRegions = contentRegions.filter { region in
            !region.intersection(candidate.bounds).isNull
        }
        if let bestRegion = overlappingRegions.max(by: {
            $0.intersection(candidate.bounds).width * $0.intersection(candidate.bounds).height <
            $1.intersection(candidate.bounds).width * $1.intersection(candidate.bounds).height
        }) {
            let score = scoreHypothesis(bestRegion, contentMap: contentMap)
            hypotheses.append(BoundaryHypothesis(bounds: bestRegion, strategy: .contentFit, score: score))
        } else if let contentBox = contentMap.contentBoundingBox() {
            // Fallback: if no connected component overlaps, use global bounding box
            let score = scoreHypothesis(contentBox, contentMap: contentMap)
            hypotheses.append(BoundaryHypothesis(bounds: contentBox, strategy: .contentFit, score: score))
        }

        // 2. Saliency-anchored: original candidate bounds (already trimmed in Pass 1)
        let saliencyScore = scoreHypothesis(candidate.bounds, contentMap: contentMap)
        hypotheses.append(BoundaryHypothesis(bounds: candidate.bounds, strategy: .saliencyAnchored, score: saliencyScore))

        // 3. Subject-anchored: union of overlapping subject bounds, clipped to content
        let overlappingSubjects = subjectBounds.filter { subject in
            let inter = candidate.bounds.intersection(subject)
            guard !inter.isNull else { return false }
            let sArea = subject.width * subject.height
            return sArea > 0 && (inter.width * inter.height) / sArea > 0.10
        }
        if !overlappingSubjects.isEmpty {
            var subjectUnion = overlappingSubjects[0]
            for s in overlappingSubjects.dropFirst() { subjectUnion = subjectUnion.union(s) }
            // Extend to overlapping content region (subject may be smaller than photo)
            let subjectContentRegions = contentRegions.filter { !$0.intersection(subjectUnion).isNull }
            if let bestSubjectRegion = subjectContentRegions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                subjectUnion = subjectUnion.union(bestSubjectRegion)
            }
            let subjectScore = scoreHypothesis(subjectUnion, contentMap: contentMap)
            hypotheses.append(BoundaryHypothesis(bounds: subjectUnion, strategy: .subjectAnchored, score: subjectScore))
        }

        // 4. Text-gap: find largest text-free vertical span containing the candidate
        let textGapBounds = findTextGapBounds(around: candidate.bounds, textBounds: textBounds)
        if let gap = textGapBounds {
            let gapScore = scoreHypothesis(gap, contentMap: contentMap)
            hypotheses.append(BoundaryHypothesis(bounds: gap, strategy: .textGap, score: gapScore))
        }

        return hypotheses
    }

    /// Scores a boundary hypothesis based on content density, coverage, and text exclusion.
    static func scoreHypothesis(_ bounds: CGRect, contentMap: ContentMap) -> Double {
        let density = contentMap.contentDensity(in: bounds)
        let coverage = contentMap.contentCoverage(of: bounds)
        let textExcl = contentMap.textExclusion(in: bounds)
        return density * 0.4 + coverage * 0.4 + textExcl * 0.2
    }

    /// Finds the largest text-free vertical span that contains the candidate center.
    /// Returns a rect with full width of the candidate but height limited by text above/below.
    private static func findTextGapBounds(around candidate: CGRect, textBounds: [CGRect]) -> CGRect? {
        guard !textBounds.isEmpty else { return nil }

        let centerY = candidate.midY

        // Find nearest text block above (higher Vision Y) and below (lower Vision Y)
        var ceilingY: CGFloat = 1.0  // default: top of image
        var floorY: CGFloat = 0.0    // default: bottom of image

        for text in textBounds {
            // Text above candidate center, overlapping horizontally
            let hOverlap = min(text.maxX, candidate.maxX) - max(text.minX, candidate.minX)
            guard hOverlap > candidate.width * 0.2 else { continue }

            if text.minY > centerY && text.minY < ceilingY {
                ceilingY = text.minY
            }
            if text.maxY < centerY && text.maxY > floorY {
                floorY = text.maxY
            }
        }

        let gapHeight = ceilingY - floorY
        guard gapHeight > 0.05 else { return nil }

        return CGRect(x: candidate.minX, y: floorY,
                      width: candidate.width, height: gapHeight)
    }

    // MARK: - Variance Excluding Text

    /// Computes color variance of an image while masking out text regions.
    /// If all visual variance comes from text (dark glyphs on background), the
    /// non-text variance will be near-zero — indicating a text-only region, not a figure.
    ///
    /// - Parameters:
    ///   - image: The image to analyze.
    ///   - textBounds: Normalized text bounding boxes (Vision coords, bottom-left origin).
    ///   - background: The page background RGB color.
    /// - Returns: Color variance (std dev of brightness) excluding text pixels.
    static func varianceExcludingText(
        image: CGImage,
        textBounds: [CGRect],
        background: (r: Double, g: Double, b: Double)
    ) -> CGFloat {
        // Use original resolution — no scaling, avoids interpolation artifacts
        // at text block edges that would leak dark pixels outside text bounds.
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return 0 }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var sum: Double = 0
        var sumSq: Double = 0
        var count = 0

        // Sparse sampling: step through pixels to keep processing reasonable for large images
        let stepX = max(1, width / 200)
        let stepY = max(1, height / 200)

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                // Convert pixel to normalized Vision coords to check text overlap
                let nx = CGFloat(x) / CGFloat(width)
                let ny = 1.0 - CGFloat(y) / CGFloat(height)

                // Skip pixels inside text bounding boxes
                let inText = textBounds.contains { $0.contains(CGPoint(x: nx, y: ny)) }
                if !inText {
                    let off = (y * width + x) * 4
                    let brightness = (Double(ptr[off]) + Double(ptr[off + 1]) + Double(ptr[off + 2])) / 3.0
                    sum += brightness
                    sumSq += brightness * brightness
                    count += 1
                }
                x += stepX
            }
            y += stepY
        }

        guard count > 1 else { return 0 }
        let mean = sum / Double(count)
        let variance = sumSq / Double(count) - mean * mean
        return CGFloat(max(0, variance).squareRoot())
    }

    // MARK: - Region Growing

    /// Grows a seed region outward in each direction until the edge pixels match
    /// the image background. This expands a saliency hint to the full visually
    /// coherent area, independent of background color.
    ///
    /// Works by sampling pixel rows/columns at the seed edges and comparing their
    /// brightness distribution to the image background (sampled from corners/edges).
    /// Expansion stops when a row/column looks like background, or hits a text bound.
    ///
    /// - Parameters:
    ///   - seed: Starting region in normalized Vision coordinates (bottom-left origin).
    ///   - image: The source image.
    ///   - textBounds: Text bounding boxes to avoid growing into.
    ///   - step: Fraction of image to step per iteration (default 0.02 = 2%).
    ///   - threshold: Minimum brightness difference from background to count as content (default 15).
    /// - Returns: Expanded region in normalized Vision coordinates.
    static func growRegion(
        _ seed: CGRect,
        in image: CGImage,
        textBounds: [CGRect],
        step: CGFloat = 0.02,
        threshold: Double = 15.0
    ) -> CGRect {
        let imgW = image.width
        let imgH = image.height
        guard imgW > 10, imgH > 10 else { return seed }

        // Render image to pixel buffer for direct access
        guard let ctx = CGContext(
            data: nil, width: imgW, height: imgH,
            bitsPerComponent: 8, bytesPerRow: imgW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return seed }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))
        guard let data = ctx.data else { return seed }
        let ptr = data.bindMemory(to: UInt8.self, capacity: imgW * imgH * 4)

        // Sample background color (full RGB) from edges/corners
        let bgColor = sampleBackgroundColor(ptr: ptr, width: imgW, height: imgH)
        let bgBrightness = (bgColor.r + bgColor.g + bgColor.b) / 3.0

        // Convert seed from Vision coords (bottom-left) to pixel coords (top-left)
        var top = Int((1.0 - seed.maxY) * CGFloat(imgH))
        var bottom = Int((1.0 - seed.minY) * CGFloat(imgH))
        var left = Int(seed.minX * CGFloat(imgW))
        var right = Int(seed.maxX * CGFloat(imgW))

        // Clamp to image bounds
        top = max(0, min(imgH - 1, top))
        bottom = max(0, min(imgH, bottom))
        left = max(0, min(imgW - 1, left))
        right = max(0, min(imgW, right))

        let stepX = max(1, Int(step * CGFloat(imgW)))
        let stepY = max(1, Int(step * CGFloat(imgH)))

        // Helper: check if a row/column in pixel coords overlaps with any text bound.
        // Tests multiple sample points along the row/column for robust detection.
        func rowOverlapsText(y py: Int, xStart: Int, xEnd: Int) -> Bool {
            let ny = 1.0 - CGFloat(py) / CGFloat(imgH)
            let step = max(1, (xEnd - xStart) / 10)
            var x = xStart
            while x < xEnd {
                let nx = CGFloat(x) / CGFloat(imgW)
                if textBounds.contains(where: { $0.contains(CGPoint(x: nx, y: ny)) }) {
                    return true
                }
                x += step
            }
            return false
        }

        func colOverlapsText(x px: Int, yStart: Int, yEnd: Int) -> Bool {
            let nx = CGFloat(px) / CGFloat(imgW)
            let step = max(1, (yEnd - yStart) / 10)
            var y = yStart
            while y < yEnd {
                let ny = 1.0 - CGFloat(y) / CGFloat(imgH)
                if textBounds.contains(where: { $0.contains(CGPoint(x: nx, y: ny)) }) {
                    return true
                }
                y += step
            }
            return false
        }

        // Growth helper: scan in one direction, stop at background OR text.
        // Uses "consecutive background" detection: if 2+ consecutive steps are background,
        // this is a real boundary (not just a single light row in a gradient).
        func scanRows(from start: Int, direction: Int, limit: Int) -> Int {
            var pos = start
            var consecutiveBg = 0
            let maxConsecutive = 2  // 2 consecutive background steps = definite boundary

            while (direction > 0 ? pos + stepY <= limit : pos - stepY >= limit) {
                let testRow = direction > 0 ? min(imgH - 1, pos + stepY - 1) : pos - stepY
                if rowOverlapsText(y: testRow, xStart: left, xEnd: right) { break }
                if rowLooksLikeBackground(ptr: ptr, y: testRow, xStart: left, xEnd: right,
                                           width: imgW, bgBrightness: bgBrightness, threshold: threshold,
                                           bgColor: bgColor) {
                    consecutiveBg += 1
                    if consecutiveBg >= maxConsecutive { break }
                } else {
                    consecutiveBg = 0
                }
                pos = direction > 0 ? min(limit, pos + stepY) : max(0, pos - stepY)
            }
            return pos
        }

        func scanCols(from start: Int, direction: Int, limit: Int) -> Int {
            var pos = start
            var consecutiveBg = 0
            let maxConsecutive = 2

            while (direction > 0 ? pos + stepX <= limit : pos - stepX >= limit) {
                let testCol = direction > 0 ? min(imgW - 1, pos + stepX - 1) : pos - stepX
                if colOverlapsText(x: testCol, yStart: top, yEnd: bottom) { break }
                if colLooksLikeBackground(ptr: ptr, x: testCol, yStart: top, yEnd: bottom,
                                           width: imgW, bgBrightness: bgBrightness, threshold: threshold,
                                           bgColor: bgColor) {
                    consecutiveBg += 1
                    if consecutiveBg >= maxConsecutive { break }
                } else {
                    consecutiveBg = 0
                }
                pos = direction > 0 ? min(limit, pos + stepX) : max(0, pos - stepX)
            }
            return pos
        }

        // Grow in all 4 directions
        top = scanRows(from: top, direction: -1, limit: 0)
        bottom = scanRows(from: bottom, direction: 1, limit: imgH)
        left = scanCols(from: left, direction: -1, limit: 0)
        right = scanCols(from: right, direction: 1, limit: imgW)

        // Convert back to Vision coordinates
        let normX = CGFloat(left) / CGFloat(imgW)
        let normW = CGFloat(right - left) / CGFloat(imgW)
        let normH = CGFloat(bottom - top) / CGFloat(imgH)
        let normY = 1.0 - CGFloat(bottom) / CGFloat(imgH)

        return CGRect(x: normX, y: normY, width: normW, height: normH)
    }

    /// Samples background brightness from image edges, avoiding the figure region.
    /// Uses the 4 edge midpoints (top, bottom, left, right) and 4 corners,
    /// taking the median to be robust against corners contaminated by figures.
    /// Samples background color (full RGB) from image edges and corners.
    /// Uses median of 8 patches (4 corners + 4 edge midpoints) to be robust
    /// against patches contaminated by figure content.
    /// Works on any background color: white, gray, dark, cream, etc.
    static func sampleBackgroundColor(
        ptr: UnsafePointer<UInt8>, width: Int, height: Int
    ) -> (r: Double, g: Double, b: Double) {
        let patchSize = min(8, min(width, height) / 4)

        struct PatchColor {
            var r: Double; var g: Double; var b: Double
            var brightness: Double { (r + g + b) / 3.0 }
        }

        var patches: [PatchColor] = []

        // Sample a 4×4 grid of points across the image, inset from edges to
        // avoid macOS window chrome (rounded corners, translucent title bar).
        // Using 16 points instead of 8 ensures the actual background color
        // dominates even when the title bar picks up a dark wallpaper.
        let cornerInset = max(patchSize, min(width, height) / 30)  // ~3% inset
        let gridSteps = 4
        var points: [(Int, Int)] = []
        for gy in 0..<gridSteps {
            for gx in 0..<gridSteps {
                let cx = cornerInset + (width - 2 * cornerInset - patchSize) * gx / (gridSteps - 1)
                let cy = cornerInset + (height - 2 * cornerInset - patchSize) * gy / (gridSteps - 1)
                points.append((cx, cy))
            }
        }

        for (cx, cy) in points {
            var rSum: Double = 0, gSum: Double = 0, bSum: Double = 0
            var count = 0
            for dy in 0..<patchSize {
                for dx in 0..<patchSize {
                    let px = min(width - 1, cx + dx)
                    let py = min(height - 1, cy + dy)
                    let off = (py * width + px) * 4
                    rSum += Double(ptr[off])
                    gSum += Double(ptr[off + 1])
                    bSum += Double(ptr[off + 2])
                    count += 1
                }
            }
            if count > 0 {
                patches.append(PatchColor(
                    r: rSum / Double(count),
                    g: gSum / Double(count),
                    b: bSum / Double(count)
                ))
            }
        }

        guard !patches.isEmpty else { return (128, 128, 128) }

        guard !patches.isEmpty else { return (128, 128, 128) }

        // Cluster patches by brightness into bins (width 40) and pick the
        // largest cluster. This is robust against both window chrome (dark
        // corners) and figure content (which tends to be distinct from bg).
        // The background color is typically the most common color in the image.
        let binWidth = 40.0
        var bins: [Int: [PatchColor]] = [:]
        for p in patches {
            let bin = Int(p.brightness / binWidth)
            bins[bin, default: []].append(p)
        }
        let largestBin = bins.max(by: { $0.value.count < $1.value.count })!.value

        // Average the patches in the largest cluster
        let avgR = largestBin.reduce(0.0) { $0 + $1.r } / Double(largestBin.count)
        let avgG = largestBin.reduce(0.0) { $0 + $1.g } / Double(largestBin.count)
        let avgB = largestBin.reduce(0.0) { $0 + $1.b } / Double(largestBin.count)
        return (avgR, avgG, avgB)
    }

    /// Convenience: returns just the brightness from sampleBackgroundColor.
    private static func sampleBackgroundBrightness(
        ptr: UnsafePointer<UInt8>, width: Int, height: Int
    ) -> Double {
        let bg = sampleBackgroundColor(ptr: ptr, width: width, height: height)
        return (bg.r + bg.g + bg.b) / 3.0
    }

    /// Checks if a row of pixels looks like background (>60% of sampled pixels match bg color).
    /// Uses full RGB comparison for robustness on colored backgrounds.
    private static func rowLooksLikeBackground(
        ptr: UnsafePointer<UInt8>, y: Int, xStart: Int, xEnd: Int,
        width: Int, bgBrightness: Double, threshold: Double,
        bgColor: (r: Double, g: Double, b: Double)? = nil
    ) -> Bool {
        let sampleCount = 20
        let range = max(1, xEnd - xStart)
        let step = max(1, range / sampleCount)
        var bgPixels = 0
        var total = 0

        var x = xStart
        while x < xEnd {
            let off = (y * width + x) * 4
            let r = Double(ptr[off]), g = Double(ptr[off + 1]), b = Double(ptr[off + 2])
            let isBackground: Bool
            if let bg = bgColor {
                // RGB distance check — more accurate than brightness-only
                let dist = abs(r - bg.r) + abs(g - bg.g) + abs(b - bg.b)
                isBackground = dist <= threshold * 3.0
            } else {
                let brightness = (r + g + b) / 3.0
                isBackground = abs(brightness - bgBrightness) <= threshold
            }
            if isBackground { bgPixels += 1 }
            total += 1
            x += step
        }
        return total > 0 && Double(bgPixels) / Double(total) >= 0.60
    }

    /// Checks if a column of pixels looks like background.
    private static func colLooksLikeBackground(
        ptr: UnsafePointer<UInt8>, x: Int, yStart: Int, yEnd: Int,
        width: Int, bgBrightness: Double, threshold: Double,
        bgColor: (r: Double, g: Double, b: Double)? = nil
    ) -> Bool {
        let sampleCount = 20
        let range = max(1, yEnd - yStart)
        let step = max(1, range / sampleCount)
        var bgPixels = 0
        var total = 0

        var y = yStart
        while y < yEnd {
            let off = (y * width + x) * 4
            let r = Double(ptr[off]), g = Double(ptr[off + 1]), b = Double(ptr[off + 2])
            let isBackground: Bool
            if let bg = bgColor {
                let dist = abs(r - bg.r) + abs(g - bg.g) + abs(b - bg.b)
                isBackground = dist <= threshold * 3.0
            } else {
                let brightness = (r + g + b) / 3.0
                isBackground = abs(brightness - bgBrightness) <= threshold
            }
            if isBackground { bgPixels += 1 }
            total += 1
            y += step
        }
        return total > 0 && Double(bgPixels) / Double(total) >= 0.60
    }

    // MARK: - Spatial Relationship Classification

    /// Classifies the spatial relationship between a figure region and a text block.
    ///
    /// Uses projection overlap on each axis to determine whether text is beside,
    /// above/below, inside, or far from the figure. This replaces ad-hoc proximity
    /// checks that cannot distinguish "text to the right" from "text below".
    ///
    /// - Parameters:
    ///   - figure: Normalized bounding box of the figure candidate.
    ///   - text: Normalized bounding box of a text block.
    ///   - proximity: Maximum gap (in normalized coords) to still count as adjacent. Default 0.03.
    ///   - overlapThreshold: Minimum intersection fraction of text area to count as overlapping. Default 0.05.
    static func classifyTextRelation(
        figure: CGRect, text: CGRect,
        proximity: CGFloat = 0.03,
        overlapThreshold: CGFloat = 0.05
    ) -> TextFigureRelation {
        // Check for substantial overlap first
        let intersection = figure.intersection(text)
        if !intersection.isNull {
            let textArea = text.width * text.height
            if textArea > 0 && (intersection.width * intersection.height) / textArea > overlapThreshold {
                return .overlapping
            }
        }

        // Compute projection overlaps on each axis.
        // Vertical projection: how much do they share on the Y axis?
        let vOverlap = min(figure.maxY, text.maxY) - max(figure.minY, text.minY)
        let minHeight = min(figure.height, text.height)
        let vFraction = minHeight > 0 ? max(0, vOverlap) / minHeight : 0

        // Horizontal projection: how much do they share on the X axis?
        let hOverlap = min(figure.maxX, text.maxX) - max(figure.minX, text.minX)
        let minWidth = min(figure.width, text.width)
        let hFraction = minWidth > 0 ? max(0, hOverlap) / minWidth : 0

        let projectionThreshold: CGFloat = 0.30

        // Horizontal adjacency: share vertical span, separated horizontally
        if vFraction > projectionThreshold {
            let hGap = max(text.minX - figure.maxX, figure.minX - text.maxX)
            if hGap >= 0 && hGap < proximity {
                return text.midX > figure.midX ? .adjacentRight : .adjacentLeft
            }
            // Also catch sub-pixel overlap where text edge barely touches figure edge
            if hGap < 0 && abs(hGap) < proximity {
                return text.midX > figure.midX ? .adjacentRight : .adjacentLeft
            }
        }

        // Vertical adjacency: share horizontal span, separated vertically
        if hFraction > projectionThreshold {
            let vGap = max(text.minY - figure.maxY, figure.minY - text.maxY)
            if vGap >= 0 && vGap < proximity {
                return text.midY > figure.midY ? .adjacentAbove : .adjacentBelow
            }
            if vGap < 0 && abs(vGap) < proximity {
                return text.midY > figure.midY ? .adjacentAbove : .adjacentBelow
            }
        }

        return .disjoint
    }

    /// Determines which expansion edges are blocked by adjacent text.
    ///
    /// For each text block, classifies the spatial relationship and adds the
    /// corresponding blocked edge. Returns a set of edges that should NOT be expanded.
    static func blockedExpansionEdges(
        figure: CGRect, textBounds: [CGRect],
        proximity: CGFloat = 0.03
    ) -> Set<ExpansionEdge> {
        var blocked = Set<ExpansionEdge>()
        for text in textBounds {
            let relation = classifyTextRelation(figure: figure, text: text, proximity: proximity)
            switch relation {
            case .adjacentRight:  blocked.insert(.right)
            case .adjacentLeft:   blocked.insert(.left)
            case .adjacentAbove:  blocked.insert(.top)
            case .adjacentBelow:  blocked.insert(.bottom)
            case .overlayOnFigure, .overlapping, .disjoint: break
            }
        }
        return blocked
    }

    // MARK: - Overlap Merging

    /// Merges overlapping regions using Intersection over Union (IoU).
    func mergeOverlapping(_ regions: [CGRect]) -> [CGRect] {
        guard !regions.isEmpty else { return [] }

        var merged = regions
        var changed = true

        while changed {
            changed = false
            var result: [CGRect] = []
            var used = Set<Int>()

            for i in 0..<merged.count {
                guard !used.contains(i) else { continue }

                var current = merged[i]
                for j in (i + 1)..<merged.count {
                    guard !used.contains(j) else { continue }

                    if iou(current, merged[j]) > mergeOverlapThreshold {
                        current = current.union(merged[j])
                        used.insert(j)
                        changed = true
                    }
                }
                result.append(current)
            }
            merged = result
        }

        return merged
    }

    /// Intersection over Union of two rectangles.
    func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea

        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
