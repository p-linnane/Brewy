import SwiftUI

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    struct CacheData {
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> CacheData {
        CacheData(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout CacheData, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        let rows = computeRows(proposal: proposal, sizes: cache.sizes)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map(\.height).max() ?? 0
            height += rowHeight
            if index < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        let rows = computeRows(proposal: proposal, sizes: cache.sizes)
        var y = bounds.minY
        var subviewIndex = 0
        for row in rows {
            let rowHeight = row.map(\.height).max() ?? 0
            var x = bounds.minX
            for size in row {
                subviews[subviewIndex].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
                subviewIndex += 1
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, sizes: [CGSize]) -> [[CGSize]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var currentWidth: CGFloat = 0
        for size in sizes {
            if currentWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(size)
            currentWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Console Output

struct ConsoleOutput: View {
    let text: String
    var maxHeight: CGFloat?
    var padding: CGFloat = 12

    var body: some View {
        let content = Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        if let maxHeight {
            ScrollView { content }.frame(maxHeight: maxHeight)
        } else {
            content
        }
    }
}

// MARK: - Action Overlay

struct ActionOverlay: View {
    let output: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Running...")
                .font(.headline)
            if !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 200)
                .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 8))
            }
        }
        .padding(24)
        .frame(maxWidth: 400)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .shadow(radius: 20, y: 10)
    }
}
