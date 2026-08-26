import SwiftUI

// MARK: - Shared UI pieces (Apple-native register)

struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0.001))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.7), value: progress)
        }
    }
}

struct DifficultyBadge: View {
    let difficulty: Difficulty
    var defense: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(difficulty.displayName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(difficulty.tint.opacity(0.14), in: .capsule)
                .foregroundStyle(difficulty.tint)
            if defense {
                Label("Committee", systemImage: "person.3.fill")
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.14), in: .capsule)
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

/// Provenance chips. Two rows, deliberately distinguished: an anchor resolves
/// to a claim in the thesis knowledge base and the compiler fails if one does
/// not, while a source is a free-form note about where a card came from.
struct SourceChips: View {
    var anchors: [String] = []
    let sources: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !anchors.isEmpty {
                chips(anchors, symbol: "link", tint: Theme.accent)
            }
            if !sources.isEmpty {
                chips(sources, symbol: "text.book.closed", tint: .secondary)
            }
        }
    }

    private func chips(_ items: [String], symbol: String, tint: Color) -> some View {
        ViewThatFits(in: .horizontal) {
            row(items, symbol: symbol, tint: tint)
            ScrollView(.horizontal, showsIndicators: false) {
                row(items, symbol: symbol, tint: tint)
            }
        }
    }

    private func row(_ items: [String], symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(tint)
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5), in: .capsule)
                    .foregroundStyle(tint)
            }
        }
    }
}

struct ActionCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

/// Card prose is authored as markdown in the vault, so **bold** and `code`
/// must render as formatting rather than as punctuation. Parsed inline only,
/// preserving whitespace, because a card's line breaks are deliberate.
func cardMarkdown(_ raw: String) -> AttributedString {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
}

extension Text {
    /// Card prose style: New York serif, comfortable size.
    func cardProse() -> some View {
        self
            .font(.title3)
            .fontDesign(.serif)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
