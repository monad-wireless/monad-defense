import SwiftUI

// MARK: - Screenshot and inspection routing (DEBUG only)
//
// Capturing a screenshot of one particular card, or of a session mid-answer,
// otherwise means tapping through the app by hand — which cannot be scripted
// and cannot be repeated identically when the design changes.
//
// This router opens a chosen session straight from launch. It lives inside
// `#if DEBUG` so it cannot exist in a release build: a launch argument that
// jumps into arbitrary app state is a debugging affordance, not a feature,
// and shipping one would be an invitation.
//
//   xcrun simctl launch <sim> Sibyx.monad-knowledge -DemoCards abbr-0011,abbr-0031
//   xcrun simctl launch <sim> Sibyx.monad-knowledge -DemoCards abbr-0003 -DemoReveal
//
// `-DemoReveal` opens each card with its answer already showing.

#if DEBUG

enum DebugRouter {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// Card ids named by `-DemoCards a,b,c`, in order.
    static var demoCardIDs: [String] {
        guard let index = arguments.firstIndex(of: "-DemoCards"),
            arguments.indices.contains(index + 1)
        else { return [] }
        return arguments[index + 1]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Show every card with its answer open, for capturing a revealed state.
    static var revealsImmediately: Bool { arguments.contains("-DemoReveal") }

    /// Open the read-only card reader on this id — what following a graph
    /// link leads to. `-DemoReader abbr-0031`.
    static var demoReaderID: String? {
        guard let index = arguments.firstIndex(of: "-DemoReader"),
            arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    /// Render only a card's figures, for capturing a widget without the
    /// prose above it pushing the picture off screen. `-DemoFigures <id>`.
    static var demoFiguresID: String? {
        guard let index = arguments.firstIndex(of: "-DemoFigures"),
            arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    /// The session `-DemoCards` asks for, or nil when the flag is absent.
    @MainActor
    static func demoSession(from store: StudyStore) -> StudySession? {
        let cards = demoCardIDs.compactMap { store.cardsByID[$0] }
        guard !cards.isEmpty else { return nil }
        return StudySession(
            mode: .deck, title: "Preview", cards: cards, track: cards[0].track)
    }
}

/// A card's figures alone, on a plain ground. Debug-only: it exists so a
/// screenshot of one widget is reproducible, and it is not a screen the app
/// ever navigates to.
struct FigureGalleryView: View {
    let card: Card

    var body: some View {
        NavigationStack {
            ScrollView {
                FigureStack(figures: card.figures, tint: card.track.tint)
                    .padding()
            }
            .navigationTitle(card.shortLabel)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#endif
