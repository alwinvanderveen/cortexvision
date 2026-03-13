import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Production implementation of PermissionManager for local (non-sandboxed) distribution.
public final class LocalPermissionManager: PermissionManager, @unchecked Sendable {
    public init() {}

    public func screenRecordingStatus() -> PermissionStatus {
        // CGPreflightScreenCaptureAccess is the only truly silent check.
        // It never triggers a system prompt.
        if CGPreflightScreenCaptureAccess() {
            return .granted
        }
        return .notDetermined
    }

    public func requestScreenRecording() async -> Bool {
        // Silent preflight first
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        // Not granted — trigger the system prompt
        CGRequestScreenCaptureAccess()
        return false
    }

    public func accessibilityStatus() -> PermissionStatus {
        if AXIsProcessTrusted() {
            return .granted
        }
        return .notDetermined
    }

    public func requestAccessibility() async -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: kCFBooleanTrue!] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openSystemSettings(for permission: PermissionType) {
        let urlString: String
        switch permission {
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
