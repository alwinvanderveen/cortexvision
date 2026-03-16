import CoreGraphics
import Foundation

/// Testable abstraction for figure retouching/inpainting.
public protocol FigureRetouching {
    /// Removes overlay text/UI from a detected figure and returns the retouched figure crop.
    func removeText(
        from image: CGImage,
        figureBounds: CGRect,
        textBounds: [CGRect]
    ) -> CGImage?
}

/// Utilities for cropping and compositing figure crops back into the full preview image.
public enum FigurePreviewComposer {
    /// Converts Vision-style normalized figure bounds (bottom-left origin) to top-left pixel coordinates.
    public static func pixelRect(for figureBounds: CGRect, in image: CGImage) -> CGRect {
        CGRect(
            x: figureBounds.origin.x * CGFloat(image.width),
            y: (1.0 - figureBounds.origin.y - figureBounds.height) * CGFloat(image.height),
            width: figureBounds.width * CGFloat(image.width),
            height: figureBounds.height * CGFloat(image.height)
        ).integral
    }

    /// Crops a figure region from the original full-size image.
    public static func cropFigure(from image: CGImage, figureBounds: CGRect) -> CGImage? {
        let rect = pixelRect(for: figureBounds, in: image)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isEmpty else { return nil }
        return image.cropping(to: rect)
    }

    /// Draws a replacement figure crop back into the original full-size image.
    public static func compositeFigure(
        _ figureImage: CGImage,
        into image: CGImage,
        figureBounds: CGRect
    ) -> CGImage? {
        let rect = pixelRect(for: figureBounds, in: image)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isEmpty else { return nil }

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let drawRect = CGRect(
            x: rect.origin.x,
            y: CGFloat(image.height) - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        context.draw(figureImage, in: drawRect)
        return context.makeImage()
    }
}
