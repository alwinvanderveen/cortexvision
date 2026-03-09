import SwiftUI

struct ResultsPanel: View {
    var body: some View {
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
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
