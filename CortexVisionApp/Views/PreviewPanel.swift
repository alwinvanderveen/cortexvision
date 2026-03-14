import SwiftUI
import CortexVision

struct PreviewPanel: View {
    let capturedImage: CGImage?
    let captureState: CaptureState
    let overlays: [AnalysisOverlay]
    let interactiveItems: [OverlayItem]
    let selectedOverlayId: UUID?
    let imageSize: CGSize
    var onSelectOverlay: ((UUID?) -> Void)?
    var onMoveOverlay: ((UUID, CGFloat, CGFloat) -> Void)?
    var onResizeOverlay: ((UUID, CGRect) -> Void)?
    var onDeleteOverlay: (() -> Void)?
    var onDrawNewOverlay: ((CGRect) -> Void)?
    var onToggleExclusion: ((UUID) -> Void)?

    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 8.0

    var body: some View {
        Group {
            if let image = capturedImage {
                GeometryReader { geo in
                    let scaleFactor: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
                    let logicalWidth = CGFloat(image.width) / scaleFactor
                    let logicalHeight = CGFloat(image.height) / scaleFactor
                    let imageAspect = logicalWidth / logicalHeight
                    let panelSize = CGSize(
                        width: geo.size.width - 16,
                        height: geo.size.height - 40 // room for zoom bar
                    )
                    let fittedSize = fitSize(imageAspect: imageAspect, into: panelSize)

                    VStack(spacing: 0) {
                        // Zoom controls bar
                        zoomBar

                        // Zoomable, pannable preview with overlays
                        ZStack {
                            Color(nsColor: .controlBackgroundColor)

                            ZStack {
                                Image(decorative: image, scale: scaleFactor)
                                    .resizable()
                                    .frame(width: fittedSize.width, height: fittedSize.height)

                                if !interactiveItems.isEmpty {
                                    InteractiveOverlayView(
                                        items: interactiveItems,
                                        imageSize: imageSize,
                                        selectedId: selectedOverlayId,
                                        onSelect: onSelectOverlay,
                                        onMove: onMoveOverlay,
                                        onResize: onResizeOverlay,
                                        onDelete: onDeleteOverlay,
                                        onDrawNew: onDrawNewOverlay,
                                        onToggleExclusion: onToggleExclusion
                                    )
                                    .frame(width: fittedSize.width, height: fittedSize.height)
                                } else {
                                    AnalysisOverlayView(
                                        overlays: overlays,
                                        imageSize: imageSize
                                    )
                                    .frame(width: fittedSize.width, height: fittedSize.height)
                                }
                            }
                            .scaleEffect(zoomScale)
                            .offset(panOffset)
                        }
                        .clipped()
                        .overlay(
                            MiddleMousePanView { delta in
                                panOffset = CGSize(
                                    width: lastPanOffset.width + delta.width,
                                    height: lastPanOffset.height + delta.height
                                )
                            } onEnd: {
                                lastPanOffset = panOffset
                            }
                        )
                        .overlay(
                            ScrollWheelZoomView { delta in
                                let factor = delta > 0 ? 1.05 : (1.0 / 1.05)
                                let newScale = min(maxZoom, max(minZoom, zoomScale * factor))
                                withAnimation(.easeOut(duration: 0.1)) {
                                    zoomScale = newScale
                                }
                            }
                        )
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Zoom Controls

    private var zoomBar: some View {
        HStack(spacing: 8) {
            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    zoomScale = max(minZoom, zoomScale * 0.8)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(zoomScale <= minZoom)

            Text("\(Int(zoomScale * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .center)

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    zoomScale = min(maxZoom, zoomScale * 1.25)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(zoomScale >= maxZoom)

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    zoomScale = 1.0
                    panOffset = .zero
                    lastPanOffset = .zero
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(zoomScale == 1.0 && panOffset == .zero)
            .help("Reset zoom")

            Spacer()
        }
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private func fitSize(imageAspect: CGFloat, into container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        let containerAspect = container.width / container.height
        if imageAspect > containerAspect {
            return CGSize(width: container.width, height: container.width / imageAspect)
        } else {
            return CGSize(width: container.height * imageAspect, height: container.height)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No Capture")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text("Select a capture mode from the toolbar to get started")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Scroll Wheel Zoom

private struct ScrollWheelZoomView: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    private var scrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.window != nil else { return event }
                let locationInWindow = event.locationInWindow
                let locationInView = self.convert(locationInWindow, from: nil)
                if self.bounds.contains(locationInView) {
                    let delta = event.scrollingDeltaY
                    if abs(delta) > 0.1 {
                        self.onScroll?(delta)
                        return nil
                    }
                }
                return event
            }
        }
    }

    override func removeFromSuperview() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        super.removeFromSuperview()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil, let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Middle Mouse Button Pan

private struct MiddleMousePanView: NSViewRepresentable {
    let onDrag: (CGSize) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> MiddleMouseNSView {
        let view = MiddleMouseNSView()
        view.onDrag = onDrag
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ nsView: MiddleMouseNSView, context: Context) {
        nsView.onDrag = onDrag
        nsView.onEnd = onEnd
    }
}

private class MiddleMouseNSView: NSView {
    var onDrag: ((CGSize) -> Void)?
    var onEnd: (() -> Void)?
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var dragOrigin: NSPoint?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, dragMonitor == nil else { return }

        // Monitor middle mouse button down to start pan
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseDragged, .otherMouseUp]) { [weak self] event in
            guard let self, self.window != nil else { return event }
            // Only handle middle button (buttonNumber == 2)
            guard event.buttonNumber == 2 else { return event }

            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)
            guard self.bounds.contains(locationInView) || self.dragOrigin != nil else { return event }

            switch event.type {
            case .otherMouseDown:
                self.dragOrigin = locationInWindow
                return nil // consume

            case .otherMouseDragged:
                guard let origin = self.dragOrigin else { return event }
                let delta = CGSize(
                    width: locationInWindow.x - origin.x,
                    height: -(locationInWindow.y - origin.y) // flip Y for SwiftUI
                )
                self.onDrag?(delta)
                return nil

            case .otherMouseUp:
                if self.dragOrigin != nil {
                    self.dragOrigin = nil
                    self.onEnd?()
                    return nil
                }
                return event

            default:
                return event
            }
        }
    }

    override func removeFromSuperview() {
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
        super.removeFromSuperview()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil, let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
