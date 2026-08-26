import SwiftUI

// MARK: - Unified study session (flash / mcq / formula)

struct SessionView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let session: StudySession

    @State private var index = 0
    @State private var correct = 0
    @State private var revealed = false
    @State private var selectedChoice: Int?
    @State private var choiceOrder: [Int] = []
    @State private var feedback: FeedbackKind?
    @State private var noteTarget: Card?
    @State private var readingTarget: Card?

    enum FeedbackKind { case success, warning, error }

    private var card: Card? {
        index < session.cards.count ? session.cards[index] : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.cards.isEmpty {
                    ContentUnavailableView(
                        "Nothing here yet", systemImage: "checkmark.seal",
                        description: Text("All caught up — come back later."))
                } else if let card {
                    cardStage(card)
                } else {
                    summary
                }
            }
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { finish() }
                }
                if let card {
                    ToolbarItem(placement: .topBarTrailing) {
                        let existing = store.note(for: card.id)
                        Button {
                            noteTarget = card
                        } label: {
                            Image(
                                systemName: existing.map(\.verdict.symbol)
                                    ?? "square.and.pencil")
                        }
                        .tint(existing?.verdict.tint)
                        .accessibilityLabel("Note on this card")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(index + 1)/\(session.cards.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: $noteTarget) { card in
                CardNoteEditor(card: card)
            }
            .sheet(item: $readingTarget) { card in
                CardReaderView(card: card)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if card != nil {
                    ProgressView(value: Double(index), total: Double(session.cards.count))
                        .tint(Theme.accent)
                        .padding(.horizontal)
                }
            }
        }
        .interactiveDismissDisabled()
        .sensoryFeedback(trigger: feedback) { _, new in
            switch new {
            case .success: .success
            case .warning: .warning
            case .error: .error
            case nil: nil
            }
        }
        .onAppear { prepare() }
    }

    // MARK: Stage

    @ViewBuilder
    private func cardStage(_ card: Card) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(card.track.displayName, systemImage: card.track.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(card.track.tint)
                    Spacer()
                    DifficultyBadge(difficulty: card.difficulty, defense: card.defense)
                }

                switch card.kind {
                case .flash: flashBody(card)
                case .mcq: mcqBody(card)
                case .formula: formulaBody(card)
                }

                if revealed {
                    revealFooter(card)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding()
            .animation(.spring(duration: 0.35), value: revealed)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            bottomBar(card)
                .padding()
                .background(.bar)
        }
    }

    // MARK: Flash

    @ViewBuilder
    private func flashBody(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(cardMarkdown(card.prompt))
                .cardProse()
            if revealed {
                Divider()
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
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 20))
        .rotation3DEffect(.degrees(revealed ? 0 : 0.001), axis: (x: 0, y: 1, z: 0))
        .onTapGesture {
            if !revealed { reveal() }
        }
    }

    // MARK: MCQ

    @ViewBuilder
    private func mcqBody(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(cardMarkdown(card.prompt))
                .cardProse()
            VStack(spacing: 10) {
                ForEach(choiceOrder, id: \.self) { original in
                    choiceButton(card, original: original)
                }
            }
        }
    }

    private func choiceButton(_ card: Card, original: Int) -> some View {
        let text = card.choices?[original] ?? ""
        let isCorrect = original == card.correct
        let isSelected = selectedChoice == original

        return Button {
            guard !revealed else { return }
            selectedChoice = original
            let ok = isCorrect
            if ok { correct += 1 }
            feedback = ok ? .success : .error
            store.record(rating: ok ? .good : .again, for: card)
            reveal(recorded: true)
        } label: {
            HStack {
                Text(cardMarkdown(text))
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if revealed {
                    Image(
                        systemName: isCorrect
                            ? "checkmark.circle.fill"
                            : (isSelected ? "xmark.circle.fill" : "circle"))
                    .foregroundStyle(isCorrect ? .green : (isSelected ? .red : .secondary))
                }
            }
            .padding(14)
            .background(
                revealed && isCorrect
                    ? Color.green.opacity(0.12)
                    : (revealed && isSelected ? Color.red.opacity(0.12) : Color(.tertiarySystemFill)),
                in: .rect(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
        .disabled(revealed)
    }

    // MARK: Formula

    @ViewBuilder
    private func formulaBody(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(cardMarkdown(card.prompt))
                .cardProse()
            if revealed {
                if let latex = card.latex {
                    FormulaBlock(latex: latex)
                }
                if let reading = card.reading {
                    Label {
                        Text(cardMarkdown(reading))
                            .font(.callout)
                            .fontDesign(.serif)
                            .lineSpacing(3)
                    } icon: {
                        Image(systemName: "text.quote")
                            .foregroundStyle(.secondary)
                    }
                }
                if let fields = card.fields, !fields.isEmpty {
                    FormulaFieldsTable(fields: fields)
                }
            }
        }
        .onTapGesture {
            if !revealed { reveal() }
        }
    }

    // MARK: Reveal footer + bottom bar

    @ViewBuilder
    private func revealFooter(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if card.kind != .flash, let explanation = card.explanation {
                Text(cardMarkdown(explanation))
                    .font(.callout)
                    .fontDesign(.serif)
                    .lineSpacing(3)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: .rect(cornerRadius: 14))
            }
            if let example = card.example, !example.isEmpty {
                ExampleBlock(text: example, tint: card.track.tint)
            }
            FigureStack(figures: card.figures, tint: card.track.tint)
            RelatedCardsRow(card: card, reading: $readingTarget)
            SourceChips(anchors: card.anchors, sources: card.sources)
        }
    }

    @ViewBuilder
    private func bottomBar(_ card: Card) -> some View {
        switch card.kind {
        case .flash:
            if revealed {
                gradeBar(card)
            } else {
                Button {
                    reveal()
                } label: {
                    Label("Show answer", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
            }
        case .mcq:
            if revealed { nextButton }
        case .formula:
            if revealed {
                gradeBar(card)
            } else {
                Button {
                    reveal()
                } label: {
                    Label("Show the law", systemImage: "function")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
            }
        }
    }

    private func gradeBar(_ card: Card) -> some View {
        let snapshot = store.progress(for: card.id).snapshot
        return HStack(spacing: 8) {
            ForEach(FSRSRating.allCases, id: \.rawValue) { rating in
                Button {
                    if rating != .again { correct += 1 }
                    feedback = rating == .again ? .error : .success
                    store.record(rating: rating, for: card)
                    advance()
                } label: {
                    VStack(spacing: 2) {
                        Text(rating.label)
                            .font(.subheadline.weight(.semibold))
                        Text(FSRS.intervalPreview(snapshot, rating: rating))
                            .font(.caption2.monospacedDigit())
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(gradeTint(rating))
            }
        }
    }

    private func gradeTint(_ rating: FSRSRating) -> Color {
        switch rating {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    private var nextButton: some View {
        Button {
            advance()
        } label: {
            Label(
                index + 1 < session.cards.count ? "Next" : "Finish",
                systemImage: "arrow.right")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Theme.accent)
    }

    // MARK: Summary

    private var summary: some View {
        let total = session.cards.count
        let fraction = total > 0 ? Double(correct) / Double(total) : 0
        return VStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: fraction, tint: Theme.accent, lineWidth: 12)
                VStack {
                    Text("\(correct)/\(total)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(fraction >= 0.8 ? "Committee-ready" : "Keep drilling")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)
            Text(summaryLine(fraction))
                .font(.body)
                .fontDesign(.serif)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button {
                finish()
            } label: {
                Text("Done")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)
        }
        .padding()
        .onAppear { feedback = .success }
    }

    private func summaryLine(_ fraction: Double) -> String {
        switch fraction {
        case 0.9...: "The committee has no further questions."
        case 0.7..<0.9: "Solid. Sharpen the misses and come back."
        case 0.4..<0.7: "The gaps are showing — the misses are tomorrow's queue."
        default: "Rough session. That is exactly what this app is for."
        }
    }

    // MARK: Flow

    private func prepare() {
        guard let card else { return }
        choiceOrder = Array((card.choices ?? []).indices).shuffled()
        revealed = false
        selectedChoice = nil
        #if DEBUG
            revealed = DebugRouter.revealsImmediately
        #endif
    }

    private func reveal(recorded: Bool = false) {
        _ = recorded
        revealed = true
    }

    private func advance() {
        index += 1
        if index >= session.cards.count {
            store.finishSession(session, correct: correct)
        }
        prepare()
    }

    private func finish() {
        if index < session.cards.count, index > 0 {
            store.finishSession(session, correct: correct)
        }
        dismiss()
    }
}
