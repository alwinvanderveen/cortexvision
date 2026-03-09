import SwiftUI
import CortexVision

struct ResultsPanel: View {
    let captureState: CaptureState
    let ocrResult: OCRResult?

    var body: some View {
        VStack(spacing: 0) {
            if case .analyzing = captureState {
                analyzingView
            } else if let result = ocrResult, !result.textBlocks.isEmpty {
                resultView(result)
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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

    private func resultView(_ result: OCRResult) -> some View {
        VStack(spacing: 0) {
            // Header with word count
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text("Recognized Text")
                    .font(.headline)
                Spacer()
                Text("\(result.wordCount) words")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Text content with confidence highlighting
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(result.textBlocks) { block in
                        textBlockView(block)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Copy button at bottom
            Divider()
            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.fullText, forType: .string)
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .padding(8)
            }
        }
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
