import CoreGraphics
import Foundation
import OnnxRuntimeBindings

// MARK: - Layout Detection Types

/// A document layout element detected by DocLayout-YOLO.
public struct LayoutDetection: Equatable, Sendable {
    /// Bounding box in normalized coordinates (0..1), top-left origin.
    public let bounds: CGRect
    /// Confidence score (0..1).
    public let confidence: Float
    /// Detected class.
    public let layoutClass: LayoutClass
}

/// Document layout classes detected by DocLayout-YOLO DocStructBench.
public enum LayoutClass: Int, CaseIterable, Sendable {
    case title = 0
    case plainText = 1
    case abandon = 2
    case figure = 3
    case figureCaption = 4
    case table = 5
    case tableCaption = 6
    case tableFootnote = 7
    case isolateFormula = 8
    case formulaCaption = 9

    /// Classes that represent visual figures (non-text elements to extract).
    public static let figureClasses: Set<LayoutClass> = [.figure, .table]

    /// Classes that represent text regions (used for text-exclusion).
    public static let textClasses: Set<LayoutClass> = [.title, .plainText, .figureCaption, .tableCaption, .tableFootnote, .formulaCaption]
}

// MARK: - DocLayoutDetector

/// Runs DocLayout-YOLO inference via ONNX Runtime to detect document layout elements.
///
/// The model accepts an RGB image (resized with aspect-ratio-preserving padding aligned to stride 32)
/// and outputs detections in XYXY format with confidence and class ID.
public final class DocLayoutDetector: @unchecked Sendable {

    /// Model input size (target for the longest side).
    public static let inputSize = 1024
    /// Stride for padding alignment.
    private static let stride = 32

    private let session: ORTSession
    private let env: ORTEnv

    // MARK: - Initialization

    /// Creates a detector by loading the ONNX model from the given path.
    public init(modelPath: String) throws {
        self.env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        self.session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
    }

    /// Creates a detector using the bundled model from the framework's resources.
    public convenience init() throws {
        guard let modelURL = Bundle.module.url(forResource: "doclayout_yolo_docstructbench_imgsz1024", withExtension: "onnx") else {
            throw DocLayoutError.modelNotFound
        }
        try self.init(modelPath: modelURL.path)
    }

    // MARK: - Detection

    /// Detects document layout elements in the given image.
    ///
    /// - Parameters:
    ///   - image: The input image (any size, will be resized with letterbox padding).
    ///   - confidenceThreshold: Minimum confidence to keep a detection (default 0.25).
    ///   - iouThreshold: IoU threshold for NMS (default 0.45).
    /// - Returns: Array of detections with bounds in normalized image coordinates (0..1), top-left origin.
    public func detect(
        in image: CGImage,
        confidenceThreshold: Float = 0.25,
        iouThreshold: Float = 0.45
    ) throws -> [LayoutDetection] {
        let imageWidth = image.width
        let imageHeight = image.height

        // Step 1: Compute letterbox dimensions (aspect-ratio preserving, stride-aligned)
        let scale = min(Float(Self.inputSize) / Float(imageWidth), Float(Self.inputSize) / Float(imageHeight))
        let scaledW = Int(round(Float(imageWidth) * scale))
        let scaledH = Int(round(Float(imageHeight) * scale))
        // Pad to stride multiple
        let padW = (Self.stride - scaledW % Self.stride) % Self.stride
        let padH = (Self.stride - scaledH % Self.stride) % Self.stride
        let padLeft = padW / 2
        let padTop = padH / 2
        let tensorW = scaledW + padW
        let tensorH = scaledH + padH

        // Step 2: Render into padded bitmap and convert to NCHW float32
        let tensorData = try renderToNCHW(image: image, scaledW: scaledW, scaledH: scaledH,
                                           padLeft: padLeft, padTop: padTop,
                                           tensorW: tensorW, tensorH: tensorH)

        // Step 3: Run inference
        let inputShape: [NSNumber] = [1, 3, NSNumber(value: tensorH), NSNumber(value: tensorW)]
        let inputTensor = try ORTValue(tensorData: tensorData, elementType: .float, shape: inputShape)
        let outputs = try session.run(
            withInputs: ["images": inputTensor],
            outputNames: Set(["output0"]),
            runOptions: nil
        )

        guard let outputTensor = outputs["output0"] else {
            throw DocLayoutError.noOutput
        }

        // Step 4: Parse XYXY output and map back to original image coordinates
        let detections = try parseOutput(
            outputTensor,
            scale: scale,
            padLeft: padLeft,
            padTop: padTop,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            confidenceThreshold: confidenceThreshold
        )

        // Step 5: Apply NMS
        return applyNMS(detections, iouThreshold: iouThreshold)
    }

    // MARK: - Preprocessing

    /// Renders the image into a NCHW float32 tensor with stride-aligned letterbox padding.
    private func renderToNCHW(
        image: CGImage,
        scaledW: Int,
        scaledH: Int,
        padLeft: Int,
        padTop: Int,
        tensorW: Int,
        tensorH: Int
    ) throws -> NSMutableData {
        let bytesPerPixel = 4
        let bytesPerRow = tensorW * bytesPerPixel
        let bitmapSize = bytesPerRow * tensorH
        let bitmapData = UnsafeMutablePointer<UInt8>.allocate(capacity: bitmapSize)
        defer { bitmapData.deallocate() }
        // Fill with gray (114 is standard YOLO letterbox fill)
        memset(bitmapData, 114, bitmapSize)

        guard let context = CGContext(
            data: bitmapData,
            width: tensorW,
            height: tensorH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw DocLayoutError.renderFailed
        }

        // CGContext has bottom-left origin; draw image at (padLeft, padBottom)
        let padBottom = tensorH - scaledH - padTop
        context.draw(image, in: CGRect(x: padLeft, y: padBottom, width: scaledW, height: scaledH))

        // Convert RGBX bitmap to NCHW float32 tensor, normalized 0..1
        let pixelCount = tensorW * tensorH
        let floatCount = 3 * pixelCount
        let tensorDataOut = NSMutableData(length: floatCount * MemoryLayout<Float32>.size)!
        let floats = tensorDataOut.mutableBytes.assumingMemoryBound(to: Float32.self)

        for i in 0..<pixelCount {
            let pixelOffset = i * bytesPerPixel
            let r = Float32(bitmapData[pixelOffset]) / 255.0
            let g = Float32(bitmapData[pixelOffset + 1]) / 255.0
            let b = Float32(bitmapData[pixelOffset + 2]) / 255.0
            floats[i] = r
            floats[pixelCount + i] = g
            floats[2 * pixelCount + i] = b
        }

        return tensorDataOut
    }

    // MARK: - Output Parsing

    /// Parses the output tensor (XYXY + confidence + class_id) into detections
    /// with normalized image coordinates.
    private func parseOutput(
        _ tensor: ORTValue,
        scale: Float,
        padLeft: Int,
        padTop: Int,
        imageWidth: Int,
        imageHeight: Int,
        confidenceThreshold: Float
    ) throws -> [LayoutDetection] {
        let data = try tensor.tensorData() as Data
        let floatCount = data.count / MemoryLayout<Float32>.size
        let stride = 6 // x1, y1, x2, y2, confidence, class_id
        let detectionCount = floatCount / stride

        guard floatCount > 0 && floatCount % stride == 0 else {
            throw DocLayoutError.unexpectedOutputShape(floatCount)
        }

        var detections: [LayoutDetection] = []

        data.withUnsafeBytes { rawBuffer in
            let floats = rawBuffer.bindMemory(to: Float32.self)

            for i in 0..<detectionCount {
                let offset = i * stride
                let confidence = floats[offset + 4]

                guard confidence >= confidenceThreshold else { continue }

                let classId = Int(floats[offset + 5])
                guard let layoutClass = LayoutClass(rawValue: classId) else { continue }

                // XYXY in letterboxed pixel coordinates → normalized original image coordinates
                let x1 = (floats[offset] - Float(padLeft)) / (scale * Float(imageWidth))
                let y1 = (floats[offset + 1] - Float(padTop)) / (scale * Float(imageHeight))
                let x2 = (floats[offset + 2] - Float(padLeft)) / (scale * Float(imageWidth))
                let y2 = (floats[offset + 3] - Float(padTop)) / (scale * Float(imageHeight))

                // Clamp to 0..1
                let clampedX1 = max(0, min(1, x1))
                let clampedY1 = max(0, min(1, y1))
                let clampedX2 = max(0, min(1, x2))
                let clampedY2 = max(0, min(1, y2))
                let w = clampedX2 - clampedX1
                let h = clampedY2 - clampedY1

                guard w > 0 && h > 0 else { continue }

                detections.append(LayoutDetection(
                    bounds: CGRect(x: Double(clampedX1), y: Double(clampedY1), width: Double(w), height: Double(h)),
                    confidence: confidence,
                    layoutClass: layoutClass
                ))
            }
        }

        return detections
    }

    // MARK: - Non-Maximum Suppression

    /// Applies class-aware NMS: only suppresses detections of the same class.
    private func applyNMS(_ detections: [LayoutDetection], iouThreshold: Float) -> [LayoutDetection] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var keep: [LayoutDetection] = []

        for detection in sorted {
            let dominated = keep.contains { kept in
                kept.layoutClass == detection.layoutClass &&
                iou(kept.bounds, detection.bounds) > iouThreshold
            }
            if !dominated {
                keep.append(detection)
            }
        }

        return keep
    }

    /// Intersection over Union of two CGRects.
    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = Float(intersection.width * intersection.height)
        let unionArea = Float(a.width * a.height + b.width * b.height) - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
}

// MARK: - Errors

public enum DocLayoutError: Error, LocalizedError {
    case modelNotFound
    case renderFailed
    case noOutput
    case unexpectedOutputShape(Int)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "DocLayout-YOLO ONNX model not found in bundle resources."
        case .renderFailed:
            return "Failed to create bitmap context for image preprocessing."
        case .noOutput:
            return "ONNX Runtime returned no output tensor."
        case .unexpectedOutputShape(let count):
            return "Unexpected output tensor size: \(count) floats (not a multiple of 6)."
        }
    }
}
