import SwiftUI
import UIKit

// MARK: - Triage — one three-way swipe component, many uses (IP-151)
//
// The gesture grammar is fixed so the hand learns it once:
//   right      yes / keep / include            green
//   left       no / cut / exclude              red
//   up         send back for rework, with a note   orange   (the button bar)
//   fourth     the rare fourth verb, when a spec declares one   blue   (the button bar)
//   tap        flip or expand the card — no decision
//
// Only horizontal drags decide. A vertical drag scrolls the card, so long
// evidence can be read without a stray "up" commit, and holding a finger on
// the text never decides anything (2026-10-13: both did, mid-read).
//
// A stack is a `TriageSpec`: what cards, what each gesture does, and what the
// card SHOWS — which is what the judgement is about, not always the whole
// card. Every action writes SwiftData first and exports later.
//
// The deck is generic over the item (IP-161): study `Card`s for the IP-151
// stacks, `DeskCard`s for the Desk. An action reports what happened. Only a
// saved action advances; a failed one keeps the card and shows why; an action
// that needs input first returns an editor, and the card advances only when
// that editor reports a save. Cancelling an editor leaves the card untouched.

enum TriageOutcome {
    case saved
    case failed(String)
    /// Present this editor. It calls `finish` after it has saved.
    case edit((_ finish: @escaping () -> Void) -> AnyView)
}

struct TriageAction<Item> {
    let label: String
    let symbol: String
    let tint: Color
    /// Called with the item and the note the curator typed (up-swipe opens the
    /// note sheet unless the spec turns that off; the others pass any pending note).
    let perform: (Item, String) -> TriageOutcome
}

struct TriageSpec<Item: Identifiable> {
    let title: String
    let cards: [Item]
    /// What the card shows. `expanded` toggles on tap.
    let render: (Item, _ expanded: Bool) -> AnyView
    let right: TriageAction<Item>
    let left: TriageAction<Item>
    let up: TriageAction<Item>
    var longPress: TriageAction<Item>? = nil
    /// Canned phrases for the note sheet.
    var quickNotes: [String] = []
    /// What the finished screen tells the curator to do next.
    var finishedHint: String = "Export from Curate."
    /// Up opens the free-text note sheet before `up.perform`. Off when the
    /// up action brings its own editor.
    var upOpensNote: Bool = true
    /// Reverse the decision on an item decided in this sitting. Nil hides undo.
    var undo: ((Item) -> TriageOutcome)? = nil
    /// The finished-screen noun.
    var noun: String = "card(s)"
}

struct TriageDeckView<Item: Identifiable>: View {
    @Environment(\.dismiss) private var dismiss

    let spec: TriageSpec<Item>

    @State private var index = 0
    @State private var offset: CGSize = .zero
    @State private var expanded = false
    /// Which swipe the note sheet serves — `.up` commits on Done, nil is a
    /// free note attached to the next swipe.
    @State private var noteSheet: TriageSwipe?
    @State private var noteSheetShown = false
    @State private var pendingNote = ""
    @State private var flyOut: CGSize?
    @State private var editor: EditorRequest?
    @State private var errorText: String?
    /// Indices decided in this sitting, newest last, for undo.
    @State private var decided: [Int] = []

    private struct EditorRequest: Identifiable {
        let id = UUID()
        let view: AnyView
    }

    private enum Slot { case right, left, up, hold }

    private let commitDistance: CGFloat = 110

    private var card: Item? { index < spec.cards.count ? spec.cards[index] : nil }
    private var next: Item? { index + 1 < spec.cards.count ? spec.cards[index + 1] : nil }

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
                if spec.undo != nil, !decided.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Undo", systemImage: "arrow.uturn.backward") { undoLast() }
                    }
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
            .sheet(item: $editor) { request in
                request.view
            }
            .alert(
                "Not saved",
                isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
            ) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: Stage

    @ViewBuilder
    private func stage(_ card: Item) -> some View {
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
                    .simultaneousGesture(drag(card))
                    .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
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

    private func cardFace(_ card: Item, expanded: Bool) -> some View {
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
            legendItem(spec.left, slot: .left, hint: "swipe left")
            legendItem(spec.up, slot: .up, hint: "tap")
            legendItem(spec.right, slot: .right, hint: "swipe right")
            if let lp = spec.longPress {
                legendItem(lp, slot: .hold, hint: "tap")
            }
        }
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func legendItem(_ action: TriageAction<Item>, slot: Slot, hint: String) -> some View {
        Button {
            guard let card else { return }
            haptic(.medium)
            switch slot {
            case .up: up(card)
            case .right: commit(action, card, swipe: .right)
            case .left: commit(action, card, swipe: .left)
            case .hold: commit(action, card, swipe: nil)
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
        .accessibilityLabel(Text(action.label))
        .accessibilityHint(Text(hint))
    }

    // MARK: Gesture

    /// Horizontal only: the card follows a drag that is mostly sideways, and a
    /// vertical drag stays with the scroll view underneath.
    private func drag(_ card: Item) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let t = value.translation
                guard flyOut == nil, abs(t.width) > abs(t.height) * 1.4 else { return }
                offset = CGSize(width: t.width, height: t.height * 0.15)
            }
            .onEnded { value in
                let t = value.translation
                guard flyOut == nil, abs(t.width) > abs(t.height) * 1.4 else {
                    offset = .zero
                    return
                }
                if t.width > commitDistance {
                    haptic(.medium)
                    commit(spec.right, card, swipe: .right)
                } else if t.width < -commitDistance {
                    haptic(.medium)
                    commit(spec.left, card, swipe: .left)
                } else {
                    offset = .zero
                }
            }
    }

    private func up(_ card: Item) {
        if spec.upOpensNote {
            showNote(for: .up)
        } else {
            commit(spec.up, card, swipe: .up)
        }
    }

    /// Run the action first; only a save moves the deck on. A second tap while
    /// the card is still flying out would decide the same card twice.
    private func commit(_ action: TriageAction<Item>, _ card: Item, swipe: TriageSwipe?) {
        guard flyOut == nil, editor == nil else { return }
        switch action.perform(card, pendingNote) {
        case .saved:
            advance(swipe)
        case .failed(let message):
            offset = .zero
            haptic(.heavy)
            errorText = message
        case .edit(let build):
            offset = .zero
            editor = EditorRequest(view: build {
                editor = nil
                advance(swipe)
            })
        }
    }

    private func undoLast() {
        guard let undo = spec.undo, let last = decided.last else { return }
        switch undo(spec.cards[last]) {
        case .saved:
            decided.removeLast()
            haptic(.light)
            withAnimation(.snappy) {
                index = last
                expanded = false
                offset = .zero
            }
        case .failed(let message):
            errorText = message
        case .edit:
            break
        }
    }

    private func advance(_ swipe: TriageSwipe?) {
        decided.append(index)
        let direction: CGSize = switch swipe {
        case .right: CGSize(width: 700, height: -40)
        case .left: CGSize(width: -700, height: -40)
        case .up: CGSize(width: 0, height: -900)
        case nil: CGSize(width: 0, height: 700)
        }
        withAnimation(.easeIn(duration: 0.22)) { flyOut = direction }
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
            Text("\(spec.cards.count) \(spec.noun) decided. \(spec.finishedHint)")
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
