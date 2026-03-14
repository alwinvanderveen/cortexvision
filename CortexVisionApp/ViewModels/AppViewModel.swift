import SwiftUI
import CoreGraphics
import CortexVision

@MainActor
public final class AppViewModel: ObservableObject {
    // MARK: - Published State

    @Published var selectedMode: CaptureMode = .window
    @Published var captureState: CaptureState = .idle
    @Published var capturedImage: CGImage?
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
    private let regionSelector = RegionSelector()
    private let ocrEngine = OCREngine()
    private let figureDetector = FigureDetector()
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
        guard let image = capturedImage else { return .zero }
        return CGSize(width: image.width, height: image.height)
    }

    // MARK: - Init

    init(
        captureProvider: CaptureProvider? = nil,
        scrollCaptureProvider: ScrollCaptureProvider? = nil,
        exportDestination: ExportDestination? = nil,
        permissionManager: PermissionManager? = nil
    ) {
        self.captureProvider = captureProvider
        self.scrollCaptureProvider = scrollCaptureProvider
        self.exportDestination = exportDestination
        self.permissionManager = permissionManager
    }

    /// Convenience init with default production providers.
    convenience init() {
        self.init(
            captureProvider: ScreenCaptureKitProvider(),
            permissionManager: LocalPermissionManager()
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
        analysisOverlays = []
        ocrResult = nil
        figureResult = nil
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

    /// Toggle selection state of a detected figure by index.
    func toggleFigureSelection(at index: Int) {
        guard let result = figureResult, index < result.figures.count else { return }
        var figures = result.figures
        figures[index].isSelected.toggle()
        figureResult = FigureDetectionResult(figures: figures)
    }

    // MARK: - Overlay Interaction (UC-5a)

    private let textBlockGrouper = TextBlockGrouper()

    /// Builds interactive overlay items from OCR + figure detection results.
    func buildOverlayItems() {
        guard let ocrRes = ocrResult, let figureRes = figureResult else {
            overlayItems = []
            return
        }

        // Group text blocks into logical regions
        let textInputs = ocrRes.textBlocks.map { (text: $0.text, bounds: $0.bounds) }
        let textOverlays = textBlockGrouper.group(textInputs)

        // Create figure overlay items (with SwiftUI Y-flip)
        let figureOverlays = figureRes.figures.enumerated().map { index, figure in
            OverlayItem(
                bounds: CGRect(
                    x: figure.bounds.origin.x,
                    y: 1.0 - figure.bounds.origin.y - figure.bounds.height,
                    width: figure.bounds.width,
                    height: figure.bounds.height
                ),
                kind: .figure,
                label: figure.label,
                sourceFigureIndex: index
            )
        }

        overlayItems = textOverlays + figureOverlays
        selectedOverlayId = nil
    }

    /// Select an overlay by ID. Deselects the previously selected overlay.
    func selectOverlay(id: UUID?) {
        // Deselect previous
        if let prevId = selectedOverlayId,
           let prevIdx = overlayItems.firstIndex(where: { $0.id == prevId }) {
            overlayItems[prevIdx].isSelected = false
        }
        // Select new
        selectedOverlayId = id
        if let newId = id,
           let newIdx = overlayItems.firstIndex(where: { $0.id == newId }) {
            overlayItems[newIdx].isSelected = true
        }
    }

    /// Move an overlay by a normalized delta.
    func moveOverlay(id: UUID, dx: CGFloat, dy: CGFloat) {
        guard let idx = overlayItems.firstIndex(where: { $0.id == id }) else { return }
        overlayItems[idx].move(dx: dx, dy: dy)
    }

    /// Resize an overlay to new bounds.
    func resizeOverlay(id: UUID, to newBounds: CGRect) {
        guard let idx = overlayItems.firstIndex(where: { $0.id == id }) else { return }
        overlayItems[idx].resize(to: newBounds)
    }

    /// Toggle exclusion state of an overlay (include/exclude from export).
    func toggleOverlayExclusion(id: UUID) {
        guard let idx = overlayItems.firstIndex(where: { $0.id == id }) else { return }
        overlayItems[idx].isExcluded.toggle()
    }

    /// Delete the selected overlay.
    func deleteSelectedOverlay() {
        guard let id = selectedOverlayId else { return }
        overlayItems.removeAll { $0.id == id }
        selectedOverlayId = nil
    }

    /// Add a new manually drawn figure overlay.
    func addManualFigureOverlay(bounds: CGRect) {
        let label = "Figure \(overlayItems.filter { $0.kind == .figure }.count + 1)"
        let item = OverlayItem(
            bounds: bounds,
            kind: .figure,
            label: label,
            isManual: true
        )
        overlayItems.append(item)
        selectOverlay(id: item.id)
    }

    /// Re-extracts the figure CGImage for an overlay after it was moved/resized.
    func reExtractFigure(for overlayId: UUID) {
        guard let image = capturedImage,
              let idx = overlayItems.firstIndex(where: { $0.id == overlayId }),
              overlayItems[idx].kind == .figure else { return }

        let item = overlayItems[idx]
        // Convert SwiftUI bounds back to pixel rect
        let pixelRect = CGRect(
            x: item.bounds.origin.x * CGFloat(image.width),
            y: item.bounds.origin.y * CGFloat(image.height),
            width: item.bounds.width * CGFloat(image.width),
            height: item.bounds.height * CGFloat(image.height)
        )
        let clamped = pixelRect.intersection(
            CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        guard !clamped.isEmpty, let cropped = image.cropping(to: clamped) else { return }

        // Update the figure result if this was an auto-detected figure
        if let figIdx = item.sourceFigureIndex, let result = figureResult, figIdx < result.figures.count {
            var figures = result.figures
            // Convert SwiftUI bounds back to Vision bounds for the figure
            let visionBounds = CGRect(
                x: item.bounds.origin.x,
                y: 1.0 - item.bounds.origin.y - item.bounds.height,
                width: item.bounds.width,
                height: item.bounds.height
            )
            figures[figIdx] = DetectedFigure(
                id: figures[figIdx].id,
                bounds: visionBounds,
                label: figures[figIdx].label,
                extractedImage: cropped,
                isSelected: figures[figIdx].isSelected
            )
            figureResult = FigureDetectionResult(figures: figures)
        }
    }
}
