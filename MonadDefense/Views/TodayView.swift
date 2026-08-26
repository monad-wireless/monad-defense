import SwiftUI

struct TodayView: View {
    @Environment(StudyStore.self) private var store
    @State private var session: StudySession?
    #if DEBUG
        @State private var debugReader: Card?
        @State private var debugFigures: Card?
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    StalenessNotice(ageInDays: store.bank.ageInDays)
                    actions
                    committeeSpotlight
                }
                .padding()
            }
            .background(.background.secondary.opacity(0.4))
            .navigationTitle("Defense")
            .fullScreenCover(item: $session) { session in
                SessionView(session: session)
            }
            #if DEBUG
                .sheet(item: $debugReader) { CardReaderView(card: $0) }
                .fullScreenCover(item: $debugFigures) { FigureGalleryView(card: $0) }
                .onAppear {
                    session = session ?? DebugRouter.demoSession(from: store)
                    debugReader =
                        debugReader ?? DebugRouter.demoReaderID.flatMap { store.cardsByID[$0] }
                    debugFigures =
                        debugFigures ?? DebugRouter.demoFiguresID.flatMap { store.cardsByID[$0] }
                }
            #endif
        }
    }

    private var header: some View {
        let due = store.dueCards.count
        let stats = store.overallStats
        return HStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: stats.mastery, tint: Theme.accent, lineWidth: 10)
                VStack(spacing: 0) {
                    Text("\(Int((stats.mastery * 100).rounded()))")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("mastery")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 108, height: 108)

            VStack(alignment: .leading, spacing: 8) {
                metric(
                    value: "\(due)", label: due == 1 ? "card due" : "cards due",
                    symbol: "tray.full", tint: due > 0 ? .orange : .green)
                metric(
                    value: "\(store.streak)", label: "day streak", symbol: "flame",
                    tint: store.streak > 0 ? .red : .secondary)
                metric(
                    value: "\(store.reviewsToday)", label: "reviews today",
                    symbol: "checkmark.circle", tint: Theme.accent)
            }
            Spacer()
        }
        .padding(18)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private func metric(value: String, label: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        let due = store.dueCards.count
        return VStack(spacing: 12) {
            Button {
                session = store.reviewSession()
            } label: {
                ActionCard(
                    title: due > 0 ? "Review \(due) due" : "Learn new cards",
                    subtitle: due > 0
                        ? "Spaced repetition — clear the queue"
                        : "Nothing due — pull fresh cards into rotation",
                    symbol: "rectangle.on.rectangle.angled", tint: Theme.accent)
            }
            HStack(spacing: 12) {
                Button {
                    session = store.quizSession()
                } label: {
                    ActionCard(
                        title: "Quick Quiz", subtitle: "10 questions, weak spots first",
                        symbol: "checklist", tint: .teal)
                }
                Button {
                    session = store.fundamentalsSession()
                } label: {
                    ActionCard(
                        title: "Fundamentals",
                        subtitle: "Shortcuts, definitions, formulas",
                        symbol: "character.book.closed", tint: .mint)
                }
            }
            Button {
                session = store.committeeSession()
            } label: {
                ActionCard(
                    title: "Committee Room",
                    subtitle: "Traps, big questions, and near-miss claims",
                    symbol: "person.3.fill", tint: .red)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var committeeSpotlight: some View {
        if let pick = store.committeePick {
            VStack(alignment: .leading, spacing: 10) {
                Label("Committee pick", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(pick.prompt.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.body)
                    .fontDesign(.serif)
                    .lineLimit(4)
                HStack {
                    DifficultyBadge(difficulty: pick.difficulty, defense: pick.defense)
                    Spacer()
                    Text(pick.track.displayName)
                        .font(.caption)
                        .foregroundStyle(pick.track.tint)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 20))
        }
    }
}
