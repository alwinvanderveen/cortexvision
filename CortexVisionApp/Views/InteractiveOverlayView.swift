import SwiftUI
import CortexVision

/// Interactive overlay view that renders overlay items on the preview with support for
/// selection, dragging, resizing via handles, deletion, and exclusion toggling.
struct InteractiveOverlayView: View {
    let items: [OverlayItem]
    let imageSize: CGSize
    let selectedId: UUID?
    var onSelect: ((UUID?) -> Void)?
    var onMove: ((UUID, CGFloat, CGFloat) -> Void)?
    var onResize: ((UUID, CGRect) -> Void)?
    var onDelete: (() -> Void)?
    var onDrawNew: ((CGRect) -> Void)?
    var onToggleExclusion: ((UUID) -> Void)?

    @State private var drawStart: CGPoint?
    @State private var drawCurrent: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let scale = fitScale(imageSize: imageSize, viewSize: geometry.size)
            let offset = fitOffset(imageSize: imageSize, viewSize: geometry.size, scale: scale)

            ZStack {
                // Tap on empty area to deselect. Option+drag on empty area = draw new overlay.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect?(nil) }
                    .gesture(drawGesture(scale: scale, offset: offset))
                    .allowsHitTesting(true)

                // Draw-in-progress rectangle
                if let start = drawStart, let current = drawCurrent {
                    let drawRect = normalizedRect(from: start, to: current)
                    Rectangle()
                        .strokeBorder(Color.green.opacity(0.8), lineWidth: 2)
                        .background(Color.green.opacity(0.15))
                        .frame(
                            width: drawRect.width * imageSize.width * scale,
                            height: drawRect.height * imageSize.height * scale
                        )
                        .position(
                            x: (drawRect.midX * imageSize.width) * scale + offset.x,
                            y: (drawRect.midY * imageSize.height) * scale + offset.y
                        )
                }

                // Overlay items
                ForEach(items) { item in
                    let viewRect = viewRect(for: item, scale: scale, offset: offset)
                    let isSelected = item.id == selectedId

                    InteractiveOverlayBox(
                        item: item,
                        viewRect: viewRect,
                        isSelected: isSelected,
                        imageSize: imageSize,
                        scale: scale,
                        onSelect: { onSelect?(item.id) },
                        onMove: { dx, dy in
                            let ndx = dx / (imageSize.width * scale)
                            let ndy = dy / (imageSize.height * scale)
                            onMove?(item.id, ndx, ndy)
                        },
                        onResize: { newBounds in
                            onResize?(item.id, newBounds)
                        },
                        onToggleExclusion: { onToggleExclusion?(item.id) }
                    )
                }
            }
            .onKeyPress(.delete) {
                if selectedId != nil {
                    onDelete?()
                    return .handled
                }
                return .ignored
            }
        }
    }

    // MARK: - Draw Gesture

    private func drawGesture(scale: CGFloat, offset: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                drawStart = viewToNormalized(value.startLocation, scale: scale, offset: offset)
                drawCurrent = viewToNormalized(value.location, scale: scale, offset: offset)
            }
            .onEnded { value in
                if let start = drawStart, let end = viewToNormalized(value.location, scale: scale, offset: offset) {
                    let rect = normalizedRect(from: start, to: end)
                    if rect.width > 0.02 && rect.height > 0.02 {
                        onDrawNew?(rect)
                    }
                }
                drawStart = nil
                drawCurrent = nil
            }
    }

    private func viewToNormalized(_ point: CGPoint, scale: CGFloat, offset: CGPoint) -> CGPoint? {
        guard imageSize.width > 0, imageSize.height > 0, scale > 0 else { return nil }
        let nx = (point.x - offset.x) / (imageSize.width * scale)
        let ny = (point.y - offset.y) / (imageSize.height * scale)
        return CGPoint(x: max(0, min(1, nx)), y: max(0, min(1, ny)))
    }

    private func normalizedRect(from a: CGPoint?, to b: CGPoint?) -> CGRect {
        guard let a, let b else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    // MARK: - Coordinate Helpers

    private func viewRect(for item: OverlayItem, scale: CGFloat, offset: CGPoint) -> CGRect {
        let pixelRect = item.pixelRect(for: imageSize)
        return CGRect(
            x: pixelRect.origin.x * scale + offset.x,
            y: pixelRect.origin.y * scale + offset.y,
            width: pixelRect.width * scale,
            height: pixelRect.height * scale
        )
    }

    private func fitScale(imageSize: CGSize, viewSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    }

    private func fitOffset(imageSize: CGSize, viewSize: CGSize, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (viewSize.width - imageSize.width * scale) / 2,
            y: (viewSize.height - imageSize.height * scale) / 2
        )
    }
}

// MARK: - Interactive Overlay Box

private struct InteractiveOverlayBox: View {
    let item: OverlayItem
    let viewRect: CGRect
    let isSelected: Bool
    let imageSize: CGSize
    let scale: CGFloat
    var onSelect: () -> Void
    var onMove: (CGFloat, CGFloat) -> Void
    var onResize: (CGRect) -> Void
    var onToggleExclusion: () -> Void

    @State private var dragOffset: CGSize = .zero

    private var baseColor: Color {
        switch item.kind {
        case .text:
            // Overlay-text on figures gets orange, page-text gets blue
            if let cls = item.textOverlayClassification, cls == .overlay || cls == .edgeOverlay {
                return .orange
            }
            return .blue
        case .figure: return .green
        }
    }

    private var color: Color {
        item.isExcluded ? baseColor.opacity(0.3) : baseColor
    }

    private var borderStyle: some ShapeStyle {
        item.isExcluded ? AnyShapeStyle(color.opacity(0.4)) : AnyShapeStyle(isSelected ? color : color.opacity(0.6))
    }

    var body: some View {
        ZStack {
            // Main bounding box
            if item.isExcluded {
                // Excluded: dashed border, dimmed
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(baseColor.opacity(0.3))
                    .background(baseColor.opacity(0.03))
            } else {
                // Normal: solid border
                Rectangle()
                    .strokeBorder(
                        isSelected ? baseColor : baseColor.opacity(0.6),
                        lineWidth: isSelected ? 3 : 2
                    )
                    .background(isSelected ? baseColor.opacity(0.15) : baseColor.opacity(0.05))
            }

            // Label + exclusion indicator
            VStack {
                HStack(spacing: 4) {
                    if let label = item.label {
                        Text(item.isExcluded ? "\(label)" : label)
                            .font(.system(size: 9, weight: .medium))
                            .strikethrough(item.isExcluded)
                            .foregroundStyle(.white.opacity(item.isExcluded ? 0.5 : 1.0))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(baseColor.opacity(item.isExcluded ? 0.3 : 0.8))
                            .cornerRadius(2)
                    }
                    Spacer()

                    // Eye icon (visible when selected)
                    if isSelected {
                        Button {
                            onToggleExclusion()
                        } label: {
                            Image(systemName: item.isExcluded ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(baseColor.opacity(0.8))
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                        .help(item.isExcluded ? "Include in export" : "Exclude from export")
                    }
                }
                Spacer()
            }
            .padding(2)

            // Resize handles (only when selected and not excluded)
            if isSelected && !item.isExcluded {
                ResizeHandles(
                    bounds: item.bounds,
                    viewRect: viewRect,
                    imageSize: imageSize,
                    scale: scale,
                    onResize: onResize
                )
            }
        }
        .frame(width: viewRect.width, height: viewRect.height)
        .offset(isSelected && !item.isExcluded ? dragOffset : .zero)
        .position(x: viewRect.midX, y: viewRect.midY)
        .onTapGesture { onSelect() }
        .gesture(isSelected && !item.isExcluded ? dragGesture : nil)
        .contextMenu {
            Button {
                onToggleExclusion()
            } label: {
                Label(
                    item.isExcluded ? "Include in Export" : "Exclude from Export",
                    systemImage: item.isExcluded ? "eye" : "eye.slash"
                )
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in dragOffset = value.translation }
            .onEnded { value in
                onMove(value.translation.width, value.translation.height)
                dragOffset = .zero
            }
    }
}

// MARK: - Resize Handles

private struct ResizeHandles: View {
    let bounds: CGRect
    let viewRect: CGRect
    let imageSize: CGSize
    let scale: CGFloat
    var onResize: (CGRect) -> Void

    private let handleSize: CGFloat = 10

    var body: some View {
        ZStack {
            handleAt(.topLeading)
            handleAt(.topTrailing)
            handleAt(.bottomLeading)
            handleAt(.bottomTrailing)
            handleAt(.top)
            handleAt(.bottom)
            handleAt(.leading)
            handleAt(.trailing)
        }
    }

    @ViewBuilder
    private func handleAt(_ position: HandlePosition) -> some View {
        let pos = handleViewPosition(position)
        Circle()
            .fill(Color.white)
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: handleSize, height: handleSize)
            .position(x: pos.x - viewRect.minX, y: pos.y - viewRect.minY)
            .gesture(
                DragGesture()
                    .onEnded { value in
                        let dx = value.translation.width / (imageSize.width * scale)
                        let dy = value.translation.height / (imageSize.height * scale)
                        onResize(applyResize(position: position, dx: dx, dy: dy))
                    }
            )
    }

    private func handleViewPosition(_ position: HandlePosition) -> CGPoint {
        switch position {
        case .topLeading:     return CGPoint(x: viewRect.minX, y: viewRect.minY)
        case .topTrailing:    return CGPoint(x: viewRect.maxX, y: viewRect.minY)
        case .bottomLeading:  return CGPoint(x: viewRect.minX, y: viewRect.maxY)
        case .bottomTrailing: return CGPoint(x: viewRect.maxX, y: viewRect.maxY)
        case .top:            return CGPoint(x: viewRect.midX, y: viewRect.minY)
        case .bottom:         return CGPoint(x: viewRect.midX, y: viewRect.maxY)
        case .leading:        return CGPoint(x: viewRect.minX, y: viewRect.midY)
        case .trailing:       return CGPoint(x: viewRect.maxX, y: viewRect.midY)
        }
    }

    private func applyResize(position: HandlePosition, dx: CGFloat, dy: CGFloat) -> CGRect {
        var b = bounds
        switch position {
        case .topLeading:     b.origin.x += dx; b.size.width -= dx; b.origin.y += dy; b.size.height -= dy
        case .topTrailing:    b.size.width += dx; b.origin.y += dy; b.size.height -= dy
        case .bottomLeading:  b.origin.x += dx; b.size.width -= dx; b.size.height += dy
        case .bottomTrailing: b.size.width += dx; b.size.height += dy
        case .top:            b.origin.y += dy; b.size.height -= dy
        case .bottom:         b.size.height += dy
        case .leading:        b.origin.x += dx; b.size.width -= dx
        case .trailing:       b.size.width += dx
        }
        return b
    }

    private enum HandlePosition {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        case top, bottom, leading, trailing
    }
}
