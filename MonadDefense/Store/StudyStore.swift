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
    /// Bumped when sync merges rows in. Every query reads it, so a view that
    /// shows a queue or a count redraws after another device's reviews land.
    private(set) var revision = 0

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
        _ = revision
        return (try? context.fetch(FetchDescriptor<CardProgress>())) ?? []
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
        _ = revision
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
        _ = revision
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

    /// One `now` for the schedule and the log: a device that replays the log
    /// must reach the same schedule this review produced.
    func record(rating: FSRSRating, for card: Card) {
        let now = Date.syncNow
        let progress = progress(for: card.id)
        progress.apply(FSRS.review(progress.snapshot, rating: rating, now: now))
        if rating == .again {
            progress.wrongCount += 1
        } else {
            progress.correctCount += 1
        }
        context.insert(ReviewLog(cardID: card.id, rating: rating, kind: card.kind, date: now))
        try? context.save()
    }

    func finishSession(_ session: StudySession, correct: Int) {
        context.insert(
            SessionResult(
                mode: session.mode.rawValue, total: session.cards.count, correct: correct,
                track: session.track?.rawValue, date: .syncNow))
        try? context.save()
    }

    // MARK: Export

    private static let exportFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: IP-151 triage — dwell review and eggs

    var dwellSelection: DwellSelection { bank.dwellSelection ?? .empty }

    func triageDecisions(_ scope: TriageScope) -> [TriageDecision] {
        _ = revision
        let raw = scope.rawValue
        let predicate = #Predicate<TriageDecision> { $0.scopeRaw == raw }
        return (try? context.fetch(
            FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.date, order: .reverse)])))
            ?? []
    }

    var triageDecisions: [TriageDecision] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<TriageDecision>(sortBy: [SortDescriptor(\.date, order: .reverse)])))
            ?? []
    }

    func triageDecision(_ scope: TriageScope, for cardID: String) -> TriageDecision? {
        let key = "\(scope.rawValue)|\(cardID)"
        let predicate = #Predicate<TriageDecision> { $0.key == key }
        return try? context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    /// Upsert — one row per (scope, card). Re-swiping replaces the decision.
    func setTriage(_ scope: TriageScope, _ decision: TriageSwipe, for card: Card, note: String = "") {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = scope == .dwell ? card.dwellDigest : nil
        if let existing = triageDecision(scope, for: card.id) {
            existing.decisionRaw = decision.rawValue
            existing.note = trimmed
            existing.digest = digest
            existing.date = .syncNow
        } else {
            context.insert(
                TriageDecision(scope: scope, cardID: card.id, decision: decision, note: trimmed, digest: digest, date: .syncNow))
        }
        try? context.save()
    }

    func clearTriage(_ scope: TriageScope, for cardID: String) {
        guard let existing = triageDecision(scope, for: cardID) else { return }
        tombstone([existing.key])
        context.delete(existing)
        try? context.save()
    }

    func clearAllTriage() {
        let rows = triageDecisions
        tombstone(rows.map(\.key))
        for row in rows { context.delete(row) }
        try? context.save()
    }

    var triageCount: Int {
        _ = revision
        return (try? context.fetchCount(FetchDescriptor<TriageDecision>())) ?? 0
    }

    func triageCount(_ scope: TriageScope, _ decision: TriageSwipe) -> Int {
        _ = revision
        let s = scope.rawValue
        let d = decision.rawValue
        let predicate = #Predicate<TriageDecision> { $0.scopeRaw == s && $0.decisionRaw == d }
        return (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    /// Cards for the Dwell review stack: every card with a block that the
    /// vault has not decided (or has decided on different words), minus the
    /// ones already swiped here since the last export. Stale first — those
    /// were once on the phone and are silently off it now.
    func dwellReviewQueue(track: Track?, includeDecided: Bool) -> [Card] {
        let swiped = Set(triageDecisions(.dwell).map(\.cardID))
        let selection = dwellSelection
        let pool = bank.cards.filter { card in
            guard card.dwell != nil else { return false }
            if let track, card.track != track { return false }
            if swiped.contains(card.id) { return false }
            let status = selection.status(of: card)
            if includeDecided { return true }
            return status == .undecided || status == .stale
        }
        return pool.sorted { a, b in
            let sa = selection.status(of: a) == .stale
            let sb = selection.status(of: b) == .stale
            if sa != sb { return sa }
            return (a.deck, a.id) < (b.deck, b.id)
        }
    }

    /// Cards for the Egg stack: on the phone (or swiped right here) with an
    /// instance to judge, not already tagged, and not yet decided here.
    func eggQueue(track: Track?) -> [Card] {
        let swipedEgg = Set(triageDecisions(.egg).map(\.cardID))
        let includedHere = Set(triageDecisions(.dwell).filter { $0.decision == .right }.map(\.cardID))
        let selection = dwellSelection
        return bank.cards
            .filter { card in
                guard let dwell = card.dwell, dwell.fact != nil else { return false }
                if let track, card.track != track { return false }
                if card.tags.contains("wtf") || swipedEgg.contains(card.id) { return false }
                return selection.status(of: card) == .included || includedHere.contains(card.id)
            }
            .sorted { ($0.deck, $0.id) < ($1.deck, $1.id) }
    }

    var triageExportFilenameStem: String {
        let day = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "defense-triage-\(day)"
    }

    /// JSON consumed by `monad-knowledge edu deck select <file>` (IP-151).
    var triageExportJSON: String {
        let formatter = Self.exportFormatter
        let rows: [[String: Any]] = triageDecisions.map { row in
            [
                "scope": row.scopeRaw,
                "target": row.cardID,
                "decision": row.decisionRaw,
                "digest": row.digest as Any? ?? NSNull(),
                "note": row.note.isEmpty ? NSNull() : row.note,
                "date": row.date.formatted(.iso8601.year().month().day().dateSeparator(.dash)),
            ]
        }
        let payload: [String: Any] = [
            "schema": "monad-defense/triage/1",
            "bank_version": bank.bankVersion,
            "exported_at": formatter.string(from: .now),
            "decisions": rows,
        ]
        let data = (try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    var triageExportMarkdown: String {
        var out = "# Defense triage\n\n"
        out += "bank \(bank.bankVersion) · \(triageCount) decision(s) · "
        out += "exported \(Date.now.formatted(date: .abbreviated, time: .shortened))\n"
        for scope in TriageScope.allCases {
            let rows = triageDecisions(scope)
            guard !rows.isEmpty else { continue }
            out += "\n## \(scope.displayName) (\(rows.count))\n\n"
            for row in rows.sorted(by: { $0.cardID < $1.cardID }) {
                let title = cardsByID[row.cardID]?.title ?? cardsByID[row.cardID]?.prompt ?? "(card gone from bank)"
                out += "- `\(row.cardID)` \(row.decisionRaw) — \(title.replacingOccurrences(of: "\n", with: " "))\n"
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
        _ = revision
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
        _ = revision
        var descriptor = FetchDescriptor<SessionResult>(
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 20
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Sync
    //
    // Reviews, finished sessions and swipes travel; `CardProgress` does not. A
    // card's schedule is replayed from its merged review log, so two devices
    // that reviewed the same card offline both end on the schedule of the
    // interleaved history, not on whichever wrote last.

    private static let tombstonesKey = "sync.triageTombstones"

    /// Cleared swipes by key, with when: a clear must beat an older swipe that
    /// arrives later from a device that has not seen the clear.
    private var tombstones: [String: Int64] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: Self.tombstonesKey) as? [String: NSNumber] ?? [:]
            return raw.mapValues(\.int64Value)
        }
        set {
            UserDefaults.standard.set(newValue.mapValues { NSNumber(value: $0) }, forKey: Self.tombstonesKey)
        }
    }

    private func tombstone(_ keys: [String]) {
        let now = Date.syncNow.syncMs
        var t = tombstones
        for key in keys { t[key] = now }
        tombstones = t
    }

    static func reviewID(cardID: String, date: Date, rating: Int) -> String {
        "\(cardID)|\(date.syncMs)|\(rating)"
    }

    /// This device's study rows dated at or after `since`.
    func syncRecords(since: Date) -> [SyncRecord] {
        var out: [SyncRecord] = []
        let logs = (try? context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.date >= since }))) ?? []
        for log in logs {
            var r = SyncRecord(type: SyncRecord.Kind.review)
            r.cardID = log.cardID
            r.dateMs = log.date.syncMs
            r.rating = log.ratingRaw
            r.cardKind = log.kindRaw
            out.append(r)
        }
        let results = (try? context.fetch(FetchDescriptor<SessionResult>(predicate: #Predicate { $0.date >= since }))) ?? []
        for s in results {
            var r = SyncRecord(type: SyncRecord.Kind.studySession)
            r.dateMs = s.date.syncMs
            r.studyMode = s.modeRaw
            r.total = s.total
            r.correct = s.correct
            r.track = s.trackRaw
            out.append(r)
        }
        let swipes = (try? context.fetch(FetchDescriptor<TriageDecision>(predicate: #Predicate { $0.date >= since }))) ?? []
        for t in swipes {
            var r = SyncRecord(type: SyncRecord.Kind.triage)
            r.key = t.key
            r.scope = t.scopeRaw
            r.cardID = t.cardID
            r.decision = t.decisionRaw
            r.note = t.note
            r.digest = t.digest
            r.dateMs = t.date.syncMs
            out.append(r)
        }
        let sinceMs = since.syncMs
        for (key, ms) in tombstones where ms >= sinceMs {
            var r = SyncRecord(type: SyncRecord.Kind.triage)
            r.key = key
            r.dateMs = ms
            r.cleared = true
            out.append(r)
        }
        return out
    }

    /// Merge another device's study rows. Returns how many rows changed.
    @discardableResult
    func apply(_ records: [SyncRecord]) -> Int {
        var changed = 0
        var replay = Set<String>()

        let reviews = records.filter { $0.type == SyncRecord.Kind.review }
        if !reviews.isEmpty {
            let logs = (try? context.fetch(FetchDescriptor<ReviewLog>())) ?? []
            var known = Set(logs.map { Self.reviewID(cardID: $0.cardID, date: $0.date, rating: $0.ratingRaw) })
            for r in reviews {
                guard let card = r.cardID, let ms = r.dateMs, let raw = r.rating, let rating = FSRSRating(rawValue: raw)
                else { continue }
                let date = Date(syncMs: ms)
                let id = Self.reviewID(cardID: card, date: date, rating: raw)
                guard !known.contains(id) else { continue }
                let kind = r.cardKind.flatMap(CardKind.init(rawValue:)) ?? cardsByID[card]?.kind ?? .flash
                context.insert(ReviewLog(cardID: card, rating: rating, kind: kind, date: date))
                known.insert(id)
                replay.insert(card)
                changed += 1
            }
        }

        let results = records.filter { $0.type == SyncRecord.Kind.studySession }
        if !results.isEmpty {
            let rows = (try? context.fetch(FetchDescriptor<SessionResult>())) ?? []
            var known = Set(rows.map { "\($0.date.syncMs)|\($0.modeRaw)" })
            for r in results {
                guard let ms = r.dateMs, let mode = r.studyMode, !known.contains("\(ms)|\(mode)") else { continue }
                context.insert(
                    SessionResult(mode: mode, total: r.total ?? 0, correct: r.correct ?? 0, track: r.track, date: Date(syncMs: ms)))
                known.insert("\(ms)|\(mode)")
                changed += 1
            }
        }

        for r in records where r.type == SyncRecord.Kind.triage {
            guard let key = r.key, let ms = r.dateMs else { continue }
            if let cleared = tombstones[key], cleared >= ms { continue }
            let predicate = #Predicate<TriageDecision> { $0.key == key }
            let local = try? context.fetch(FetchDescriptor(predicate: predicate)).first
            if let local, local.date.syncMs >= ms { continue }
            if r.cleared == true {
                var t = tombstones
                t[key] = ms
                tombstones = t
                if let local {
                    context.delete(local)
                    changed += 1
                }
                continue
            }
            guard let scope = r.scope.flatMap(TriageScope.init(rawValue:)), let cardID = r.cardID,
                let decision = r.decision.flatMap(TriageSwipe.init(rawValue:))
            else { continue }
            if let local {
                local.decisionRaw = decision.rawValue
                local.note = r.note ?? ""
                local.digest = r.digest
                local.date = Date(syncMs: ms)
            } else {
                context.insert(
                    TriageDecision(
                        scope: scope, cardID: cardID, decision: decision, note: r.note ?? "", digest: r.digest,
                        date: Date(syncMs: ms)))
            }
            changed += 1
        }

        for card in replay where cardsByID[card] != nil { replayProgress(card) }
        if changed > 0 {
            try? context.save()
            revision += 1
        }
        return changed
    }

    /// Rebuild a card's schedule and counts from its whole review log.
    private func replayProgress(_ cardID: String) {
        let predicate = #Predicate<ReviewLog> { $0.cardID == cardID }
        let logs = (try? context.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.date)]))) ?? []
        let progress = progress(for: cardID)
        var s = CardProgress(cardID: cardID).snapshot
        var correct = 0
        var wrong = 0
        for log in logs {
            s = FSRS.review(s, rating: log.rating, now: log.date)
            if log.rating == .again { wrong += 1 } else { correct += 1 }
        }
        progress.apply(s)
        progress.correctCount = correct
        progress.wrongCount = wrong
    }
}
