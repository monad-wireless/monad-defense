import SwiftUI

struct TracksView: View {
    @Environment(StudyStore.self) private var store
    @State private var session: StudySession?

    var body: some View {
        NavigationStack {
            List {
                ForEach(Track.allCases) { track in
                    if !store.decks(in: track).isEmpty {
                        Section {
                            trackHeader(track)
                            ForEach(store.decks(in: track)) { deck in
                                deckRow(deck)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tracks")
            .fullScreenCover(item: $session) { session in
                SessionView(session: session)
            }
        }
    }

    private func trackHeader(_ track: Track) -> some View {
        let stats = store.stats(for: track)
        return HStack(spacing: 14) {
            ZStack {
                ProgressRing(progress: stats.mastery, tint: track.tint, lineWidth: 5)
                Image(systemName: track.symbol)
                    .font(.subheadline)
                    .foregroundStyle(track.tint)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayName)
                    .font(.headline)
                Text("\(track.code) · \(stats.seen)/\(stats.total) seen · \(stats.due) due")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                session = store.quizSession(track: track)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(track.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quiz \(track.displayName)")
        }
        .padding(.vertical, 4)
    }

    private func deckRow(_ deck: Deck) -> some View {
        let stats = store.stats(over: store.cards(inDeck: deck.slug))
        return Button {
            session = store.deckSession(deck)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.shortTitle)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    DifficultyBadge(difficulty: deck.difficulty, defense: deck.defense)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(deck.cardCount)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text("\(Int((stats.mastery * 100).rounded()))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
