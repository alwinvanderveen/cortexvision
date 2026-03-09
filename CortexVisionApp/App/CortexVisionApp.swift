import SwiftUI

@main
struct CortexVisionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: appViewModel)
                .frame(minWidth: 800, minHeight: 600)
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
