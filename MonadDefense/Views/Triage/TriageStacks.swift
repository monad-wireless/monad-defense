import SwiftUI

// MARK: - The two IP-151 stacks, each one `TriageSpec` declaration

/// Dwell review — does this card's dwell block belong on a participant's phone?
/// The card renders as the monad-app panel; tap flips to the full card.
struct DwellReviewView: View {
    @Environment(StudyStore.self) private var store
    let cards: [Card]
    let title: String

    var body: some View {
        TriageDeckView(spec: spec)
    }

    private var spec: TriageSpec {
        let store = store
        return TriageSpec(
            title: title,
            cards: cards,
            render: { card, expanded in
                if expanded || card.dwell == nil {
                    return AnyView(CurationCardBody(card: card, deckTitle: store.decksBySlug[card.deck]?.title))
                }
                return AnyView(
                    DwellPanelMock(card: card, block: card.dwell!, status: store.dwellSelection.status(of: card))
                )
            },
            right: TriageAction(label: "Include", symbol: "iphone.badge.checkmark", tint: .green) { card, note in
                store.setTriage(.dwell, .right, for: card, note: note)
            },
            left: TriageAction(label: "Exclude", symbol: "iphone.slash", tint: .red) { card, note in
                store.setTriage(.dwell, .left, for: card, note: note)
            },
            up: TriageAction(label: "Rework", symbol: "wrench.adjustable", tint: .orange) { card, note in
                store.setTriage(.dwell, .up, for: card, note: note)
            },
            quickNotes: [
                "Too long", "Definition again", "No instance", "Jargon", "Wrong emphasis",
                "Quip is weak", "Needs a number", "Split the idea",
            ],
            finishedHint: "Export from Curate and run `edu deck select <file>` in the vault."
        )
    }
}

/// Eggs — is this card's instance the absurd kind that makes somebody walk
/// the quest again? Right sets the `wtf` tag, left leaves it plain, up asks
/// for a rewrite that would earn it.
struct EggTriageView: View {
    @Environment(StudyStore.self) private var store
    let cards: [Card]
    let title: String

    var body: some View {
        TriageDeckView(spec: spec)
    }

    private var spec: TriageSpec {
        let store = store
        return TriageSpec(
            title: title,
            cards: cards,
            render: { card, expanded in
                if expanded || card.dwell == nil {
                    return AnyView(CurationCardBody(card: card, deckTitle: store.decksBySlug[card.deck]?.title))
                }
                return AnyView(DwellPanelMock(card: card, block: card.dwell!, status: .included))
            },
            right: TriageAction(label: "Egg", symbol: "sparkles", tint: .green) { card, note in
                store.setTriage(.egg, .right, for: card, note: note)
            },
            left: TriageAction(label: "Plain", symbol: "circle", tint: .red) { card, note in
                store.setTriage(.egg, .left, for: card, note: note)
            },
            up: TriageAction(label: "Could be", symbol: "wand.and.sparkles", tint: .orange) { card, note in
                store.setTriage(.egg, .up, for: card, note: note)
            },
            quickNotes: ["Lead with the number", "Drier", "Too clever", "The instance is the joke", "Cut the quip"],
            finishedHint: "Export from Curate and run `edu deck select <file>` — right-swipes land as the `wtf` tag."
        )
    }
}
