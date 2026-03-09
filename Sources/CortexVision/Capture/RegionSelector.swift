import AppKit
import CoreGraphics

/// Callback when a region is selected or cancelled.
public typealias RegionSelectionHandler = (CGRect?) -> Void

/// Manages a fullscreen overlay for the user to draw a capture region.
public final class RegionSelector {
    private var overlayWindows: [NSWindow] = []
    private var completion: RegionSelectionHandler?

    public init() {}

    /// Shows the region selection overlay on all screens.
    /// - Parameter completion: Called with the selected rect (screen coordinates), or nil if cancelled.
    public func beginSelection(completion: @escaping RegionSelectionHandler) {
        self.completion = completion

        for screen in NSScreen.screens {
            let window = RegionOverlayWindow(
                screen: screen,
                onSelection: { [weak self] rect in
                    self?.finishSelection(rect: rect)
                },
                onCancel: { [weak self] in
                    self?.finishSelection(rect: nil)
                }
            )
            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
        }
    }

    /// Cancels the current selection.
    public func cancel() {
        finishSelection(rect: nil)
    }

    private func finishSelection(rect: CGRect?) {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        completion?(rect)
        completion = nil
    }
}

// MARK: - Overlay Window

private final class RegionOverlayWindow: NSWindow {
    convenience init(screen: NSScreen, onSelection: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false

        let overlayView = RegionOverlayView(frame: screen.frame)
        overlayView.onSelection = onSelection
        overlayView.onCancel = onCancel
        self.contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Overlay View

private final class RegionOverlayView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: NSPoint?
    private var dragEnd: NSPoint?
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragEnd = dragStart
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        dragEnd = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let start = dragStart else { return }
        isDragging = false
        let end = convert(event.locationInWindow, from: nil)

        let rect = normalizedRect(from: start, to: end)
        guard rect.width > 10 && rect.height > 10 else {
            // Too small, treat as cancelled
            onCancel?()
            return
        }

        // Convert from view coordinates to screen coordinates
        let screenRect = window?.convertToScreen(NSRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )) ?? rect

        onSelection?(screenRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim background
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        // Draw selection rectangle
        guard isDragging, let start = dragStart, let end = dragEnd else { return }

        let selectionRect = normalizedRect(from: start, to: end)

        // Clear the selection area (make it transparent)
        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)

        // Draw border around selection
        let borderPath = NSBezierPath(rect: selectionRect)
        borderPath.lineWidth = 2.0
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        borderPath.stroke()

        // Draw corner handles
        let handleSize: CGFloat = 6
        NSColor.white.setFill()
        for point in cornerPoints(of: selectionRect) {
            let handleRect = NSRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            NSBezierPath(ovalIn: handleRect).fill()
        }

        // Draw dimensions label
        let width = Int(selectionRect.width)
        let height = Int(selectionRect.height)
        let label = "\(width) × \(height)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6),
        ]
        let labelSize = label.size(withAttributes: attrs)
        let labelPoint = NSPoint(
            x: selectionRect.midX - labelSize.width / 2,
            y: selectionRect.maxY + 8
        )
        label.draw(at: labelPoint, withAttributes: attrs)
    }

    private func normalizedRect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func cornerPoints(of rect: NSRect) -> [NSPoint] {
        [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
        ]
    }
}
