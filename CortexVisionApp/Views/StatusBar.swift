import SwiftUI
import CortexVision

struct StatusBar: View {
    let captureState: CaptureState
    let screenRecordingGranted: Bool

    var body: some View {
        HStack {
            statusIcon
            Text(captureState.statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            permissionIndicator
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

    private var permissionIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: screenRecordingGranted ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 9))
            Text("Screen Recording")
                .font(.system(size: 10))
        }
        .foregroundStyle(screenRecordingGranted ? .green : .red)
        .help(screenRecordingGranted
              ? "Screen recording permission granted"
              : "Screen recording permission not granted — open System Settings to fix")
    }
}
