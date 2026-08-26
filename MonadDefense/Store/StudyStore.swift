import Foundation
import SwiftData
import SwiftUI

// MARK: - Session descriptor

enum SessionMode: String, Identifiable {
    case review = "Review"
    case quiz = "Quick Quiz"
    case fundamentals = "Fundamentals"
    case explore = "Explore"
    case committee = "Committee Room"
    case deck = "Deck"

    var id: String { rawValue }
}

struct StudySession: Identifiable {
    let id = UUID()
    let mode: SessionMode
    let title: String
    let cards: [Card]
    let track: Track?
}

// MARK: - Study store

@MainActor
@Observable
final class StudyStore {
    let bank: DeckBank
    let cardsByID: [String: Card]
    let decksBySlug: [String: Deck]
    private let context: ModelContext

    init(context: ModelContext) {
        let bank = DeckBank.loadBundled()
        self.bank = bank
        self.cardsByID = Dictionary(uniqueKeysWithValues: bank.cards.map { ($0.id, $0) })
        self.decksBySlug = Dictionary(uniqueKeysWithValues: bank.decks.map { ($0.slug, $0) })
        self.context = context
        pruneOrphans()
    }

    /// Remove progress rows whose card no longer exists in the bank.
    private func pruneOrphans() {
        guard let rows = try? context.fetch(FetchDescriptor<CardProgress>()) else { return }
        for row in rows where cardsByID[row.cardID] == nil {
            context.delete(row)
        }
    }

    // MARK: Progress access

    func progress(for cardID: String) -> CardProgress {
        let predicate = #Predicate<CardProgress> { $0.cardID == cardID }
        if let existing = try? context.fetch(FetchDescriptor(predicate: predicate)).first {
            return existing
        }
        let fresh = CardProgress(cardID: cardID)
        context.insert(fresh)
        return fresh
    }

    private func allProgress() -> [CardProgress] {
        (try? context.fetch(FetchDescriptor<CardProgress>())) ?? []
    }

    // MARK: Queries

    var dueCards: [Card] {
        let now = Date.now
        let dueIDs = allProgress()
            .filter { $0.stateRaw != FSRSState.new.rawValue && $0.due <= now }
            .sorted { $0.due < $1.due }
            .map(\.cardID)
        return dueIDs.compactMap { cardsByID[$0] }
    }

    var newCards: [Card] {
        let seen = Set(allProgress().filter { $0.stateRaw != FSRSState.new.rawValue }.map(\.cardID))
        return bank.cards.filter { !seen.contains($0.id) }
    }

    var defenseCards: [Card] { bank.cards.filter(\.defense) }

    /// Weakest committee-style card — the Today spotlight.
    var committeePick: Card? {
        let progressByID = Dictionary(
            uniqueKeysWithValues: allProgress().map { ($0.cardID, $0) })
        return defenseCards.min { a, b in
            let ra = progressByID[a.id]?.retrievability ?? 0
            let rb = progressByID[b.id]?.retrievability ?? 0
            return ra < rb
        }
    }

    /// The cards a given card links to, in bank order.
    func related(to card: Card) -> [Card] {
        (card.seeAlso ?? []).compactMap { cardsByID[$0] }
    }

    /// A session that walks a neighbourhood: the card, then everything it
    /// leads to. Reading around a term is a different act from drilling it,
    /// so this deliberately does not touch the FSRS queue ordering.
    func exploreSession(from card: Card) -> StudySession {
        StudySession(
            mode: .explore, title: "Around this card", cards: [card] + related(to: card),
            track: card.track)
    }

    func cards(inDeck slug: String) -> [Card] {
        bank.cards.filter { $0.deck == slug }
    }

    func decks(in track: Track) -> [Deck] {
        bank.decks
            .filter { $0.track == track }
            .sorted { ($0.difficulty, $0.slug) < ($1.difficulty, $1.slug) }
    }

    struct TrackStats {
        var total: Int = 0
        var seen: Int = 0
        var due: Int = 0
        var mastery: Double = 0  // mean retrievability over all cards, unseen = 0
    }

    func stats(for track: Track) -> TrackStats {
        let cards = bank.cards.filter { $0.track == track }
        return stats(over: cards)
    }

    func stats(over cards: [Card]) -> TrackStats {
        var s = TrackStats(total: cards.count)
        guard !cards.isEmpty else { return s }
        let ids = Set(cards.map(\.id))
        let rows = allProgress().filter { ids.contains($0.cardID) }
        let now = Date.now
        var retrievabilitySum = 0.0
        for row in rows {
            if row.stateRaw != FSRSState.new.rawValue {
                s.seen += 1
                retrievabilitySum += row.retrievability
                if row.due <= now { s.due += 1 }
            }
        }
        s.mastery = retrievabilitySum / Double(cards.count)
        return s
    }

    var overallStats: TrackStats { stats(over: bank.cards) }

    /// Consecutive days (ending today or yesterday) with at least one review.
    var streak: Int {
        let logs = (try? context.fetch(FetchDescriptor<ReviewLog>())) ?? []
        let calendar = Calendar.current
        let days = Set(logs.map { calendar.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }
        var cursor = calendar.startOfDay(for: .now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                days.contains(yesterday)
            else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    var reviewsToday: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let predicate = #Predicate<ReviewLog> { $0.date >= start }
        return (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    // MARK: Session builders

    private func weakFirst(_ cards: [Card]) -> [Card] {
        let progressByID = Dictionary(
            uniqueKeysWithValues: allProgress().map { ($0.cardID, $0) })
        return cards.sorted {
            (progressByID[$0.id]?.retrievability ?? 0) < (progressByID[$1.id]?.retrievability ?? 0)
        }
    }

    func reviewSession(newLimit: Int = 10) -> StudySession {
        var cards = dueCards
        if cards.count < newLimit {
            cards += newCards.shuffled().prefix(newLimit - cards.count)
        }
        return StudySession(mode: .review, title: "Review", cards: cards, track: nil)
    }

    func quizSession(count: Int = 10, track: Track? = nil) -> StudySession {
        var pool = bank.cards.filter { $0.kind == .mcq || $0.kind == .formula }
        if let track { pool = pool.filter { $0.track == track } }
        let weak = weakFirst(pool)
        // Half weakest, half random — drill weaknesses without becoming a rut.
        let half = count / 2
        var picked = Array(weak.prefix(half))
        let rest = pool.filter { card in !picked.contains(where: { $0.id == card.id }) }
        picked += rest.shuffled().prefix(count - picked.count)
        return StudySession(
            mode: .quiz, title: track.map { "\($0.code) Quiz" } ?? "Quick Quiz",
            cards: picked.shuffled(), track: track)
    }

    /// The vocabulary pass: abbreviations, symbols, topic ownership, formulas.
    /// Weakest first — this is the layer that decays quietest and costs most
    /// when it fails, because a hesitation here reads as not knowing the field.
    func fundamentalsSession(count: Int = 12) -> StudySession {
        let pool = bank.cards.filter { $0.track == .core }
        let picked = Array(weakFirst(pool).prefix(count)).shuffled()
        return StudySession(mode: .fundamentals, title: "Fundamentals", cards: picked, track: .core)
    }

    func committeeSession(count: Int = 12) -> StudySession {
        let picked = Array(weakFirst(defenseCards).prefix(count)).shuffled()
        return StudySession(mode: .committee, title: "Committee Room", cards: picked, track: nil)
    }

    func deckSession(_ deck: Deck) -> StudySession {
        StudySession(
            mode: .deck, title: deck.shortTitle, cards: cards(inDeck: deck.slug).shuffled(),
            track: deck.track)
    }

    // MARK: Recording

    func record(rating: FSRSRating, for card: Card) {
        let progress = progress(for: card.id)
        progress.apply(FSRS.review(progress.snapshot, rating: rating))
        if rating == .again {
            progress.wrongCount += 1
        } else {
            progress.correctCount += 1
        }
        context.insert(ReviewLog(cardID: card.id, rating: rating, kind: card.kind))
        try? context.save()
    }

    func finishSession(_ session: StudySession, correct: Int) {
        context.insert(
            SessionResult(
                mode: session.mode.rawValue, total: session.cards.count, correct: correct,
                track: session.track?.rawValue))
        try? context.save()
    }

    // MARK: Curation notes (feedback loop — "keep this / cut this / more of this")

    /// Canned phrases the note editor appends — the recurring verdicts, typed once.
    static let quickNotes = [
        "Wrong number", "Wrong claim", "Misleading", "Badly worded", "Too trivial",
        "Needs an example", "Split in two", "Add a source",
    ]

    var notes: [CardNote] {
        (try? context.fetch(
            FetchDescriptor<CardNote>(sortBy: [SortDescriptor(\.updated, order: .reverse)])))
            ?? []
    }

    func note(for cardID: String) -> CardNote? {
        let predicate = #Predicate<CardNote> { $0.cardID == cardID }
        return try? context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    /// Upsert — editing a card's verdict or note keeps one row per card.
    func setNote(_ text: String, verdict: CurationVerdict, for cardID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = note(for: cardID) {
            existing.verdictRaw = verdict.rawValue
            existing.note = trimmed
            existing.updated = .now
        } else {
            context.insert(CardNote(cardID: cardID, verdict: verdict, note: trimmed))
        }
        try? context.save()
    }

    func clearNote(_ cardID: String) {
        guard let existing = note(for: cardID) else { return }
        context.delete(existing)
        try? context.save()
    }

    func clearAllNotes() {
        for row in notes { context.delete(row) }
        try? context.save()
    }

    var curatedCount: Int {
        (try? context.fetchCount(FetchDescriptor<CardNote>())) ?? 0
    }

    func curationCount(_ verdict: CurationVerdict) -> Int {
        let raw = verdict.rawValue
        let predicate = #Predicate<CardNote> { $0.verdictRaw == raw }
        return (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    /// Cards to sweep, grouped deck by deck so the pass mirrors the vault
    /// notes you will edit afterwards.
    func curationQueue(track: Track?, onlyUncurated: Bool) -> [Card] {
        let curated = Set(notes.map(\.cardID))
        return bank.cards
            .filter { card in
                if let track, card.track != track { return false }
                if onlyUncurated, curated.contains(card.id) { return false }
                return true
            }
            .sorted { ($0.deck, $0.id) < ($1.deck, $1.id) }
    }

    func curationProgress(track: Track?) -> (curated: Int, total: Int) {
        let pool = bank.cards.filter { track == nil || $0.track == track }
        let curated = Set(notes.map(\.cardID))
        return (pool.filter { curated.contains($0.id) }.count, pool.count)
    }

    // MARK: Export

    private static let exportFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var exportFilenameStem: String {
        let day = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "defense-curation-\(day)"
    }

    /// JSON payload consumed by `monad-knowledge edu deck curation <file>`.
    var curationExportJSON: String {
        let formatter = Self.exportFormatter
        let rows: [[String: Any]] = notes.map { row in
            let card = cardsByID[row.cardID]
            return [
                "card_id": row.cardID,
                "verdict": row.verdictRaw,
                "note": row.note,
                "deck": card?.deck ?? "",
                "track": card?.track.rawValue ?? "",
                "prompt": card?.prompt.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                "updated": formatter.string(from: row.updated),
            ]
        }
        let payload: [String: Any] = [
            "schema": "monad-defense/curation/1",
            "bank_version": bank.bankVersion,
            "exported_at": formatter.string(from: .now),
            "cards_total": bank.cards.count,
            "cards_curated": rows.count,
            "notes": rows,
        ]
        let data = (try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Human-readable twin of the JSON — paste into a vault note or a chat.
    var curationExportMarkdown: String {
        let rows = notes
        var out = "# Defense card curation\n\n"
        out += "bank \(bank.bankVersion) · \(rows.count) of \(bank.cards.count) cards curated · "
        out += "exported \(Date.now.formatted(date: .abbreviated, time: .shortened))\n"
        for verdict in CurationVerdict.allCases {
            let group = rows.filter { $0.verdict == verdict }
            guard !group.isEmpty else { continue }
            out += "\n## \(verdict.intent) (\(group.count))\n\n"
            for row in group.sorted(by: { $0.cardID < $1.cardID }) {
                let card = cardsByID[row.cardID]
                let prompt = card?.prompt
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ") ?? "(card gone from bank)"
                out += "- `\(row.cardID)` — \(prompt)\n"
                if let deck = card?.deck { out += "  - deck: `\(deck)`\n" }
                if !row.note.isEmpty { out += "  - note: \(row.note)\n" }
            }
        }
        return out
    }

    // MARK: Stats feeds

    struct DayActivity: Identifiable {
        let id: Date
        let count: Int
    }

    func activity(days: Int = 84) -> [DayActivity] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: .now))!
        let predicate = #Predicate<ReviewLog> { $0.date >= start }
        let logs = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        let grouped = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.date) }
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return DayActivity(id: day, count: grouped[day]?.count ?? 0)
        }
    }

    var recentSessions: [SessionResult] {
        var descriptor = FetchDescriptor<SessionResult>(
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 20
        return (try? context.fetch(descriptor)) ?? []
    }
}
