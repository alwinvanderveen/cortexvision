import SwiftUI
import CortexVision

struct AnalysisOverlayView: View {
    let overlays: [AnalysisOverlay]
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let scale = fitScale(imageSize: imageSize, viewSize: geometry.size)
            let offset = fitOffset(imageSize: imageSize, viewSize: geometry.size, scale: scale)

            ForEach(overlays) { overlay in
                let pixelRect = overlay.pixelRect(for: imageSize)
                let viewRect = CGRect(
                    x: pixelRect.origin.x * scale + offset.x,
                    y: pixelRect.origin.y * scale + offset.y,
                    width: pixelRect.width * scale,
                    height: pixelRect.height * scale
                )

                OverlayBox(overlay: overlay, rect: viewRect)
            }
        }
    }

    private func fitScale(imageSize: CGSize, viewSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(
            viewSize.width / imageSize.width,
            viewSize.height / imageSize.height
        )
    }

    private func fitOffset(imageSize: CGSize, viewSize: CGSize, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (viewSize.width - imageSize.width * scale) / 2,
            y: (viewSize.height - imageSize.height * scale) / 2
        )
    }
}

private struct OverlayBox: View {
    let overlay: AnalysisOverlay
    let rect: CGRect

    private var color: Color {
        switch overlay.kind {
        case .text: return .blue
        case .figure: return .green
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bounding box
            Rectangle()
                .strokeBorder(color.opacity(0.8), lineWidth: 2)
                .background(color.opacity(0.1))

            // Label
            if let label = overlay.label {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.8))
                    .cornerRadius(2)
                    .offset(x: 2, y: -14)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}
