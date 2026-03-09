import Foundation

/// Permission states for OS-level capabilities.
public enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
    case restricted
}

/// Abstracts OS permission management.
/// Current implementation: LocalPermissionManager (direct system checks).
/// Future App Store implementation: SandboxPermissionManager (sandbox-aware).
public protocol PermissionManager {
    /// Checks the current screen recording permission status.
    func screenRecordingStatus() -> PermissionStatus

    /// Requests screen recording permission. Returns true if granted.
    func requestScreenRecording() async -> Bool

    /// Checks the current accessibility permission status.
    func accessibilityStatus() -> PermissionStatus

    /// Requests accessibility permission. Returns true if granted.
    func requestAccessibility() async -> Bool

    /// Opens System Settings at the relevant permission pane.
    func openSystemSettings(for permission: PermissionType)
}

/// Types of permissions the app may need.
public enum PermissionType {
    case screenRecording
    case accessibility
}
