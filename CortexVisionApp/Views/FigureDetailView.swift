import SwiftUI
import CortexVision

/// Zoomable detail view for inspecting a detected figure at full resolution.
/// Supports pinch-to-zoom (trackpad), scroll-to-zoom (mouse), +/- buttons, and drag-to-pan.
struct FigureDetailView: View {
    let figure: DetectedFigure
    let onDismiss: () -> Void

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var fittedImageSize: CGSize = .zero

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 10.0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(figure.label)
                    .font(.headline)

                Spacer()

                // Zoom controls
                Button {
                    applyZoom(zoomScale * 0.8)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Zoom out")
                .disabled(zoomScale <= minZoom)

                Text(zoomLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .center)

                Button {
                    applyZoom(zoomScale * 1.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Zoom in")
                .disabled(zoomScale >= maxZoom)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        zoomScale = 1.0
                        lastZoomScale = 1.0
                        panOffset = .zero
                        lastPanOffset = .zero
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset zoom")
                .disabled(zoomScale == 1.0 && panOffset == .zero)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Zoomable image
            GeometryReader { geo in
                if let cgImage = figure.extractedImage {
                    let imageAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
                    let fitted = fitSize(imageAspect: imageAspect, into: geo.size)

                    ZStack {
                        Color(nsColor: .controlBackgroundColor)

                        Image(decorative: cgImage, scale: 1.0)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: fitted.width, height: fitted.height)
                            .scaleEffect(zoomScale)
                            .offset(panOffset)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .gesture(magnifyGesture)
                    .gesture(dragGesture)
                    .onAppear {
                        containerSize = geo.size
                        fittedImageSize = fitted
                    }
                    .onChange(of: geo.size) {
                        containerSize = geo.size
                        fittedImageSize = fitSize(imageAspect: imageAspect, into: geo.size)
                    }
                    .overlay(
                        ScrollWheelCaptureView { delta in
                            let zoomDelta = delta > 0 ? 1.05 : (1.0 / 1.05)
                            applyZoom(zoomScale * zoomDelta)
                        }
                    )
                } else {
                    Text("No image available")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            // Footer with size info
            HStack {
                if let cgImage = figure.extractedImage {
                    Text("\(cgImage.width) × \(cgImage.height) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Scroll or pinch to zoom, drag to pan")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = clampZoom(lastZoomScale * value.magnification)
                zoomScale = newScale
            }
            .onEnded { _ in
                lastZoomScale = zoomScale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                panOffset = CGSize(
                    width: lastPanOffset.width + value.translation.width,
                    height: lastPanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastPanOffset = panOffset
            }
    }

    // MARK: - Helpers

    private func applyZoom(_ newScale: CGFloat) {
        let clamped = clampZoom(newScale)
        withAnimation(.easeOut(duration: 0.15)) {
            zoomScale = clamped
            lastZoomScale = clamped
            clampPan(in: containerSize, fittedSize: fittedImageSize)
        }
    }

    private var zoomLabel: String {
        let pct = Int(zoomScale * 100)
        return "\(pct)%"
    }

    private func clampZoom(_ scale: CGFloat) -> CGFloat {
        min(maxZoom, max(minZoom, scale))
    }

    private func clampPan(in containerSize: CGSize, fittedSize: CGSize) {
        let scaledW = fittedSize.width * zoomScale
        let scaledH = fittedSize.height * zoomScale
        let maxOffsetX = max(0, (scaledW - containerSize.width) / 2)
        let maxOffsetY = max(0, (scaledH - containerSize.height) / 2)
        panOffset = CGSize(
            width: min(maxOffsetX, max(-maxOffsetX, panOffset.width)),
            height: min(maxOffsetY, max(-maxOffsetY, panOffset.height))
        )
        lastPanOffset = panOffset
    }

    private func fitSize(imageAspect: CGFloat, into container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        let containerAspect = container.width / container.height
        if imageAspect > containerAspect {
            return CGSize(width: container.width, height: container.width / imageAspect)
        } else {
            return CGSize(width: container.height * imageAspect, height: container.height)
        }
    }
}

// MARK: - Scroll Wheel Capture

/// NSView overlay that captures scroll wheel events for zoom while passing through
/// mouse clicks and drags to SwiftUI gestures via hitTest returning nil.
private struct ScrollWheelCaptureView: NSViewRepresentable {
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

/// Custom NSView that uses a local event monitor to capture scroll wheel events
/// without interfering with SwiftUI gesture recognition.
private class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    private var scrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self = self, self.window != nil else { return event }
                let locationInWindow = event.locationInWindow
                let locationInView = self.convert(locationInWindow, from: nil)
                if self.bounds.contains(locationInView) {
                    let delta = event.scrollingDeltaY
                    if abs(delta) > 0.1 {
                        self.onScroll?(delta)
                        return nil // Consume the event
                    }
                }
                return event // Pass through
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

    // Transparent to mouse hit testing so SwiftUI gestures work
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
