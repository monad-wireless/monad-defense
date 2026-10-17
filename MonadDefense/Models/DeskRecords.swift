import Foundation
import SwiftData

// MARK: - Desk persistence (IP-161)
//
// Separate from `TriageDecision` on purpose: the IP-151 stacks keep their
// keys and enum, and nothing here is pruned when a card leaves a bundled bank.
// Events are append-only; undo is a retraction event, never a delete.

@Model
final class DeskSession {
    @Attribute(.unique) var sessionID: String
    var bankID: String
    var bankTitle: String
    var stackRaw: String
    var modeRaw: String
    var actorID: String
    var deviceID: String
    var created: Date
    var lockedAt: Date?
    /// The receipt `kb desk select` returned for this session, verbatim.
    var receiptJSON: String?
    var receiptImportedAt: Date?
    /// When the locked session reached the Desk API inbox (IP-172). Optional, so
    /// stores from before IP-172 open by lightweight migration.
    var sentAt: Date?

    init(bank: DeskBank, actorID: String, deviceID: String, date: Date = .now) {
        self.sessionID = DeskLedger.newID()
        self.bankID = bank.bankID
        self.bankTitle = bank.title
        self.stackRaw = bank.stack.rawValue
        self.modeRaw = bank.mode.rawValue
        self.actorID = actorID
        self.deviceID = deviceID
        self.created = date
    }

    /// A session another device recorded, as its sync record carried it.
    init(synced r: SyncRecord) {
        self.sessionID = r.sessionID ?? DeskLedger.newID()
        self.bankID = r.bankID ?? ""
        self.bankTitle = r.bankTitle ?? ""
        self.stackRaw = r.stack ?? ""
        self.modeRaw = r.mode ?? ""
        self.actorID = r.actorID ?? ""
        self.deviceID = r.deviceID ?? ""
        self.created = r.createdMs.map(Date.init(syncMs:)) ?? .now
        self.lockedAt = r.lockedAtMs.map(Date.init(syncMs:))
        self.sentAt = r.sentAtMs.map(Date.init(syncMs:))
        self.receiptJSON = r.receiptJSON
        self.receiptImportedAt = r.receiptImportedAtMs.map(Date.init(syncMs:))
    }

    var isLocked: Bool { lockedAt != nil }

    var syncRecord: SyncRecord {
        var r = SyncRecord(type: SyncRecord.Kind.deskSession)
        r.sessionID = sessionID
        r.bankID = bankID
        r.bankTitle = bankTitle
        r.stack = stackRaw
        r.mode = modeRaw
        r.actorID = actorID
        r.deviceID = deviceID
        r.createdMs = created.syncMs
        r.lockedAtMs = lockedAt?.syncMs
        r.sentAtMs = sentAt?.syncMs
        r.receiptJSON = receiptJSON
        r.receiptImportedAtMs = receiptImportedAt?.syncMs
        return r
    }

    /// The newest moment this session changed, for "what to push".
    var lastChanged: Date {
        [created, lockedAt, sentAt, receiptImportedAt].compactMap { $0 }.max() ?? created
    }

    /// Fill what another device learned and this one has not: a lock, a send,
    /// a receipt. Each is set once and never changes, so nothing is overwritten.
    /// Returns whether anything changed.
    func absorb(_ r: SyncRecord) -> Bool {
        var changed = false
        if lockedAt == nil, let ms = r.lockedAtMs { lockedAt = Date(syncMs: ms); changed = true }
        if sentAt == nil, let ms = r.sentAtMs { sentAt = Date(syncMs: ms); changed = true }
        if receiptJSON == nil, let json = r.receiptJSON {
            receiptJSON = json
            receiptImportedAt = r.receiptImportedAtMs.map(Date.init(syncMs:)) ?? .now
            changed = true
        }
        return changed
    }
    var stack: DeskStack? { DeskStack(rawValue: stackRaw) }
    var mode: DeskMode? { DeskMode(rawValue: modeRaw) }

    var receipt: DeskReceipt? {
        guard let receiptJSON else { return nil }
        return try? DeskReceipt.load(Data(receiptJSON.utf8))
    }
}

@Model
final class DeskDecisionEvent {
    @Attribute(.unique) var decisionID: String
    var sessionID: String
    var sequence: Int
    var kind: String
    var taskID: String
    var taskRevision: String
    var subjectID: String
    var proposalID: String?
    var proposalVisible: Bool
    var action: String
    var payloadJSON: String
    var note: String?
    var decidedAt: String
    var supersedes: String?

    init(sessionID: String, record r: DeskEventRecord) {
        self.decisionID = r.decisionID
        self.sessionID = sessionID
        self.sequence = r.sequence
        self.kind = r.kind
        self.taskID = r.taskID
        self.taskRevision = r.taskRevision
        self.subjectID = r.subjectID
        self.proposalID = r.proposalID
        self.proposalVisible = r.proposalVisible
        self.action = r.action
        self.payloadJSON = r.payloadJSON
        self.note = r.note
        self.decidedAt = r.decidedAt
        self.supersedes = r.supersedes
    }

    var record: DeskEventRecord {
        DeskEventRecord(
            decisionID: decisionID, sequence: sequence, kind: kind, taskID: taskID,
            taskRevision: taskRevision, subjectID: subjectID, proposalID: proposalID,
            proposalVisible: proposalVisible, action: action, payloadJSON: payloadJSON,
            note: note, decidedAt: decidedAt, supersedes: supersedes)
    }

    var syncRecord: SyncRecord {
        var r = SyncRecord(type: SyncRecord.Kind.deskEvent)
        r.sessionID = sessionID
        r.decisionID = decisionID
        r.sequence = sequence
        r.kind = kind
        r.taskID = taskID
        r.taskRevision = taskRevision
        r.subjectID = subjectID
        r.proposalID = proposalID
        r.proposalVisible = proposalVisible
        r.action = action
        r.payloadJSON = payloadJSON
        r.note = note
        r.decidedAt = decidedAt
        r.supersedes = supersedes
        return r
    }

    /// The event another device recorded. Nil when a field the ledger needs is missing.
    static func synced(_ r: SyncRecord) -> DeskDecisionEvent? {
        guard let sessionID = r.sessionID, let decisionID = r.decisionID, let sequence = r.sequence,
            let kind = r.kind, let taskID = r.taskID, let taskRevision = r.taskRevision,
            let subjectID = r.subjectID, let action = r.action, let payloadJSON = r.payloadJSON,
            let decidedAt = r.decidedAt
        else { return nil }
        return DeskDecisionEvent(
            sessionID: sessionID,
            record: DeskEventRecord(
                decisionID: decisionID, sequence: sequence, kind: kind, taskID: taskID,
                taskRevision: taskRevision, subjectID: subjectID, proposalID: r.proposalID,
                proposalVisible: r.proposalVisible ?? false, action: action, payloadJSON: payloadJSON,
                note: r.note, decidedAt: decidedAt, supersedes: r.supersedes))
    }
}
