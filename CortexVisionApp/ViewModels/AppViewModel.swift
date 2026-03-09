import SwiftUI
import CoreGraphics
import CortexVision

@MainActor
public final class AppViewModel: ObservableObject {
    // MARK: - Published State

    @Published var selectedMode: CaptureMode = .window
    @Published var captureState: CaptureState = .idle
    @Published var capturedImage: CGImage?

    // MARK: - Providers (injected via protocol)

    private var captureProvider: CaptureProvider?
    private var scrollCaptureProvider: ScrollCaptureProvider?
    private var exportDestination: ExportDestination?
    private var permissionManager: PermissionManager?

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

    // MARK: - Actions

    func selectMode(_ mode: CaptureMode) {
        selectedMode = mode
    }

    func startCapture() async {
        guard isCaptureAvailable else { return }
        captureState = .capturing
        // Actual capture logic will be implemented in UC-3
    }

    func requestExport() async {
        guard isExportAvailable else { return }
        // Actual export logic will be implemented in UC-7
    }
}
