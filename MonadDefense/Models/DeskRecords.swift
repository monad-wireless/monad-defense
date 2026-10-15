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

    var isLocked: Bool { lockedAt != nil }
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
}
