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
                    interactiveItems: viewModel.overlayItems,
                    selectedOverlayId: viewModel.selectedOverlayId,
                    imageSize: viewModel.imageSize,
                    onSelectOverlay: { id in viewModel.selectOverlay(id: id) },
                    onMoveOverlay: { id, dx, dy in
                        viewModel.moveOverlay(id: id, dx: dx, dy: dy)
                        viewModel.reExtractFigure(for: id)
                    },
                    onResizeOverlay: { id, bounds in
                        viewModel.resizeOverlay(id: id, to: bounds)
                        viewModel.reExtractFigure(for: id)
                    },
                    onDeleteOverlay: { viewModel.deleteSelectedOverlay() },
                    onDrawNewOverlay: { bounds in viewModel.addManualFigureOverlay(bounds: bounds) },
                    onToggleExclusion: { id in viewModel.toggleOverlayExclusion(id: id) }
                )
                .frame(minWidth: 500, idealWidth: 700)

                ResultsPanel(
                    captureState: viewModel.captureState,
                    ocrResult: viewModel.ocrResult,
                    figureResult: viewModel.figureResult,
                    excludedTextOverlayIds: Set(viewModel.overlayItems.filter { $0.kind == .text && $0.isExcluded }.map(\.id)),
                    onToggleFigure: { index in
                        viewModel.toggleFigureSelection(at: index)
                    }
                )
                    .frame(minWidth: 220, idealWidth: 300)
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
