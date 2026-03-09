import SwiftUI

@main
struct CortexVisionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if appViewModel.hasCompletedOnboarding {
                    MainView(viewModel: appViewModel)
                } else {
                    PermissionOnboardingView(
                        viewModel: appViewModel,
                        onContinue: { appViewModel.completeOnboarding() }
                    )
                }
            }
            .frame(minWidth: 800, minHeight: 600)
            .onAppear {
                appViewModel.checkPermissionsOnLaunch()
            }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit CortexVision") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

/// Terminate the app when the last window is closed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
