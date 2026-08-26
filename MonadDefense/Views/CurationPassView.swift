import SwiftUI

// MARK: - Curation pass — sweep every card, answers open, verdict per card

/// Not a study session: nothing is graded and no FSRS state moves. The whole
/// card (prompt *and* answer *and* explanation) is on screen so the judgement
/// is about the content, not about recall.
struct CurationPassView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let cards: [Card]
    let title: String

    @State private var index = 0
    @State private var text = ""
    @State private var saved: CurationVerdict?
    @FocusState private var noteFocused: Bool

    private var card: Card? { index < cards.count ? cards[index] : nil }

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView(
                        "Nothing to curate", systemImage: "checkmark.seal",
                        description: Text("Every card in this scope already has a note."))
                } else if let card {
                    content(card)
                } else {
                    finished
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                if card != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(index + 1)/\(cards.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !cards.isEmpty, card != nil {
                    ProgressView(value: Double(index), total: Double(cards.count))
                        .tint(Theme.accent)
                        .padding(.horizontal)
                }
            }
        }
        .onAppear { load() }
    }

    // MARK: Card stage

    @ViewBuilder
    private func content(_ card: Card) -> some View {
        ScrollView {
            CurationCardBody(card: card, deckTitle: store.decksBySlug[card.deck]?.title)
                .padding()
                .id(card.id)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            verdictBar(card)
        }
    }

    private func verdictBar(_ card: Card) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Note (optional)", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($noteFocused)
                if noteFocused {
                    Button("Done") { noteFocused = false }
                        .font(.subheadline.weight(.semibold))
                }
            }
            if noteFocused {
                QuickNoteChips { phrase in append(phrase) }
            }
            HStack(spacing: 8) {
                ForEach(CurationVerdict.allCases) { option in
                    Button {
                        commit(option, for: card)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: option.symbol)
                                .font(.subheadline)
                            Text(option.displayName)
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(saved == option ? option.tint : option.tint.opacity(0.55))
                }
            }
            HStack {
                Button("Back", systemImage: "chevron.left") { step(-1) }
                    .disabled(index == 0)
                Spacer()
                if saved != nil {
                    Text("noted — \(saved!.intent.lowercased())")
                        .font(.caption2)
                        .foregroundStyle(saved!.tint)
                }
                Spacer()
                Button("Skip", systemImage: "chevron.right") { step(1) }
                    .labelStyle(.titleOnly)
            }
            .font(.footnote)
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .padding()
        .background(.bar)
    }

    private var finished: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text("Pass complete")
                .font(.title2.weight(.semibold))
            Text("\(cards.count) card(s) reviewed. Export from Curate and run `edu deck curation` in the vault.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
        }
        .padding()
    }

    // MARK: Flow

    private func append(_ phrase: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = trimmed.isEmpty ? phrase : "\(trimmed). \(phrase)"
    }

    /// Save the note under `option` and move on — one tap per card.
    private func commit(_ option: CurationVerdict, for card: Card) {
        store.setNote(text, verdict: option, for: card.id)
        noteFocused = false
        step(1)
    }

    private func step(_ delta: Int) {
        // Keep edits typed without picking a verdict on a card already noted.
        if let card, let existing = store.note(for: card.id),
            text.trimmingCharacters(in: .whitespacesAndNewlines) != existing.note
        {
            store.setNote(text, verdict: existing.verdict, for: card.id)
        }
        index = min(max(index + delta, 0), cards.count)
        load()
    }

    private func load() {
        noteFocused = false
        guard let card else {
            text = ""
            saved = nil
            return
        }
        let existing = store.note(for: card.id)
        text = existing?.note ?? ""
        saved = existing?.verdict
    }
}

// MARK: - Full card content (prompt + answer + provenance)

struct CurationCardBody: View {
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
