import SwiftUI
import CortexVision

struct StatusBar: View {
    let captureState: CaptureState

    var body: some View {
        HStack {
            statusIcon
            Text(captureState.statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch captureState {
        case .idle:
            Image(systemName: "circle")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        case .capturing, .analyzing:
            ProgressView()
                .controlSize(.mini)
        case .captured:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.green)
        case .analyzed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.blue)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        }
    }
}
