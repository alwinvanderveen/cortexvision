import CoreGraphics
import Foundation

/// Generates a binary mask image from text block bounds.
/// White pixels (255) where text is, black pixels (0) elsewhere.
/// Used as input for the LaMa inpainting model.
public struct TextMaskGenerator {

    /// Minimum padding (in pixels) added around each text bound.
    private let minPadding: Int
    /// Proportional padding as fraction of text block height (e.g. 0.5 = 50% of height on each side).
    /// Covers UI elements like buttons/badges that extend beyond text glyphs.
    private let proportionalPadding: CGFloat

    public init(minPadding: Int = 4, proportionalPadding: CGFloat = 1.0) {
        self.minPadding = minPadding
        self.proportionalPadding = proportionalPadding
    }

    /// Generates a binary mask for the given text bounds on an image of the specified size.
    ///
    /// - Parameters:
    ///   - textBounds: Text block bounds in normalized coordinates (0..1), Vision coords (bottom-left origin).
    ///   - imageSize: Size of the source image in pixels.
    /// - Returns: A single-channel grayscale CGImage where text regions are white (255) and the rest is black (0).
    public func generateMask(
        textBounds: [CGRect],
        imageSize: CGSize
    ) -> CGImage? {
        let width = Int(imageSize.width)
        let height = Int(imageSize.height)
        guard width > 0, height > 0 else { return nil }

        // Create grayscale bitmap context
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // Fill with black (0 = keep)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Fill text regions with white (1 = inpaint)
        context.setFillColor(gray: 1, alpha: 1)
        for bound in textBounds {
            // Proportional padding based on text height (covers buttons/badges around text).
            // Small text blocks (likely buttons/badges) get extra padding because UI elements
            // typically have ~100% of text height as padding around the glyphs.
            let textPixelH = bound.height * CGFloat(height)
            let textPixelW = bound.width * CGFloat(width)
            // Moderate proportional padding — enough to cover text glyphs with margin,
            // but not so large that photo content gets masked.
            // UI elements (buttons/badges) are handled separately via color-based masking.
            let padH = max(CGFloat(minPadding), textPixelH * proportionalPadding)
            let padW = max(CGFloat(minPadding), textPixelH * proportionalPadding)

            let pixelRect = CGRect(
                x: bound.origin.x * CGFloat(width) - padW,
                y: bound.origin.y * CGFloat(height) - padH,
                width: bound.width * CGFloat(width) + padW * 2,
                height: bound.height * CGFloat(height) + padH * 2
            )
            // Clamp to image bounds
            let clamped = pixelRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            if !clamped.isEmpty {
                context.fill(clamped)
            }
        }

        return context.makeImage()
    }
}
