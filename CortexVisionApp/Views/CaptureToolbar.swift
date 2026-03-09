import SwiftUI
import CortexVision

struct CaptureToolbar: View {
    @Binding var selectedMode: CaptureMode
    let isCaptureAvailable: Bool
    let captureButtonTooltip: String
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    selectedMode = mode
                    if isCaptureAvailable {
                        onCapture()
                    }
                } label: {
                    Label(mode.label, systemImage: mode.systemImage)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(CaptureToolbarButtonStyle(isSelected: selectedMode == mode))
                .help(selectedMode == mode ? captureButtonTooltip : mode.label)
            }
        }
    }
}

struct CaptureToolbarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
