import SwiftUI

// MARK: - Full card content (prompt + answer + provenance)
//
// The whole card with its answer open, for the swipe stacks: the judgement is
// about the content, not about recall.

struct FullCardBody: View {
    let card: Card
    var deckTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(card.track.displayName, systemImage: card.track.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(card.track.tint)
                Spacer()
                DifficultyBadge(difficulty: card.difficulty, defense: card.defense)
            }

            Text(cardMarkdown(card.prompt))
                .cardProse()

            switch card.kind {
            case .flash: flashAnswer
            case .mcq: mcqAnswer
            case .formula: formulaAnswer
            }

            if card.kind != .flash, let explanation = card.explanation {
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

            HStack {
                Label(card.kind.displayName, systemImage: card.kind.symbol)
                Spacer()
                Text(card.id)
                    .textSelection(.enabled)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)

            if let deckTitle {
                Text(deckTitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var flashAnswer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(cardMarkdown(card.back ?? ""))
                .font(.body)
                .fontDesign(.serif)
                .lineSpacing(3)
            if let why = card.why {
                Label {
                    Text(cardMarkdown(why))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var mcqAnswer: some View {
        VStack(spacing: 8) {
            ForEach(Array((card.choices ?? []).enumerated()), id: \.offset) { offset, choice in
                let isCorrect = offset == card.correct
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isCorrect ? Color.green : Color(.tertiaryLabel))
                    Text(cardMarkdown(choice))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(
                    isCorrect ? Color.green.opacity(0.10) : Color(.tertiarySystemFill),
                    in: .rect(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private var formulaAnswer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let latex = card.latex {
                FormulaBlock(latex: latex, size: 19)
            }
            if let reading = card.reading {
                Text(cardMarkdown(reading))
                    .font(.callout)
                    .fontDesign(.serif)
                    .foregroundStyle(.secondary)
            }
            if let fields = card.fields, !fields.isEmpty {
                FormulaFieldsTable(fields: fields)
            }
        }
    }
}
