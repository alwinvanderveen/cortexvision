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
                    captureState: viewModel.captureState
                )
                .frame(minWidth: 400)

                ResultsPanel()
                    .frame(minWidth: 250, idealWidth: 350)
            }

            // Status bar
            StatusBar(captureState: viewModel.captureState)
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
    }
}
