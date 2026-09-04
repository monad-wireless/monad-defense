import SwiftUI
import UIKit

// MARK: - Triage — one three-way swipe component, many uses (IP-151)
//
// The gesture grammar is fixed so the hand learns it once:
//   right      yes / keep / include            green
//   left       no / cut / exclude              red
//   up         send back for rework, with a note   orange
//   long-press the rare fourth verb, when a spec declares one   blue
//   tap        flip or expand the card — no decision
//
// A stack is a `TriageSpec`: what cards, what each gesture does, and what the
// card SHOWS — which is what the judgement is about, not always the whole
// card. Every action writes SwiftData first and exports later.

struct TriageAction {
    let label: String
    let symbol: String
    let tint: Color
    /// Called with the card and the note the curator typed (up-swipe opens the
    /// note sheet; the others pass any pending note).
    let perform: (Card, String) -> Void
}

struct TriageSpec {
    let title: String
    let cards: [Card]
    /// What the card shows. `expanded` toggles on tap.
    let render: (Card, _ expanded: Bool) -> AnyView
    let right: TriageAction
    let left: TriageAction
    let up: TriageAction
    var longPress: TriageAction? = nil
    /// Canned phrases for the note sheet.
    var quickNotes: [String] = []
    /// What the finished screen tells the curator to do next.
    var finishedHint: String = "Export from Curate."
}

struct TriageDeckView: View {
    @Environment(\.dismiss) private var dismiss

    let spec: TriageSpec

    @State private var index = 0
    @State private var offset: CGSize = .zero
    @State private var expanded = false
    /// Which swipe the note sheet serves — `.up` commits on Done, nil is a
    /// free note attached to the next swipe.
    @State private var noteSheet: TriageSwipe?
    @State private var noteSheetShown = false
    @State private var pendingNote = ""
    @State private var flyOut: CGSize?

    private let commitDistance: CGFloat = 110

    private var card: Card? { index < spec.cards.count ? spec.cards[index] : nil }
    private var next: Card? { index + 1 < spec.cards.count ? spec.cards[index + 1] : nil }

    var body: some View {
        NavigationStack {
            Group {
                if spec.cards.isEmpty {
                    ContentUnavailableView(
                        "Nothing to triage", systemImage: "checkmark.seal",
                        description: Text("Every card in this scope has a decision."))
                } else if let card {
                    stage(card)
                } else {
                    finished
                }
            }
            .navigationTitle(spec.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                if card != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            Button("Note", systemImage: pendingNote.isEmpty ? "square.and.pencil" : "square.and.pencil.circle.fill") {
                                showNote(for: nil)
                            }
                            Text("\(index + 1)/\(spec.cards.count)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if card != nil {
                    ProgressView(value: Double(index), total: Double(spec.cards.count))
                        .tint(Theme.accent)
                        .padding(.horizontal)
                }
            }
            .sheet(isPresented: $noteSheetShown) {
                noteEditor
            }
        }
    }

    // MARK: Stage

    @ViewBuilder
    private func stage(_ card: Card) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if let next {
                    cardFace(next, expanded: false)
                        .scaleEffect(0.96)
                        .offset(y: 10)
                        .opacity(0.6)
                        .allowsHitTesting(false)
                }
                cardFace(card, expanded: expanded)
                    .overlay(alignment: .topLeading) { cue(right: true) }
                    .overlay(alignment: .topTrailing) { cue(right: false) }
                    .overlay(alignment: .bottom) { cueUp }
                    .offset(flyOut ?? offset)
                    .rotationEffect(.degrees(Double((flyOut ?? offset).width / 18)))
                    .gesture(drag(card))
                    .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        guard let action = spec.longPress else { return }
                        haptic(.rigid)
                        commit(action, card, swipe: nil)
                    }
                    .animation(.interactiveSpring(), value: offset)
                    .id(card.id)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .frame(maxHeight: .infinity)

            legend
        }
        .background(.background.secondary)
    }

    private func cardFace(_ card: Card, expanded: Bool) -> some View {
        ScrollView {
            spec.render(card, expanded)
                .padding(18)
        }
        .scrollIndicators(.hidden)
        .background(.background, in: .rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
    }

    /// Edge cue: the label fades in as the drag approaches the commit distance.
    private func cue(right: Bool) -> some View {
        let action = right ? spec.right : spec.left
        let progress = min(max((right ? offset.width : -offset.width) / commitDistance, 0), 1)
        return Label(action.label, systemImage: action.symbol)
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(action.tint)
            .background(action.tint.opacity(0.14), in: .capsule)
            .overlay(Capsule().stroke(action.tint, lineWidth: 2))
            .rotationEffect(.degrees(right ? -12 : 12))
            .padding(18)
            .opacity(Double(progress))
    }

    private var cueUp: some View {
        let progress = min(max(-offset.height / commitDistance, 0), 1)
        return Label(spec.up.label, systemImage: spec.up.symbol)
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(spec.up.tint)
            .background(spec.up.tint.opacity(0.14), in: .capsule)
            .overlay(Capsule().stroke(spec.up.tint, lineWidth: 2))
            .padding(.bottom, 24)
            .opacity(Double(progress))
    }

    private var legend: some View {
        HStack(spacing: 0) {
            legendItem(spec.left, hint: "swipe left")
            legendItem(spec.up, hint: "swipe up")
            legendItem(spec.right, hint: "swipe right")
            if let lp = spec.longPress {
                legendItem(lp, hint: "hold")
            }
        }
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func legendItem(_ action: TriageAction, hint: String) -> some View {
        Button {
            guard let card else { return }
            haptic(.medium)
            if action.label == spec.up.label {
                showNote(for: .up)
            } else {
                commit(action, card, swipe: action.label == spec.right.label ? .right : (action.label == spec.left.label ? .left : nil))
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: action.symbol)
                    .font(.title3)
                Text(action.label)
                    .font(.caption.weight(.semibold))
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(action.tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: Gesture

    private func drag(_ card: Card) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                offset = value.translation
            }
            .onEnded { value in
                let t = value.translation
                if t.width > commitDistance {
                    haptic(.medium)
                    commit(spec.right, card, swipe: .right)
                } else if t.width < -commitDistance {
                    haptic(.medium)
                    commit(spec.left, card, swipe: .left)
                } else if t.height < -commitDistance, abs(t.width) < commitDistance {
                    haptic(.light)
                    offset = .zero
                    showNote(for: .up)
                } else {
                    offset = .zero
                }
            }
    }

    private func commit(_ action: TriageAction, _ card: Card, swipe: TriageSwipe?) {
        let note = pendingNote
        let direction: CGSize = switch swipe {
        case .right: CGSize(width: 700, height: -40)
        case .left: CGSize(width: -700, height: -40)
        case .up: CGSize(width: 0, height: -900)
        case nil: CGSize(width: 0, height: 700)
        }
        withAnimation(.easeIn(duration: 0.22)) { flyOut = direction }
        action.perform(card, note)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            flyOut = nil
            offset = .zero
            pendingNote = ""
            expanded = false
            index += 1
        }
    }

    // MARK: Note sheet

    private func showNote(for swipe: TriageSwipe?) {
        noteSheet = swipe
        noteSheetShown = true
    }

    private var noteEditor: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What should change?", text: $pendingNote, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text(noteSheet == .up
                        ? "The note lands in the vault as a fix verdict on this card."
                        : "The note is attached to your next swipe on this card.")
                }
                if !spec.quickNotes.isEmpty {
                    Section("Quick phrases") {
                        FlowChips(phrases: spec.quickNotes) { phrase in
                            let trimmed = pendingNote.trimmingCharacters(in: .whitespacesAndNewlines)
                            pendingNote = trimmed.isEmpty ? phrase : "\(trimmed). \(phrase)"
                        }
                    }
                }
            }
            .navigationTitle(noteSheet == .up ? spec.up.label : "Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if noteSheet == .up { pendingNote = "" }
                        noteSheetShown = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(noteSheet == .up ? spec.up.label : "Done") {
                        noteSheetShown = false
                        if noteSheet == .up, let card {
                            haptic(.medium)
                            commit(spec.up, card, swipe: .up)
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Finished

    private var finished: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text("Stack empty")
                .font(.title2.weight(.semibold))
            Text("\(spec.cards.count) card(s) decided. \(spec.finishedHint)")
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

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Chips that wrap

struct FlowChips: View {
    let phrases: [String]
    let onPick: (String) -> Void

    var body: some View {
        // A simple wrapping layout: rows of chips, greedy fill.
        FlowLayout(spacing: 8) {
            ForEach(phrases, id: \.self) { phrase in
                Button(phrase) { onPick(phrase) }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
