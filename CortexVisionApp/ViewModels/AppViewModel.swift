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
            analysisOverlays = [] // Reset overlays, will be populated by UC-4/UC-5
            captureState = .captured(width: result.image.width, height: result.image.height)
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
            analysisOverlays = [] // Reset overlays
            captureState = .captured(width: result.image.width, height: result.image.height)
        } catch {
            captureState = .error(error.localizedDescription)
        }
    }
}
