import Foundation

// MARK: - Device sync records (`monad-defense/sync/1`)
//
// Every device pushes its own history to the Desk API as batches of records
// and reads every other device's batches back. Nothing is merged on the
// server. A device merges by record identity, and each kind of record has a
// rule that makes applying it twice change nothing:
//
//   record          identity                     merge rule
//   desk_session    session_id                   insert; a lock, send or receipt fills an empty field, never overwrites
//   desk_event      decision_id                  insert if absent (events are append-only, undo is an event)
//   review          card · date (ms) · rating    insert if absent, then replay FSRS for that card from the merged log
//   study_session   date (ms) · mode             insert if absent
//   triage          scope|card                   last writer wins on date; a clear is a dated tombstone
//
// FSRS progress is never sent. It is a pure function of a card's review log,
// so every device that holds the same log computes the same schedule.
//
// Dates travel as integer milliseconds. A review's identity is built from its
// millisecond, so a float round trip that moved it would turn one review into
// two on the way back.

struct SyncRecord: Codable, Sendable, Equatable {
    var type: String

    // desk_session
    var sessionID: String?
    var bankID: String?
    var bankTitle: String?
    var stack: String?
    var mode: String?
    var actorID: String?
    var deviceID: String?
    var createdMs: Int64?
    var lockedAtMs: Int64?
    var sentAtMs: Int64?
    var receiptJSON: String?
    var receiptImportedAtMs: Int64?

    // desk_event (session_id above)
    var decisionID: String?
    var sequence: Int?
    var kind: String?
    var taskID: String?
    var taskRevision: String?
    var subjectID: String?
    var proposalID: String?
    var proposalVisible: Bool?
    var action: String?
    var payloadJSON: String?
    var note: String?
    var decidedAt: String?
    var supersedes: String?

    // review, study_session, triage
    var cardID: String?
    var dateMs: Int64?
    var rating: Int?
    var cardKind: String?
    var studyMode: String?
    var total: Int?
    var correct: Int?
    var track: String?
    var key: String?
    var scope: String?
    var decision: String?
    var digest: String?
    var cleared: Bool?

    init(type: String) { self.type = type }

    enum Kind {
        static let deskSession = "desk_session"
        static let deskEvent = "desk_event"
        static let review = "review"
        static let studySession = "study_session"
        static let triage = "triage"
    }
}

/// What one device sends in one request. The envelope keys are the server's
/// (`desk_api/store.py`); a record's own keys are the app's and only the
/// app reads them, so they stay as Swift spells them. (A snake-case strategy
/// would write `sessionID` as `session_id` and read it back as `sessionId`.)
struct SyncBatch: Codable, Sendable {
    var schema = "monad-defense/sync/1"
    var deviceID: String
    var deviceLabel: String
    var records: [SyncRecord]

    enum CodingKeys: String, CodingKey {
        case schema, records
        case deviceID = "device_id"
        case deviceLabel = "device_label"
    }
}

/// What `GET /api/sync` answers.
struct SyncPage: Codable, Sendable {
    struct Batch: Codable, Sendable {
        let id: String
        let deviceID: String?
        let deviceLabel: String?
        let records: [SyncRecord]

        enum CodingKeys: String, CodingKey {
            case id, records
            case deviceID = "device_id"
            case deviceLabel = "device_label"
        }
    }

    let batches: [Batch]
    let more: Bool
}

extension Date {
    /// Whole milliseconds since 1970: the unit every sync date travels in.
    var syncMs: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }

    init(syncMs: Int64) { self.init(timeIntervalSince1970: Double(syncMs) / 1000) }

    /// Now, cut to a whole millisecond, so a date written here and the same
    /// date read back on another device are the same value.
    static var syncNow: Date { Date(syncMs: Date.now.syncMs) }
}
