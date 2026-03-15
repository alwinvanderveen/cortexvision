import CoreGraphics
import Foundation
import OnnxRuntimeBindings

/// Errors specific to LaMa inpainting.
public enum LaMaError: Error, Sendable {
    case modelNotFound
    case invalidInput
    case inferenceFailed(String)
    case outputConversionFailed
}

/// LaMa (Large Mask Inpainting) model wrapper using ONNX Runtime.
///
/// Input: 512×512 RGB image + 512×512 binary mask.
/// Output: 512×512 inpainted RGB image.
///
/// Image input is normalized to [0, 1] float32.
/// Mask input is [0, 1] float32 (1 = region to inpaint).
/// Output is [0, 255] float32, clipped and converted to CGImage.
public final class LaMaInpainter: @unchecked Sendable {

    public static let inputSize = 512

    private let session: ORTSession
    private let env: ORTEnv

    /// Creates an inpainter by loading the ONNX model from the given path.
    public init(modelPath: String) throws {
        self.env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        self.session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
    }

    /// Creates an inpainter using the bundled model from the framework's resources.
    public convenience init() throws {
        guard let modelURL = Bundle.module.url(forResource: "lama_fp32", withExtension: "onnx") else {
            throw LaMaError.modelNotFound
        }
        try self.init(modelPath: modelURL.path)
    }

    /// Inpaints the masked region of a 512×512 image.
    ///
    /// - Parameters:
    ///   - image: Source RGB image (will be resized to 512×512 if needed).
    ///   - mask: Grayscale mask image where white (>128) = inpaint, black = keep.
    /// - Returns: Inpainted RGB image at 512×512.
    public func inpaint(image: CGImage, mask: CGImage) throws -> CGImage {
        let size = Self.inputSize

        // Render image and mask to 512×512 RGBA bitmaps
        let imageRGBA = try renderToRGBA(image, width: size, height: size)
        let maskGray = try renderToGrayscale(mask, width: size, height: size)

        // Convert to NCHW float32 tensors
        let imageTensor = try createImageTensor(from: imageRGBA, width: size, height: size)
        let maskTensor = try createMaskTensor(from: maskGray, width: size, height: size)

        // Run inference
        let outputs = try session.run(
            withInputs: ["image": imageTensor, "mask": maskTensor],
            outputNames: Set(["output"]),
            runOptions: nil
        )

        guard let outputTensor = outputs["output"] else {
            throw LaMaError.inferenceFailed("No output tensor")
        }

        // Convert output tensor to CGImage
        return try outputToCGImage(outputTensor, width: size, height: size)
    }

    // MARK: - Rendering Helpers

    private func renderToRGBA(_ image: CGImage, width: Int, height: Int) throws -> UnsafeMutablePointer<UInt8> {
        let bytesPerRow = width * 4
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        guard let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            data.deallocate()
            throw LaMaError.invalidInput
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private func renderToGrayscale(_ image: CGImage, width: Int, height: Int) throws -> UnsafeMutablePointer<UInt8> {
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        guard let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            data.deallocate()
            throw LaMaError.invalidInput
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    // MARK: - Tensor Creation

    private func createImageTensor(from rgba: UnsafeMutablePointer<UInt8>, width: Int, height: Int) throws -> ORTValue {
        defer { rgba.deallocate() }
        let pixelCount = width * height
        let tensorData = NSMutableData(length: 3 * pixelCount * MemoryLayout<Float32>.size)!
        let floats = tensorData.mutableBytes.bindMemory(to: Float32.self, capacity: 3 * pixelCount)

        // RGBA → NCHW RGB, normalized to [0, 1]
        // CGContext bitmap row 0 = top of image = same as NCHW. No flip needed.
        for i in 0..<pixelCount {
            let offset = i * 4
            floats[i] = Float32(rgba[offset]) / 255.0                    // R
            floats[pixelCount + i] = Float32(rgba[offset + 1]) / 255.0   // G
            floats[2 * pixelCount + i] = Float32(rgba[offset + 2]) / 255.0 // B
        }

        let shape: [NSNumber] = [1, 3, NSNumber(value: height), NSNumber(value: width)]
        return try ORTValue(tensorData: tensorData, elementType: .float, shape: shape)
    }

    private func createMaskTensor(from gray: UnsafeMutablePointer<UInt8>, width: Int, height: Int) throws -> ORTValue {
        defer { gray.deallocate() }
        let pixelCount = width * height
        let tensorData = NSMutableData(length: pixelCount * MemoryLayout<Float32>.size)!
        let floats = tensorData.mutableBytes.bindMemory(to: Float32.self, capacity: pixelCount)

        // Grayscale → NCHW single channel, binarized: >128 → 1.0, else → 0.0
        // CGContext bitmap row 0 = top = same as NCHW. No flip needed.
        for i in 0..<pixelCount {
            floats[i] = gray[i] > 128 ? Float32(1.0) : Float32(0.0)
        }

        let shape: [NSNumber] = [1, 1, NSNumber(value: height), NSNumber(value: width)]
        return try ORTValue(tensorData: tensorData, elementType: .float, shape: shape)
    }

    // MARK: - Output Conversion

    private func outputToCGImage(_ tensor: ORTValue, width: Int, height: Int) throws -> CGImage {
        let data = try tensor.tensorData() as Data
        let pixelCount = width * height
        let expectedSize = 3 * pixelCount * MemoryLayout<Float32>.size
        guard data.count >= expectedSize else {
            throw LaMaError.outputConversionFailed
        }

        // NCHW float32 [0, 255] → RGBA uint8
        // Both NCHW and CGContext bitmap use row 0 = top. No flip needed.
        let rgbaData = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount * 4)

        data.withUnsafeBytes { rawBuffer in
            let floats = rawBuffer.bindMemory(to: Float32.self)
            for i in 0..<pixelCount {
                let r = max(0, min(255, floats[i]))
                let g = max(0, min(255, floats[pixelCount + i]))
                let b = max(0, min(255, floats[2 * pixelCount + i]))
                rgbaData[i * 4] = UInt8(r)
                rgbaData[i * 4 + 1] = UInt8(g)
                rgbaData[i * 4 + 2] = UInt8(b)
                rgbaData[i * 4 + 3] = 255
            }
        }

        guard let context = CGContext(
            data: rgbaData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            rgbaData.deallocate()
            throw LaMaError.outputConversionFailed
        }

        rgbaData.deallocate()
        return cgImage
    }
}
