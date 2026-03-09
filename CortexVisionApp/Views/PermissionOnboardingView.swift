import SwiftUI
import CortexVision

struct PermissionOnboardingView: View {
    @ObservedObject var viewModel: AppViewModel
    let onContinue: () -> Void

    @State private var screenRecordingGranted = false
    @State private var checking = true

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon / header
            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(.tint)

                Text("Welcome to CortexVision")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("Before we begin, CortexVision needs permission to capture your screen.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Permission cards
            VStack(spacing: 16) {
                PermissionCard(
                    title: "Screen Recording",
                    description: "Required to capture windows and screen regions",
                    systemImage: "rectangle.dashed.and.paperclip",
                    status: screenRecordingGranted ? .granted : .required,
                    action: requestScreenRecording
                )
            }
            .frame(maxWidth: 420)

            // Continue or instructions
            VStack(spacing: 12) {
                if screenRecordingGranted {
                    Button(action: onContinue) {
                        Text("Get Started")
                            .font(.headline)
                            .frame(minWidth: 160)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("After granting permission in System Settings, restart the app to apply the change.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button("Restart CortexVision") {
                        relaunchApp()
                    }
                    .controlSize(.large)
                }
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            recheckPermissions()
        }
    }

    private func requestScreenRecording() {
        Task {
            if let pm = viewModel.permissionManager {
                // This triggers the system prompt (only when user clicks Grant Access)
                let _ = await pm.requestScreenRecording()
                recheckPermissions()
            }
        }
    }

    private func recheckPermissions() {
        checking = true
        let granted: Bool
        if let pm = viewModel.permissionManager {
            granted = pm.screenRecordingStatus() == .granted
        } else {
            granted = false
        }
        screenRecordingGranted = granted
        checking = false
    }

    private func relaunchApp() {
        // Launch a new instance of ourselves, then quit the current one
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        try? task.run()

        // Give the new instance a moment to start, then quit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - Permission Card

private enum PermissionCardStatus {
    case granted
    case required
}

private struct PermissionCard: View {
    let title: String
    let description: String
    let systemImage: String
    let status: PermissionCardStatus
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(status == .granted ? .green : .orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if status == .granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button("Grant Access") {
                    action()
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(status == .granted ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        }
    }
}
