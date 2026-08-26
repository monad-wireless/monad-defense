import SwiftUI

// MARK: - The card graph
//
// Terms do not live alone. Having understood CSI you want OFDM next, and from
// OFDM the channel frequency response, and from there multipath. The bank
// carries those links explicitly (`see_also` in the deck note, made symmetric
// at compile time), and this is where a reader walks them.
//
// Following a link is deliberately NOT a review. It opens the card to read,
// it does not grade it and it does not move it in the FSRS queue — otherwise
// curiosity would corrupt the schedule, and a reader would learn not to be
// curious.

struct RelatedCardsRow: View {
    @Environment(StudyStore.self) private var store
    let card: Card
    @Binding var reading: Card?

    private var neighbours: [Card] { store.related(to: card) }

    var body: some View {
        if !neighbours.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Where this leads", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(neighbours) { neighbour in
                            Button { reading = neighbour } label: {
                                RelatedChip(card: neighbour)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }
}

private struct RelatedChip: View {
    let card: Card

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: card.track.symbol)
                .font(.caption2)
            Text(card.shortLabel)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(card.track.tint.opacity(0.12), in: .capsule)
        .foregroundStyle(card.track.tint)
    }
}

// MARK: - Reading a neighbour
//
// A read-only presentation of one card with its answer open. It is what a
// link leads to, and it can be walked onward — the graph is browsable to any
// depth without ever entering the review queue.

struct CardReaderView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let card: Card

    @State private var next: Card?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(card.track.displayName, systemImage: card.track.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(card.track.tint)
                        Spacer()
                        DifficultyBadge(difficulty: card.difficulty, defense: card.defense)
                    }

                    Text(cardMarkdown(card.prompt))
                        .cardProse()

                    RelatedCardsRow(card: card, reading: $next)

                    if let latex = card.latex {
                        FormulaBlock(latex: latex, size: 19)
                    }
                    if let reading = card.reading {
                        Text(cardMarkdown(reading))
                            .font(.callout)
                            .fontDesign(.serif)
                            .foregroundStyle(.secondary)
                    }
                    if let back = card.back {
                        Text(cardMarkdown(back))
                            .font(.body)
                            .fontDesign(.serif)
                            .lineSpacing(3)
                    }
                    if let fields = card.fields, !fields.isEmpty {
                        FormulaFieldsTable(fields: fields)
                    }
                    if card.kind == .mcq, let choices = card.choices {
                        ForEach(Array(choices.enumerated()), id: \.offset) { offset, choice in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(
                                    systemName: offset == card.correct
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundStyle(offset == card.correct ? Color.green : Color(.tertiaryLabel))
                                Text(cardMarkdown(choice))
                                    .font(.callout)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if let why = card.why {
                        Label {
                            Text(cardMarkdown(why))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "lightbulb").foregroundStyle(.yellow)
                        }
                    }
                    if let explanation = card.explanation {
                        Text(cardMarkdown(explanation))
                            .font(.callout)
                            .fontDesign(.serif)
                            .lineSpacing(3)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background.secondary, in: .rect(cornerRadius: 14))
                    }

                    FigureStack(figures: card.figures, tint: card.track.tint)
                    SourceChips(anchors: card.anchors, sources: card.sources)
                }
                .padding()
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
            }
            // Walking onward opens another reader, so depth is unbounded and
            // the back stack is the reader's own trail.
            .sheet(item: $next) { CardReaderView(card: $0) }
        }
    }
}

extension Card {
    /// A short label for a chip or a row. The deck note's heading is the
    /// authored name; the prompt is a fallback for a card that has none, and
    /// it is trimmed at the em-dash gloss abbreviation cards use.
    var shortLabel: String {
        if let title, !title.isEmpty { return title }
        let text = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if let dash = text.range(of: " — ") {
            return String(text[..<dash.lowerBound])
        }
        return text.count > 34 ? String(text.prefix(32)) + "…" : text
    }
}
