import SwiftUI
import CortexVision

struct MainView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            HSplitView {
                PreviewPanel(
                    capturedImage: viewModel.capturedImage,
                    captureState: viewModel.captureState,
                    overlays: viewModel.analysisOverlays,
                    imageSize: viewModel.imageSize
                )
                .frame(minWidth: 400)

                ResultsPanel(
                    captureState: viewModel.captureState,
                    ocrResult: viewModel.ocrResult,
                    figureResult: viewModel.figureResult,
                    onToggleFigure: { index in
                        viewModel.toggleFigureSelection(at: index)
                    }
                )
                    .frame(minWidth: 250, idealWidth: 350)
            }

            // Status bar
            StatusBar(
                captureState: viewModel.captureState,
                screenRecordingGranted: viewModel.screenRecordingGranted
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                CaptureToolbar(
                    selectedMode: $viewModel.selectedMode,
                    isCaptureAvailable: viewModel.isCaptureAvailable,
                    captureButtonTooltip: viewModel.captureButtonTooltip,
                    onCapture: {
                        Task { await viewModel.startCapture() }
                    }
                )
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await viewModel.requestExport() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(!viewModel.isExportAvailable)
                .help(viewModel.isExportAvailable ? "Export results" : "Perform a capture and analysis first")
            }
        }
        .sheet(isPresented: $viewModel.showWindowPicker) {
            WindowPicker(
                windows: viewModel.availableWindows,
                onSelect: { window in
                    Task { await viewModel.captureSelectedWindow(window) }
                },
                onCancel: {
                    viewModel.showWindowPicker = false
                }
            )
        }
        .alert(
            "Permission Required",
            isPresented: Binding(
                get: { viewModel.permissionError != nil },
                set: { if !$0 { viewModel.permissionError = nil } }
            )
        ) {
            Button("Open System Settings") {
                viewModel.openPermissionSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.permissionError ?? "")
        }
        .onExitCommand {
            viewModel.cancelCapture()
        }
    }
}
