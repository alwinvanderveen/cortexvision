import SwiftUI
import CortexVision

struct PreviewPanel: View {
    let capturedImage: CGImage?
    let captureState: CaptureState
    let overlays: [AnalysisOverlay]
    let imageSize: CGSize

    var body: some View {
        Group {
            if let image = capturedImage {
                GeometryReader { geo in
                    // Use logical size (retina pixels / scaleFactor)
                    let scaleFactor: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
                    let logicalWidth = CGFloat(image.width) / scaleFactor
                    let logicalHeight = CGFloat(image.height) / scaleFactor
                    let imageAspect = logicalWidth / logicalHeight
                    let panelSize = CGSize(
                        width: geo.size.width - 32,
                        height: geo.size.height - 32
                    )
                    let fittedSize = fitSize(
                        imageAspect: imageAspect,
                        into: panelSize
                    )

                    ScrollView([.horizontal, .vertical]) {
                        ZStack {
                            Image(decorative: image, scale: scaleFactor)
                                .resizable()
                                .frame(width: fittedSize.width, height: fittedSize.height)

                            AnalysisOverlayView(
                                overlays: overlays,
                                imageSize: imageSize
                            )
                            .frame(width: fittedSize.width, height: fittedSize.height)
                        }
                        .padding(16)
                        .frame(
                            minWidth: geo.size.width,
                            minHeight: geo.size.height
                        )
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Compute the largest size that fits within `into` while preserving aspect ratio.
    private func fitSize(imageAspect: CGFloat, into container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        let containerAspect = container.width / container.height
        if imageAspect > containerAspect {
            // Image is wider — constrain by width
            return CGSize(width: container.width, height: container.width / imageAspect)
        } else {
            // Image is taller — constrain by height
            return CGSize(width: container.height * imageAspect, height: container.height)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No Capture")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text("Select a capture mode from the toolbar to get started")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
