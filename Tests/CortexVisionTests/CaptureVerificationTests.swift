import Testing
import CoreGraphics
import CoreImage
import Vision
import AppKit
@testable import CortexVision

// MARK: - Test Reference Window

/// Creates an NSWindow with known, verifiable content:
/// - QR code encoding a unique identifier in the center
/// - Colored corners: red (top-left), green (top-right), blue (bottom-left), yellow (bottom-right)
/// - Known text label below the QR code
@MainActor
private final class ReferenceWindow {
    let window: NSWindow
    let identifier: String
    let expectedText = "CortexVision Verify"

    init(on screen: NSScreen, size: CGSize = CGSize(width: 400, height: 400), borderless: Bool = false) {
        self.identifier = UUID().uuidString

        // Position window in center of the given screen
        let screenFrame = screen.frame
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )

        window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: borderless ? [.borderless] : [.titled, .closable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "CortexVision Test Reference \(identifier.prefix(8))"
        window.backgroundColor = .white
        window.level = .floating // Keep above other windows for region capture

        let contentView = ReferenceContentView(
            frame: NSRect(origin: .zero, size: size),
            qrData: identifier,
            labelText: expectedText
        )
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Force layout and display so content is rendered before capture
        contentView.display()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window.orderOut(nil)
    }
}

/// Custom NSView that draws the reference pattern.
private final class ReferenceContentView: NSView {
    let qrData: String
    let labelText: String

    init(frame: NSRect, qrData: String, labelText: String) {
        self.qrData = qrData
        self.labelText = labelText
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        // White background
        NSColor.white.setFill()
        bounds.fill()

        let cornerSize: CGFloat = 40

        // Top-left: RED
        NSColor.red.setFill()
        NSRect(x: 0, y: bounds.height - cornerSize, width: cornerSize, height: cornerSize).fill()

        // Top-right: GREEN
        NSColor.green.setFill()
        NSRect(x: bounds.width - cornerSize, y: bounds.height - cornerSize, width: cornerSize, height: cornerSize).fill()

        // Bottom-left: BLUE
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: cornerSize, height: cornerSize).fill()

        // Bottom-right: YELLOW
        NSColor.yellow.setFill()
        NSRect(x: bounds.width - cornerSize, y: 0, width: cornerSize, height: cornerSize).fill()

        // QR code in center
        if let qrImage = generateQRCode(from: qrData) {
            let qrSize: CGFloat = 160
            let qrRect = NSRect(
                x: (bounds.width - qrSize) / 2,
                y: (bounds.height - qrSize) / 2 + 20,
                width: qrSize,
                height: qrSize
            )
            let nsImage = NSImage(cgImage: qrImage, size: NSSize(width: qrSize, height: qrSize))
            nsImage.draw(in: qrRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        // Text label below QR
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let textSize = labelText.size(withAttributes: attrs)
        let textPoint = NSPoint(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - 160) / 2 - 30
        )
        labelText.draw(at: textPoint, withAttributes: attrs)
    }

    private func generateQRCode(from string: String) -> CGImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        // Scale up for clarity
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: scale)
        let context = CIContext()
        return context.createCGImage(scaledImage, from: scaledImage.extent)
    }
}

// MARK: - Pixel Sampling Helper

/// Sample the color of a pixel in a CGImage at the given (x, y) coordinate.
/// Returns (r, g, b) as values 0-255.
private func samplePixel(in image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int)? {
    guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }

    guard let dataProvider = image.dataProvider,
          let data = dataProvider.data,
          let ptr = CFDataGetBytePtr(data) else { return nil }

    let bytesPerPixel = image.bitsPerPixel / 8
    let bytesPerRow = image.bytesPerRow
    let offset = y * bytesPerRow + x * bytesPerPixel

    // Handle both RGBA and BGRA formats
    if image.bitmapInfo.contains(.byteOrder32Little) {
        // BGRA
        return (r: Int(ptr[offset + 2]), g: Int(ptr[offset + 1]), b: Int(ptr[offset]))
    } else {
        // RGBA
        return (r: Int(ptr[offset]), g: Int(ptr[offset + 1]), b: Int(ptr[offset + 2]))
    }
}

/// Check if a color is approximately the expected color (tolerance for rendering differences).
private func colorMatches(_ pixel: (r: Int, g: Int, b: Int), expected: (r: Int, g: Int, b: Int), tolerance: Int = 40) -> Bool {
    abs(pixel.r - expected.r) <= tolerance &&
    abs(pixel.g - expected.g) <= tolerance &&
    abs(pixel.b - expected.b) <= tolerance
}

// MARK: - Verification Tests

@Suite("Capture — Verification Tests", .serialized)
struct CaptureVerificationTests {
    @Test("Window capture contains correct QR code data",
          .tags(.capture, .core),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func windowCaptureQRVerification() async throws {
        // Functional: A captured window contains all its visual content, verifiable by QR decode
        // Technical: Create reference window → capture via captureWindow → decode QR → match identifier
        // Input: Reference window with unique QR code
        // Expected: Decoded QR data matches the generated identifier
        let screen = NSScreen.main!
        let ref = ReferenceWindow(on: screen)

        // Allow window to fully render
        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let windows = try await provider.availableWindows()
        let titlePrefix = "CortexVision Test Reference \(ref.identifier.prefix(8))"
        let testWindow = windows.first(where: { $0.title.hasPrefix(titlePrefix) })
        #expect(testWindow != nil, "Reference window should appear in window list")

        let result = try await provider.captureWindow(id: testWindow!.id)
        ref.close()

        // Decode QR from captured image
        let decoded = try decodeQR(from: result.image)
        #expect(decoded == ref.identifier, "QR data should match: expected \(ref.identifier), got \(decoded ?? "nil")")
    }

    @Test("Region capture contains correct QR code data",
          .tags(.capture, .core),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func regionCaptureQRVerification() async throws {
        // Functional: A captured screen region contains the exact content at that position
        // Technical: Create reference window → capture its screen region → decode QR → match
        // Input: Reference window at known position, capture that region
        // Expected: Decoded QR data matches the generated identifier
        let screen = NSScreen.main!
        let ref = ReferenceWindow(on: screen)

        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        // Use the content frame (window frame) for region capture
        let windowFrame = ref.window.frame
        let result = try await provider.captureRegion(windowFrame)
        ref.close()

        let decoded = try decodeQR(from: result.image)
        #expect(decoded == ref.identifier, "QR data should match: expected \(ref.identifier), got \(decoded ?? "nil")")
    }

    @Test("Region capture has colored corners in correct positions",
          .tags(.capture, .core),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func regionCaptureCornerColors() async throws {
        // Functional: Captured image is not cropped or shifted — all four corners are present
        // Technical: Capture content rect of reference window, sample pixels near corners, verify colors
        // Input: Reference window with red/green/blue/yellow corners
        // Expected: Top-left≈red, top-right≈green, bottom-left≈blue, bottom-right≈yellow
        let screen = NSScreen.main!
        let ref = ReferenceWindow(on: screen)

        try await Task.sleep(for: .milliseconds(500))

        // Capture only the content area (excludes titlebar) in screen coordinates
        let windowFrame = ref.window.frame
        let contentRect = ref.window.contentLayoutRect
        let contentScreenRect = CGRect(
            x: windowFrame.origin.x + contentRect.origin.x,
            y: windowFrame.origin.y + contentRect.origin.y,
            width: contentRect.width,
            height: contentRect.height
        )

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(contentScreenRect)
        ref.close()

        let img = result.image

        // The image may be larger than the actual content due to captureRegion hardcoding 2x.
        // Use the screen's backing scale factor to find the actual content pixel dimensions.
        let scale = screen.backingScaleFactor
        let contentW = Int(contentRect.width * scale)
        let contentH = Int(contentRect.height * scale)

        // The colored squares are 40pt each. Sample 10pt (in content pixels) inward from each corner.
        let inset = Int(10 * scale)

        // Top-left should be RED (in CG coords, top-left is y=0)
        let topLeft = samplePixel(in: img, x: inset, y: inset)
        #expect(topLeft != nil)
        #expect(colorMatches(topLeft!, expected: (r: 255, g: 0, b: 0), tolerance: 80),
                "Top-left corner should be red, got \(topLeft!)")

        // Top-right should be GREEN
        let topRight = samplePixel(in: img, x: contentW - inset - 1, y: inset)
        #expect(topRight != nil)
        #expect(colorMatches(topRight!, expected: (r: 0, g: 255, b: 0), tolerance: 80),
                "Top-right corner should be green, got \(topRight!)")

        // Bottom-left should be BLUE
        let bottomLeft = samplePixel(in: img, x: inset, y: contentH - inset - 1)
        #expect(bottomLeft != nil)
        #expect(colorMatches(bottomLeft!, expected: (r: 0, g: 0, b: 255), tolerance: 80),
                "Bottom-left corner should be blue, got \(bottomLeft!)")

        // Bottom-right should be YELLOW
        let bottomRight = samplePixel(in: img, x: contentW - inset - 1, y: contentH - inset - 1)
        #expect(bottomRight != nil)
        #expect(colorMatches(bottomRight!, expected: (r: 255, g: 255, b: 0), tolerance: 80),
                "Bottom-right corner should be yellow, got \(bottomRight!)")
    }

    @Test("Region capture contains recognizable text via OCR",
          .tags(.capture, .ocr),
          .enabled(if: isScreenRecordingAvailable))
    @MainActor
    func regionCaptureOCRVerification() async throws {
        // Functional: Captured region text is readable by OCR — full content integrity
        // Technical: Create reference window with known text → capture region → OCR → verify text
        // Input: Reference window with "CortexVision Verify" label
        // Expected: OCR results contain "CortexVision" and "Verify"
        let screen = NSScreen.main!
        let ref = ReferenceWindow(on: screen)

        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: result.image, options: [:])
        try handler.perform([request])

        let recognizedText = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")

        #expect(recognizedText.contains("CortexVision"), "OCR should find 'CortexVision' in: \(recognizedText)")
        #expect(recognizedText.contains("Verify"), "OCR should find 'Verify' in: \(recognizedText)")
    }

    @Test("Secondary screen capture contains correct QR code",
          .tags(.capture, .core),
          .enabled(if: isScreenRecordingAvailable && NSScreen.screens.count > 1))
    @MainActor
    func secondaryScreenCaptureQR() async throws {
        // Functional: Capture works correctly on a secondary display
        // Technical: Place reference window on secondary screen → region capture → decode QR
        // Input: Reference window on second screen
        // Expected: Decoded QR data matches identifier
        let secondaryScreen = NSScreen.screens.first(where: { $0 != NSScreen.main })!
        let ref = ReferenceWindow(on: secondaryScreen)

        try await Task.sleep(for: .milliseconds(500))

        let provider = ScreenCaptureKitProvider()
        let result = try await provider.captureRegion(ref.window.frame)
        ref.close()

        let decoded = try decodeQR(from: result.image)
        #expect(decoded == ref.identifier, "Secondary screen QR should match")
    }

    // MARK: - Helpers

    private func decodeQR(from image: CGImage) throws -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return request.results?
            .compactMap { $0.payloadStringValue }
            .first
    }
}
