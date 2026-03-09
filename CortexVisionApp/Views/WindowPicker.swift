import SwiftUI
import CortexVision

struct WindowPicker: View {
    let windows: [WindowInfo]
    let onSelect: (WindowInfo) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    private var filteredWindows: [WindowInfo] {
        if searchText.isEmpty {
            return windows
        }
        let query = searchText.lowercased()
        return windows.filter {
            $0.title.lowercased().contains(query) ||
            $0.appName.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Window")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            // Search
            TextField("Filter windows...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()

            // Window list
            if filteredWindows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                    Text("No windows found")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredWindows) { window in
                    WindowRow(window: window)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(window)
                        }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 400, height: 500)
    }
}

private struct WindowRow: View {
    let window: WindowInfo

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            Group {
                if let icon = window.appIcon {
                    Image(decorative: icon, scale: 1.0)
                        .resizable()
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .cornerRadius(6)

            // Window info
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(window.appName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Dimensions
            Text("\(Int(window.frame.width))×\(Int(window.frame.height))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
