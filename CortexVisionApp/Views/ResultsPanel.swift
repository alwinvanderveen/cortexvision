import SwiftUI
import CortexVision

struct ResultsPanel: View {
    let captureState: CaptureState
    let ocrResult: OCRResult?
    let figureResult: FigureDetectionResult?
    var includedTextBlockIds: Set<UUID>?
    var excludedFigureIndices: Set<Int> = []
    var overlayTextItems: [OverlayItem] = []
    var figureOverlayIds: [Int: UUID] = [:]  // figureIndex → overlay UUID
    var onToggleFigureExclusion: ((Int) -> Void)?

    @State private var selectedFigureForZoom: DetectedFigure?

    private var hasResults: Bool {
        let hasText = ocrResult.map { !$0.textBlocks.isEmpty } ?? false
        let hasFigures = figureResult.map { !$0.figures.isEmpty } ?? false
        return hasText || hasFigures
    }

    var body: some View {
        VStack(spacing: 0) {
            if case .analyzing = captureState {
                analyzingView
            } else if hasResults {
                resultView
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $selectedFigureForZoom) { figure in
            FigureDetailView(figure: figure) {
                selectedFigureForZoom = nil
            }
            .frame(minWidth: 600, idealWidth: 900, maxWidth: .infinity,
                   minHeight: 500, idealHeight: 700, maxHeight: .infinity)
        }
    }

    // MARK: - Analyzing State

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Analyzing...")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text("Recognizing text in captured image")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No Results")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text("Perform a capture to see recognized text and figures")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result View

    private var resultView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Text section
                    if let result = ocrResult, !result.textBlocks.isEmpty {
                        textSection(result)
                    }

                    // Figures section
                    if let figures = figureResult, !figures.figures.isEmpty {
                        figureSection(figures)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Copy button at bottom
            if let result = ocrResult, !result.textBlocks.isEmpty {
                Divider()
                HStack {
                    Spacer()
                    Button {
                        let blocks = visibleTextBlocks(from: result)
                        let text = blocks.map(\.text).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .padding(8)
                }
            }
        }
    }

    // MARK: - Text Section

    /// Returns text blocks that are covered by a non-excluded text overlay.
    /// If includedTextBlockIds is nil (no overlays built yet), shows all blocks.
    private func visibleTextBlocks(from result: OCRResult) -> [TextBlock] {
        guard let included = includedTextBlockIds else { return result.textBlocks }
        return result.textBlocks.filter { included.contains($0.id) }
    }

    private func textSection(_ result: OCRResult) -> some View {
        let visible = visibleTextBlocks(from: result)
        let wordCount = visible.reduce(0) { $0 + $1.words.count }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.blue)
                Text("Recognized Text")
                    .font(.headline)
                Spacer()
                Text("\(wordCount) words")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(visible) { block in
                textBlockView(block)
            }
        }
    }

    // MARK: - Figure Section

    private func figureSection(_ result: FigureDetectionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo")
                    .foregroundStyle(.green)
                Text("Detected Figures")
                    .font(.headline)
                Spacer()
                Text("\(result.figures.count) figures")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(Array(result.figures.enumerated()), id: \.element.id) { index, figure in
                figureRow(figure, index: index)

                // Show overlay-text associated with this figure
                let figOverlayId = figureOverlayIds[index]
                let figureOverlayTexts = overlayTextItems.filter { $0.associatedFigureOverlayId == figOverlayId }
                if !figureOverlayTexts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "text.below.photo")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Text on Figure")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 8)

                        ForEach(figureOverlayTexts) { item in
                            Text(item.label ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .opacity(item.isExcluded ? 0.35 : 1.0)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private func figureRow(_ figure: DetectedFigure, index: Int) -> some View {
        let isExcluded = excludedFigureIndices.contains(index)
        return VStack(alignment: .leading, spacing: 8) {
            // Header: label, size info, toggle
            HStack {
                Text(figure.label)
                    .font(.callout)
                    .fontWeight(.medium)

                let w = Int(figure.bounds.width * 100)
                let h = Int(figure.bounds.height * 100)
                Text("\(w)% × \(h)% of image")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Exclusion toggle (unified with preview eye icon)
                Toggle("", isOn: Binding(
                    get: { !isExcluded },
                    set: { _ in onToggleFigureExclusion?(index) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(isExcluded ? "Include in export" : "Exclude from export")
            }

            // Large preview image — click to zoom
            if let cgImage = figure.extractedImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 250)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.green.opacity(0.5), lineWidth: 1)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                    .onTapGesture {
                        selectedFigureForZoom = figure
                    }
                    .help("Click to zoom")
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 80)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    )
            }
        }
        .padding(8)
        .opacity(isExcluded ? 0.5 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(!isExcluded ? Color.green.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(!isExcluded ? Color.green.opacity(0.2) : Color.gray.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func textBlockView(_ block: TextBlock) -> some View {
        if block.hasLowConfidenceWords {
            // Render word by word with highlighting for low confidence
            FlowLayout(spacing: 4) {
                ForEach(block.words) { word in
                    Text(word.text)
                        .font(.body)
                        .padding(.horizontal, word.isLowConfidence ? 2 : 0)
                        .background(word.isLowConfidence ? Color.orange.opacity(0.3) : Color.clear)
                        .cornerRadius(2)
                        .help(word.isLowConfidence ? "Low confidence: \(Int(word.confidence * 100))%" : "")
                }
            }
        } else {
            Text(block.text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

/// Simple flow layout that wraps items to the next line when they exceed available width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(subviews: subviews, proposal: proposal)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, proposal: proposal)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(subviews: Subviews, proposal: ProposedViewSize) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
