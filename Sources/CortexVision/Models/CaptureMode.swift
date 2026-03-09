import Foundation

/// The active capture mode selected by the user.
public enum CaptureMode: String, CaseIterable, Identifiable {
    case window = "window"
    case region = "region"
    case scrolling = "scrolling"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .window: return "Select Window"
        case .region: return "Select Region"
        case .scrolling: return "Scrolling Capture"
        }
    }

    public var systemImage: String {
        switch self {
        case .window: return "macwindow"
        case .region: return "rectangle.dashed"
        case .scrolling: return "scroll"
        }
    }
}
