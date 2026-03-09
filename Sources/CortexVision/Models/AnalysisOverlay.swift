import CoreGraphics
import Foundation

/// The kind of analysis annotation displayed on the preview.
public enum OverlayKind: String, Codable {
    case text
    case figure
}

/// A single analysis annotation with normalized bounds (0..1) relative to the image.
public struct AnalysisOverlay: Identifiable {
    public let id: UUID
    public let bounds: CGRect
    public let kind: OverlayKind
    public let label: String?

    public init(id: UUID = UUID(), bounds: CGRect, kind: OverlayKind, label: String? = nil) {
        self.id = id
        self.bounds = bounds
        self.kind = kind
        self.label = label
    }

    /// Converts normalized bounds (0..1) to pixel coordinates for a given image size.
    public func pixelRect(for imageSize: CGSize) -> CGRect {
        CGRect(
            x: bounds.origin.x * imageSize.width,
            y: bounds.origin.y * imageSize.height,
            width: bounds.width * imageSize.width,
            height: bounds.height * imageSize.height
        )
    }
}
