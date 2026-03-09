import SwiftUI
import CortexVision

struct PreviewPanel: View {
    let capturedImage: CGImage?
    let captureState: CaptureState

    var body: some View {
        Group {
            if let image = capturedImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
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
