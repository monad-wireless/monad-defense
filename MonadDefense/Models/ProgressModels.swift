import Foundation
import SwiftData
import SwiftUI

// MARK: - On-device progress (SwiftData). Content is never stored here —
// progress is keyed by stable card IDs and survives content updates.

@Model
final class CardProgress {
    @Attribute(.unique) var cardID: String
    var stateRaw: Int
    var stability: Double
    var difficulty: Double
    var due: Date
    var lastReview: Date?
    var reps: Int
    var lapses: Int
    var learningStep: Int
    var correctCount: Int
    var wrongCount: Int

    init(cardID: String) {
        self.cardID = cardID
        self.stateRaw = FSRSState.new.rawValue
        self.stability = 0
        self.difficulty = 0
        self.due = .now
        self.lastReview = nil
        self.reps = 0
        self.lapses = 0
        self.learningStep = 0
        self.correctCount = 0
        self.wrongCount = 0
    }

    var snapshot: FSRSSnapshot {
        FSRSSnapshot(
            state: FSRSState(rawValue: stateRaw) ?? .new,
            stability: stability,
            difficulty: difficulty,
            due: due,
            lastReview: lastReview,
            reps: reps,
            lapses: lapses,
            learningStep: learningStep
        )
    }

    func apply(_ s: FSRSSnapshot) {
        stateRaw = s.state.rawValue
        stability = s.stability
        difficulty = s.difficulty
        due = s.due
        lastReview = s.lastReview
        reps = s.reps
        lapses = s.lapses
        learningStep = s.learningStep
    }

    var retrievability: Double {
        guard stateRaw == FSRSState.review.rawValue, let lastReview else {
            return stateRaw == FSRSState.new.rawValue ? 0 : 0.5
        }
        let elapsed = max(Date.now.timeIntervalSince(lastReview) / 86400, 0)
        return FSRS.retrievability(elapsedDays: elapsed, stability: stability)
    }
}

@Model
final class ReviewLog {
    var cardID: String
    var date: Date
    var ratingRaw: Int
    var kindRaw: String

    init(cardID: String, rating: FSRSRating, kind: CardKind, date: Date = .now) {
        self.cardID = cardID
        self.date = date
        self.ratingRaw = rating.rawValue
        self.kindRaw = kind.rawValue
    }

    var rating: FSRSRating { FSRSRating(rawValue: ratingRaw) ?? .again }
}

/// The verdict half of a curation note — what should happen to this card.
enum CurationVerdict: String, CaseIterable, Identifiable, Codable {
    case keep, more, fix, cut

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keep: "Keep"
        case .more: "More"
        case .fix: "Fix"
        case .cut: "Cut"
        }
    }

    /// Spelled-out intent, for lists and the exported report.
    var intent: String {
        switch self {
        case .keep: "Keep as is"
        case .more: "More cards like this"
        case .fix: "Fix at source"
        case .cut: "Cut this card"
        }
    }

    var symbol: String {
        switch self {
        case .keep: "hand.thumbsup.fill"
        case .more: "plus.circle.fill"
        case .fix: "wrench.adjustable.fill"
        case .cut: "trash.fill"
        }
    }

    var tint: Color {
        switch self {
        case .keep: .green
        case .more: .blue
        case .fix: .orange
        case .cut: .red
        }
    }
}

/// IP-124 feedback loop: the curator's verdict + free-text note on one card.
/// One note per card (editable); exported as JSON/Markdown from Curate and fed
/// to `edu deck curation` to act on at source.
@Model
final class CardNote {
    @Attribute(.unique) var cardID: String
    var verdictRaw: String
    var note: String
    var created: Date
    var updated: Date

    init(cardID: String, verdict: CurationVerdict, note: String = "", date: Date = .now) {
        self.cardID = cardID
        self.verdictRaw = verdict.rawValue
        self.note = note
        self.created = date
        self.updated = date
    }

    var verdict: CurationVerdict { CurationVerdict(rawValue: verdictRaw) ?? .fix }
}

@Model
final class SessionResult {
    var date: Date
    var modeRaw: String
    var total: Int
    var correct: Int
    var trackRaw: String?

    init(mode: String, total: Int, correct: Int, track: String?, date: Date = .now) {
        self.date = date
        self.modeRaw = mode
        self.total = total
        self.correct = correct
        self.trackRaw = track
    }
}
