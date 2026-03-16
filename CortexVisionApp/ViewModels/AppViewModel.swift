import SwiftUI
import CoreGraphics
import CortexVision

@MainActor
public final class AppViewModel: ObservableObject {
    // MARK: - Published State

    @Published var selectedMode: CaptureMode = .window
    @Published var captureState: CaptureState = .idle
    @Published var capturedImage: CGImage?
    @Published var previewImage: CGImage?
    @Published var analysisOverlays: [AnalysisOverlay] = []
    @Published var overlayItems: [OverlayItem] = []
    @Published var selectedOverlayId: UUID?
    @Published var ocrResult: OCRResult?
    @Published var figureResult: FigureDetectionResult?
    @Published var showWindowPicker = false
    @Published var availableWindows: [WindowInfo] = []
    @Published var permissionError: String?
    @Published var hasCompletedOnboarding = false
    @Published var screenRecordingGranted = false

    // MARK: - Providers (injected via protocol)

    private(set) var captureProvider: CaptureProvider?
    private(set) var scrollCaptureProvider: ScrollCaptureProvider?
    private(set) var exportDestination: ExportDestination?
    private(set) var permissionManager: PermissionManager?
    private let figureRetoucher: (any FigureRetouching)?
    private var originalFigureImages: [UUID: CGImage] = [:]
    private let regionSelector = RegionSelector()
    private let ocrEngine = OCREngine()
    private let figureDetector = FigureDetector()
    private let overlayTextAnalyzer: any OverlayTextAnalyzing = HeuristicOverlayTextAnalyzer()
    let overlayController = OverlayInteractionController()
    private let debugLogURL: URL? = ProcessInfo.processInfo.environment["FIGURE_DEBUG"] == "1"
        ? URL(fileURLWithPath: "/tmp/cortexvision-analysis-debug.log") : nil

    private func debugLog(_ message: String) {
        guard let url = debugLogURL else { return }
        let line = message + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }

    // MARK: - Computed Properties

    var isCaptureAvailable: Bool {
        switch selectedMode {
        case .window, .region:
            return captureProvider != nil
        case .scrolling:
            return scrollCaptureProvider != nil
        }
    }

    var isExportAvailable: Bool {
        guard exportDestination != nil else { return false }
        if case .analyzed = captureState { return true }
        return false
    }

    var captureButtonTooltip: String {
        if isCaptureAvailable {
            return selectedMode.label
        }
        return "Capture provider not available"
    }

    var imageSize: CGSize {
        guard let image = previewImage ?? capturedImage else { return .zero }
        return CGSize(width: image.width, height: image.height)
    }

    // MARK: - Init

    init(
        captureProvider: CaptureProvider? = nil,
        scrollCaptureProvider: ScrollCaptureProvider? = nil,
        exportDestination: ExportDestination? = nil,
        permissionManager: PermissionManager? = nil,
        figureRetoucher: (any FigureRetouching)? = nil
    ) {
        self.captureProvider = captureProvider
        self.scrollCaptureProvider = scrollCaptureProvider
        self.exportDestination = exportDestination
        self.permissionManager = permissionManager
        self.figureRetoucher = figureRetoucher
    }

    /// Convenience init with default production providers.
    convenience init() {
        self.init(
            captureProvider: ScreenCaptureKitProvider(),
            permissionManager: LocalPermissionManager(),
            figureRetoucher: FigureInpaintingPipeline()
        )
    }

    // MARK: - Onboarding / Permissions

    /// Checks permissions at launch (silent, no system prompt).
    func checkPermissionsOnLaunch() {
        guard let pm = permissionManager else {
            hasCompletedOnboarding = true
            screenRecordingGranted = true
            return
        }
        let granted = pm.screenRecordingStatus() == .granted
        screenRecordingGranted = granted
        if granted {
            hasCompletedOnboarding = true
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        screenRecordingGranted = permissionManager?.screenRecordingStatus() == .granted
    }

    // MARK: - Actions

    func selectMode(_ mode: CaptureMode) {
        selectedMode = mode
    }

    func startCapture() async {
        permissionError = nil
        capturedImage = nil
        previewImage = nil
        analysisOverlays = []
        ocrResult = nil
        figureResult = nil
        originalFigureImages = [:]
        captureState = .idle

        // Check permission (silent preflight first, prompt only if needed)
        if let pm = permissionManager {
            if pm.screenRecordingStatus() != .granted {
                let granted = await pm.requestScreenRecording()
                screenRecordingGranted = granted
                if !granted {
                    captureState = .error(CaptureError.permissionDenied.localizedDescription)
                    permissionError = CaptureError.permissionDenied.localizedDescription
                    return
                }
            }
        }

        switch selectedMode {
        case .window:
            await startWindowCapture()
        case .region:
            startRegionCapture()
        case .scrolling:
            // Will be implemented in UC-6
            break
        }
    }

    func cancelCapture() {
        regionSelector.cancel()
        captureState = .idle
    }

    func requestExport() async {
        guard isExportAvailable else { return }
        // Actual export logic will be implemented in UC-7
    }

    func openPermissionSettings() {
        permissionManager?.openSystemSettings(for: .screenRecording)
    }

    // MARK: - Window Capture

    private func startWindowCapture() async {
        guard let provider = captureProvider else { return }

        do {
            let windows = try await provider.availableWindows()
            availableWindows = windows
            showWindowPicker = true
        } catch {
            captureState = .error(error.localizedDescription)
        }
    }

    func captureSelectedWindow(_ window: WindowInfo) async {
        showWindowPicker = false
        captureState = .capturing

        guard let provider = captureProvider else { return }

        do {
            let result = try await provider.captureWindow(id: window.id)
            capturedImage = result.image
            previewImage = result.image
            captureState = .captured(width: result.image.width, height: result.image.height)
            await runAnalysis(on: result.image)
        } catch {
            captureState = .error(error.localizedDescription)
        }
    }

    // MARK: - Region Capture

    private func startRegionCapture() {
        captureState = .capturing

        regionSelector.beginSelection { [weak self] rect in
            Task { @MainActor in
                guard let self else { return }
                guard let rect else {
                    self.captureState = .idle
                    return
                }
                await self.performRegionCapture(rect)
            }
        }
    }

    private func performRegionCapture(_ rect: CGRect) async {
        guard let provider = captureProvider else { return }

        do {
            let result = try await provider.captureRegion(rect)
            capturedImage = result.image
            previewImage = result.image
            captureState = .captured(width: result.image.width, height: result.image.height)
            await runAnalysis(on: result.image)
        } catch {
            captureState = .error(error.localizedDescription)
        }
    }

    // MARK: - Analysis (OCR + Figure Detection)

    private func runAnalysis(on image: CGImage) async {
        captureState = .analyzing
        analysisOverlays = []
        ocrResult = nil
        figureResult = nil
        previewImage = image

        let debug = debugLogURL != nil

        do {
            // Clear previous debug log
            if debug {
                try? "".data(using: .utf8)?.write(to: debugLogURL!)
                debugLog("[AppViewModel] === ANALYSIS START (image \(image.width)×\(image.height), bpc=\(image.bitsPerComponent), cs=\(image.colorSpace?.name ?? "nil" as CFString)) ===")
            }

            // Run OCR first (we need text bounds for figure exclusion)
            let ocrRes = try await ocrEngine.recognizeText(in: image)
            ocrResult = ocrRes

            if debug {
                debugLog("[AppViewModel] OCR: \(ocrRes.textBlocks.count) blocks, \(ocrRes.wordCount) words")
                for (i, block) in ocrRes.textBlocks.enumerated() {
                    debugLog("[AppViewModel]   text[\(i)] bounds=(\(String(format: "%.3f %.3f %.3f %.3f", block.bounds.minX, block.bounds.minY, block.bounds.width, block.bounds.height))) \"\(String(block.text.prefix(40)))\"")
                }
            }

            // Run figure detection with text exclusion
            let textBounds = ocrRes.textBlocks.map(\.bounds)
            let figureRes = try await figureDetector.detectFigures(in: image, textBounds: textBounds)
            figureResult = figureRes
            originalFigureImages = Dictionary(
                uniqueKeysWithValues: figureRes.figures.compactMap { figure in
                    guard let extractedImage = figure.extractedImage else { return nil }
                    return (figure.id, extractedImage)
                }
            )

            if debug {
                debugLog("[AppViewModel] Figures: \(figureRes.figures.count)")
                for (i, fig) in figureRes.figures.enumerated() {
                    let imgDesc = fig.extractedImage.map { "\($0.width)×\($0.height)" } ?? "nil"
                    debugLog("[AppViewModel]   fig[\(i)] bounds=(\(String(format: "%.3f %.3f %.3f %.3f", fig.bounds.minX, fig.bounds.minY, fig.bounds.width, fig.bounds.height))) img=\(imgDesc) selected=\(fig.isSelected)")
                }
            }

            // Build overlays: text (blue) + figures (green)
            // Vision uses bottom-left origin (y=0 at bottom), but SwiftUI/CGImage
            // use top-left origin (y=0 at top), so flip the Y coordinate.
            var overlays: [AnalysisOverlay] = []

            overlays += ocrRes.textBlocks.map { block in
                AnalysisOverlay(
                    bounds: CGRect(
                        x: block.bounds.origin.x,
                        y: 1.0 - block.bounds.origin.y - block.bounds.height,
                        width: block.bounds.width,
                        height: block.bounds.height
                    ),
                    kind: .text,
                    label: block.text.prefix(30).description
                )
            }

            overlays += figureRes.figures.map { figure in
                AnalysisOverlay(
                    bounds: CGRect(
                        x: figure.bounds.origin.x,
                        y: 1.0 - figure.bounds.origin.y - figure.bounds.height,
                        width: figure.bounds.width,
                        height: figure.bounds.height
                    ),
                    kind: .figure,
                    label: figure.label
                )
            }

            if debug {
                debugLog("[AppViewModel] Overlays: \(overlays.filter { $0.kind == .text }.count) text + \(overlays.filter { $0.kind == .figure }.count) figure")
            }

            analysisOverlays = overlays
            buildOverlayItems()
            captureState = .analyzed(wordCount: ocrRes.wordCount, figureCount: figureRes.figures.count)

            if debug { debugLog("[AppViewModel] === ANALYSIS END ===") }
        } catch {
            if debug { debugLog("[AppViewModel] === ANALYSIS ERROR: \(error) ===") }
            captureState = .error("Analysis failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Overlay Interaction (UC-5a / UC-5b)
    // Delegates to OverlayInteractionController for testability (no SwiftUI dependency).

    /// IDs of TextBlocks that are covered by a non-excluded text overlay.
    var includedTextBlockIds: Set<UUID> {
        overlayController.includedTextBlockIds
    }

    /// IDs of TextBlocks that are excluded via overlay toggle.
    var excludedTextBlockIds: Set<UUID> {
        overlayController.excludedTextBlockIds
    }

    /// Indices of figures whose overlay is excluded.
    var excludedFigureIndices: Set<Int> {
        overlayController.excludedFigureIndices
    }

    /// Toggle figure exclusion from ResultsPanel by figure index (unified with preview eye icon).
    func toggleFigureExclusionByIndex(_ index: Int) {
        guard let item = overlayController.overlayItems.first(where: {
            $0.kind == .figure && $0.sourceFigureIndex == index
        }) else { return }
        overlayController.toggleOverlayExclusion(id: item.id)
        syncOverlayState()
    }

    /// OCR text blocks covered by non-excluded overlays. Used for display and copy.
    var filteredTextBlocks: [TextBlock] {
        guard let ocrRes = ocrResult else { return [] }
        let included = includedTextBlockIds
        return ocrRes.textBlocks.filter { included.contains($0.id) }
    }

    /// Full text from included blocks only.
    var filteredFullText: String {
        filteredTextBlocks.map(\.text).joined(separator: "\n")
    }

    /// Syncs published state from the overlay controller.
    private func syncOverlayState() {
        overlayItems = overlayController.overlayItems
        selectedOverlayId = overlayController.selectedOverlayId
    }

    /// Builds interactive overlay items from OCR + figure detection results.
    /// Classifies each text block against each figure to identify overlay-text.
    func buildOverlayItems() {
        guard let ocrRes = ocrResult, let figureRes = figureResult else {
            overlayController.buildOverlayItems(textBlocks: [] as [(id: UUID, text: String, bounds: CGRect)], figures: [])
            syncOverlayState()
            return
        }

        let textInputs = ocrRes.textBlocks.map { (id: $0.id, text: $0.text, bounds: $0.bounds) }

        // Classify text blocks against figures (requires captured image)
        var classifications: [UUID: OverlayInteractionController.TextClassification] = [:]
        if let image = capturedImage, !figureRes.figures.isEmpty {
            let pageBgColor = samplePageBackgroundColor(from: image)
            for block in ocrRes.textBlocks {
                for (figIdx, figure) in figureRes.figures.enumerated() {
                    // Only classify if text bounds intersect with figure bounds
                    guard block.bounds.intersects(figure.bounds) else { continue }
                    let cls = overlayTextAnalyzer.classify(
                        text: block.bounds,
                        figure: figure.bounds,
                        in: image,
                        pageBgColor: pageBgColor
                    )
                    if cls == .overlay || cls == .edgeOverlay {
                        classifications[block.id] = (classification: cls, figureIndex: figIdx)
                        break // Text belongs to at most one figure
                    }
                }
            }
        }

        overlayController.buildOverlayItems(
            textBlocks: textInputs,
            figures: figureRes.figures,
            textClassifications: classifications
        )
        syncOverlayState()
    }

    /// Samples the page background color from image edges for text classification.
    private func samplePageBackgroundColor(from image: CGImage) -> (r: Double, g: Double, b: Double) {
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

    /// Select an overlay by ID. Deselects the previously selected overlay.
    func selectOverlay(id: UUID?) {
        overlayController.selectOverlay(id: id)
        syncOverlayState()
    }

    /// Move an overlay by a normalized delta.
    func moveOverlay(id: UUID, dx: CGFloat, dy: CGFloat) {
        overlayController.moveOverlay(id: id, dx: dx, dy: dy)
        syncOverlayState()
    }

    /// Resize an overlay to new bounds.
    func resizeOverlay(id: UUID, to newBounds: CGRect) {
        overlayController.resizeOverlay(id: id, to: newBounds)
        syncOverlayState()
    }

    /// Toggle exclusion state of an overlay (include/exclude from export).
    func toggleOverlayExclusion(id: UUID) {
        let shouldRefreshRetouchedPreview = overlayController.overlayItems.first(where: { $0.id == id }).map {
            $0.kind == .text && ($0.textOverlayClassification == .overlay || $0.textOverlayClassification == .edgeOverlay)
        } ?? false
        overlayController.toggleOverlayExclusion(id: id)
        syncOverlayState()
        if shouldRefreshRetouchedPreview {
            rebuildRetouchedPreview()
        }
    }

    /// Delete the selected overlay.
    func deleteSelectedOverlay() {
        overlayController.deleteSelectedOverlay()
        syncOverlayState()
    }

    /// Add a new manually drawn figure overlay.
    func addManualFigureOverlay(bounds: CGRect) {
        overlayController.addManualFigureOverlay(bounds: bounds)
        syncOverlayState()
    }

    /// Re-extracts the figure CGImage for an overlay after it was moved/resized.
    func reExtractFigure(for overlayId: UUID) {
        guard let image = capturedImage, let result = figureResult else { return }

        if let extraction = overlayController.reExtractFigure(
            for: overlayId, from: image, figures: result.figures
        ) {
            if let updatedFigures = extraction.updatedFigures {
                for figure in updatedFigures {
                    if let extractedImage = figure.extractedImage {
                        originalFigureImages[figure.id] = extractedImage
                    }
                }
                figureResult = FigureDetectionResult(figures: updatedFigures)
            }
        }
        rebuildRetouchedPreview()
        syncOverlayState()
    }

    /// Rebuilds the preview image and figure thumbnails from the original captured image,
    /// applying retouching only to excluded overlay-text items that belong to figures.
    private func rebuildRetouchedPreview() {
        guard let sourceImage = capturedImage, let result = figureResult else {
            previewImage = capturedImage
            return
        }

        seedOriginalFigureImagesIfNeeded(figures: result.figures, sourceImage: sourceImage)

        let figureOverlayIdsByIndex = Dictionary(
            uniqueKeysWithValues: overlayController.overlayItems
                .filter { $0.kind == .figure && $0.sourceFigureIndex != nil }
                .map { ($0.sourceFigureIndex!, $0.id) }
        )
        let excludedOverlayTextsByFigure = Dictionary(
            grouping: overlayController.overlayItems.compactMap { item -> (UUID, OverlayItem)? in
                guard item.kind == .text,
                      item.isExcluded,
                      (item.textOverlayClassification == .overlay || item.textOverlayClassification == .edgeOverlay),
                      let figureOverlayId = item.associatedFigureOverlayId else {
                    return nil
                }
                return (figureOverlayId, item)
            },
            by: \.0
        ).mapValues { $0.map(\.1) }
        let textBlocksById = Dictionary(
            uniqueKeysWithValues: (ocrResult?.textBlocks ?? []).map { ($0.id, $0) }
        )

        if excludedOverlayTextsByFigure.isEmpty {
            let restoredFigures = result.figures.map { figure in
                restoredFigure(from: figure, sourceImage: sourceImage)
            }
            figureResult = FigureDetectionResult(figures: restoredFigures)
            previewImage = sourceImage
            return
        }

        var updatedFigures = result.figures
        var composedPreview = sourceImage

        for (index, figure) in result.figures.enumerated() {
            let baseCrop = originalFigureImages[figure.id]
                ?? FigurePreviewComposer.cropFigure(from: sourceImage, figureBounds: figure.bounds)
                ?? figure.extractedImage
            guard let figureOverlayId = figureOverlayIdsByIndex[index] else {
                updatedFigures[index] = restoredFigure(from: figure, sourceImage: sourceImage)
                continue
            }

            let excludedTextItems = excludedOverlayTextsByFigure[figureOverlayId] ?? []
            let excludedTextBounds = Array(
                Set(excludedTextItems.flatMap(\.sourceTextBlockIds))
            ).compactMap { textBlocksById[$0]?.bounds }

            var finalCrop = baseCrop
            if !excludedTextBounds.isEmpty, let figureRetoucher {
                finalCrop = figureRetoucher.removeText(
                    from: sourceImage,
                    figureBounds: figure.bounds,
                    textBounds: excludedTextBounds
                ) ?? baseCrop
            }

            updatedFigures[index] = DetectedFigure(
                id: figure.id,
                bounds: figure.bounds,
                label: figure.label,
                extractedImage: finalCrop,
                isSelected: figure.isSelected
            )

            if !excludedTextBounds.isEmpty,
               let finalCrop,
               let composited = FigurePreviewComposer.compositeFigure(
                finalCrop,
                into: composedPreview,
                figureBounds: figure.bounds
            ) {
                composedPreview = composited
            }
        }

        figureResult = FigureDetectionResult(figures: updatedFigures)
        previewImage = composedPreview
    }

    private func seedOriginalFigureImagesIfNeeded(figures: [DetectedFigure], sourceImage: CGImage) {
        for figure in figures where originalFigureImages[figure.id] == nil {
            if let extractedImage = figure.extractedImage {
                originalFigureImages[figure.id] = extractedImage
            } else if let cropped = FigurePreviewComposer.cropFigure(from: sourceImage, figureBounds: figure.bounds) {
                originalFigureImages[figure.id] = cropped
            }
        }
    }

    private func restoredFigure(from figure: DetectedFigure, sourceImage: CGImage) -> DetectedFigure {
        let originalCrop = originalFigureImages[figure.id]
            ?? FigurePreviewComposer.cropFigure(from: sourceImage, figureBounds: figure.bounds)
            ?? figure.extractedImage
        return DetectedFigure(
            id: figure.id,
            bounds: figure.bounds,
            label: figure.label,
            extractedImage: originalCrop,
            isSelected: figure.isSelected
        )
    }
}
