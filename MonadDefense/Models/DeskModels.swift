import Foundation

// MARK: - The Desk (IP-161) — banks in, locked decision exports out
//
// A bank (`monad-knowledge/desk-bank/1`) is compiled by `kb desk compile` in
// monad-knowledge and bundled read-only. The phone records append-only
// decision events against it and exports a locked session as
// `monad-defense/desk/1`; `kb desk select` imports that file and answers with
// a receipt (`monad-knowledge/desk-receipt/1`).
//
// This file is Foundation only: decoding, the payload rules and the event
// chain. Persistence lives in `DeskStore`, rendering under `Views/Desk/`.
// The rules mirror `monad_knowledge/domain/desk.py` (`validate_payload`,
// `validate_export`, `reduce_events`); the importer stays the authority.

enum DeskSchema {
    static let bank = "monad-knowledge/desk-bank/1"
    static let export = "monad-defense/desk/1"
    static let receipt = "monad-knowledge/desk-receipt/1"
}

enum DeskStack: String, Codable, Sendable, CaseIterable, Identifiable {
    case vocabulary
    case fidelity
    case citation
    /// IP-171 Phase 3: "is this external reference that vault paper?"
    case reference

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vocabulary: "Vocabulary"
        case .fidelity: "Fidelity"
        case .citation: "Citation"
        case .reference: "Reference"
        }
    }

    var symbol: String {
        switch self {
        case .vocabulary: "character.book.closed"
        case .fidelity: "text.quote"
        case .citation: "arrow.triangle.branch"
        case .reference: "link"
        }
    }
}

enum DeskMode: String, Codable, Sendable {
    case assisted
    case blind
}

// MARK: - JSON values

/// An exact JSON value. Bank fields and proposal payloads are carried as
/// these so nothing is renamed or coerced on the way through.
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var int: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d == d.rounded(): return Int(d)
        default: return nil
        }
    }

    var double: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var array: [JSONValue] {
        if case .array(let a) = self { return a }
        return []
    }

    var isNull: Bool { self == .null }

    /// The value as `JSONSerialization` expects it.
    var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map(\.any)
        case .object(let o): return o.mapValues(\.any)
        }
    }
}

// MARK: - Bank

struct DeskProposal: Codable, Hashable, Sendable {
    let proposalID: String
    let action: String
    let payload: [String: JSONValue]
    let rationale: String?
    let sourceRefs: [String]?

    enum CodingKeys: String, CodingKey {
        case proposalID = "proposal_id"
        case action, payload, rationale
        case sourceRefs = "source_refs"
    }
}

/// What a blind bank carries instead of the proposal: an opaque reference
/// and a commitment, never the action or its payload.
struct DeskProposalRef: Codable, Hashable, Sendable {
    let proposalID: String
    let commitment: String?

    enum CodingKeys: String, CodingKey {
        case proposalID = "proposal_id"
        case commitment
    }
}

struct DeskEvidence: Codable, Hashable, Sendable {
    let fields: [String: JSONValue]
    let complete: Bool
    let missing: [String]
    let evidenceDigest: String

    enum CodingKeys: String, CodingKey {
        case fields, complete, missing
        case evidenceDigest = "evidence_digest"
    }

    subscript(key: String) -> JSONValue? { fields[key] }
}

struct DeskCard: Codable, Hashable, Sendable, Identifiable {
    let taskID: String
    let taskRevision: String
    let subjectID: String
    let stack: DeskStack
    let question: String
    let rubricVersion: String?
    let evidence: DeskEvidence
    let proposal: DeskProposal?
    let proposalRef: DeskProposalRef?
    let history: JSONValue?

    var id: String { taskID }

    /// The proposal the bank pinned, visible or not.
    var pinnedProposalID: String? { proposal?.proposalID ?? proposalRef?.proposalID }

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case taskRevision = "task_revision"
        case subjectID = "subject_id"
        case stack, question
        case rubricVersion = "rubric_version"
        case evidence, proposal
        case proposalRef = "proposal_ref"
        case history
    }
}

struct DeskCatalogueItem: Codable, Hashable, Sendable, Identifiable {
    let name: String
    let slug: String
    let definition: String?
    let aliases: [String]?
    let vaultNote: Bool?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case name, slug, definition, aliases
        case vaultNote = "vault_note"
    }
}

struct DeskCatalogue: Codable, Hashable, Sendable {
    let complete: Bool
    let kind: String?
    let items: [DeskCatalogueItem]
}

struct DeskBank: Codable, Hashable, Sendable, Identifiable {
    let schema: String
    let bankID: String
    let stack: DeskStack
    let mode: DeskMode
    let view: String?
    let queueID: String?
    let compiledAt: String?
    let rubricVersion: String?
    let cards: [DeskCard]
    let catalogue: DeskCatalogue?
    /// The bundled file this bank came from. Not part of the bank.
    var resourceName: String = ""

    var id: String { bankID }

    /// A development bank copied from the monad-knowledge test fixtures.
    var isFixture: Bool { resourceName.localizedCaseInsensitiveContains("fixture") }

    var title: String {
        var parts = [stack.title, mode.rawValue]
        if let kind = catalogue?.kind, stack == .vocabulary { parts.append(kind) }
        if let view, view != "active" { parts.append(view) }
        return parts.joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case bankID = "bank_id"
        case stack, mode, view
        case queueID = "queue_id"
        case compiledAt = "compiled_at"
        case rubricVersion = "rubric_version"
        case cards, catalogue
    }

    /// Decode and check what the phone relies on. An unknown schema, stack or
    /// mode, a duplicate task or a proposal in a blind bank rejects the file.
    static func load(_ data: Data, resourceName: String) throws -> DeskBank {
        let probe = try JSONDecoder().decode(SchemaProbe.self, from: data)
        guard probe.schema == DeskSchema.bank else {
            throw DeskError.unsupportedSchema(probe.schema ?? "none", expected: DeskSchema.bank)
        }
        var bank = try JSONDecoder().decode(DeskBank.self, from: data)
        bank.resourceName = resourceName
        var seen = Set<String>()
        for card in bank.cards {
            guard seen.insert(card.taskID).inserted else { throw DeskError.duplicateTask(card.taskID) }
            guard card.stack == bank.stack else { throw DeskError.stackMismatch(card.taskID) }
            if bank.mode == .blind, card.proposal != nil { throw DeskError.blindProposal(card.taskID) }
        }
        return bank
    }

    private struct SchemaProbe: Decodable { let schema: String? }
}

enum DeskError: LocalizedError, Equatable {
    case unsupportedSchema(String, expected: String)
    case duplicateTask(String)
    case stackMismatch(String)
    case blindProposal(String)
    case sessionLocked
    case nothingToUndo
    case invalidPayload([String])
    case receiptMismatch(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let found, let expected): "Unsupported schema \(found); expected \(expected)."
        case .duplicateTask(let id): "The bank lists task \(id) twice."
        case .stackMismatch(let id): "Task \(id) belongs to another stack than its bank."
        case .blindProposal(let id): "Blind bank carries a proposal on \(id)."
        case .sessionLocked: "This session is locked. Start a new session to decide again."
        case .nothingToUndo: "This card has no decision to undo."
        case .invalidPayload(let problems): problems.joined(separator: "\n")
        case .receiptMismatch(let why): why
        case .saveFailed(let why): "Not saved on the phone: \(why)"
        }
    }
}

// MARK: - Payload rules (mirror of domain/desk.py)

enum DeskRules {
    static let setAsideReasons = ["parser_noise", "outside_scope", "too_broad", "other"]
    static let citationRejectionReasons = ["different_topic", "too_generic", "superseded_work", "other"]
    static let referenceRejectionReasons = ["namesake", "other_version", "other"]
    static let fidelityDefects = [
        "dropped_condition", "dropped_hedge", "population_changed", "quantity_changed",
        "attribution_wrong", "direction_wrong", "unsupported", "corruption",
        "source_anchor_mismatch", "table_parser", "other",
    ]
    static let termVerdicts: Set<String> = ["fits", "wrong_term"]
    static let entityTypes: Set<String> = ["method", "problem", "dataset", "hardware", "dictionary", "topic", "keyword"]
    static let definitionMinChars = 20

    static func actions(_ stack: DeskStack, _ mode: DeskMode) -> Set<String> {
        switch stack {
        case .fidelity: ["faithful", "partial", "wrong", "cannot_assess"]
        case .citation: ["related", "not_related", "cited_but_missed", "cannot_assess"]
        case .reference: ["same_work", "different_work", "cannot_assess"]
        case .vocabulary:
            mode == .assisted
                ? ["promote", "alias", "set_aside", "defer", "needs_research", "restore", "keep_aside"]
                : ["merits_definition", "alias", "set_aside", "defer", "needs_research"]
        }
    }

    static func isSlug(_ value: Any?) -> Bool {
        guard let s = value as? String, !s.isEmpty else { return false }
        return s.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil
    }

    private static func text(_ payload: [String: Any], _ key: String) -> String {
        (payload[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func hasPlaceholder(_ s: String) -> Bool {
        s.range(
            of: #"<[^>]*>|\bTODO\b|\bTBD\b|\bplaceholder\b|\blorem ipsum\b"#,
            options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func validateDefinition(_ p: [String: Any]) -> [String] {
        var problems: [String] = []
        if text(p, "name").isEmpty { problems.append("promote needs a preferred name") }
        if !isSlug(p["slug"]) { problems.append("promote needs a canonical slug (lowercase words joined by hyphens)") }
        if !entityTypes.contains(p["entity_type"] as? String ?? "") {
            problems.append("promote needs an entity_type from the seven vocabularies")
        }
        if let aliases = p["aliases"] as? [Any] {
            if !aliases.allSatisfy({ !(($0 as? String)?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }) {
                problems.append("promote needs an aliases list of non-empty strings (it may be empty)")
            }
        } else {
            problems.append("promote needs an aliases list of non-empty strings (it may be empty)")
        }
        let definition = text(p, "definition")
        if definition.count < definitionMinChars {
            problems.append("promote needs a definition of at least \(definitionMinChars) characters")
        } else if hasPlaceholder(definition) {
            problems.append("the definition still contains placeholder text")
        }
        let refs = p["source_refs"] as? [Any] ?? []
        if refs.isEmpty || !refs.allSatisfy({ !(($0 as? String)?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }) {
            problems.append("promote needs at least one source reference")
        }
        if let scope = p["scope"], !(scope is String), !(scope is NSNull) {
            problems.append("scope must be text when present")
        }
        return problems
    }

    /// The problems that would make the importer block this row. Empty means
    /// the payload is complete for its action.
    static func validate(_ stack: DeskStack, _ mode: DeskMode, action: String, payload p: [String: Any]) -> [String] {
        guard actions(stack, mode).contains(action) else {
            return ["\(action) is not a valid \(mode.rawValue) \(stack.rawValue) action"]
        }
        var problems: [String] = []
        switch stack {
        case .fidelity:
            if action == "partial" || action == "wrong" {
                if !fidelityDefects.contains(p["defect"] as? String ?? "") { problems.append("\(action) needs a defect code") }
                if text(p, "explanation").isEmpty { problems.append("\(action) needs an explanation") }
                if text(p, "source_ref").isEmpty { problems.append("\(action) needs a source reference") }
            }
            if action == "faithful", (p["source_refs"] as? [Any] ?? []).isEmpty {
                problems.append("faithful needs the source references that were read")
            }
            if action == "cannot_assess", text(p, "reason").isEmpty { problems.append("cannot_assess needs a reason") }
            // Mirrors domain/desk.py:validate_term_review.
            if let review = p["term_review"] {
                let marks = review as? [String: String] ?? [:]
                if marks.isEmpty || !marks.allSatisfy({ $0.key.contains(":") && termVerdicts.contains($0.value) }) {
                    problems.append("term_review maps '<kind>:<term>' to fits or wrong_term")
                }
            }
        case .citation:
            if action == "not_related" {
                let reason = p["reason"] as? String ?? ""
                if !citationRejectionReasons.contains(reason) {
                    problems.append("not_related needs a reason")
                } else if reason == "other", text(p, "explanation").isEmpty {
                    problems.append("not_related with reason 'other' needs an explanation")
                }
            }
            if action == "cited_but_missed", text(p, "where").isEmpty {
                problems.append("cited_but_missed needs where the source cites the target (reference number or page)")
            }
            if action == "cannot_assess", text(p, "reason").isEmpty { problems.append("cannot_assess needs a reason") }
        case .reference:
            if action == "different_work" {
                let reason = p["reason"] as? String ?? ""
                if !referenceRejectionReasons.contains(reason) {
                    problems.append("different_work needs a reason")
                } else if reason == "other", text(p, "explanation").isEmpty {
                    problems.append("different_work with reason 'other' needs an explanation")
                }
            }
            if action == "cannot_assess", text(p, "reason").isEmpty { problems.append("cannot_assess needs a reason") }
        case .vocabulary:
            switch action {
            case "promote":
                problems += validateDefinition(p)
            case "alias":
                let target = p["target"] as? [String: Any]
                if mode == .assisted {
                    if target == nil || !isSlug(target?["slug"]) || (target?["entity_type"] as? String ?? "").isEmpty {
                        problems.append("alias needs a target from the compiled catalogue")
                    }
                    if text(p, "explanation").isEmpty {
                        problems.append("alias needs an explanation of why the surface forms denote one concept")
                    }
                } else {
                    let slug = (target?["slug"] as? String) ?? ""
                    let intended = (target?["intended"] as? String) ?? ""
                    if slug.isEmpty, intended.trimmingCharacters(in: .whitespaces).isEmpty {
                        problems.append("alias needs a target slug or an intended identity")
                    }
                }
            case "set_aside":
                if !setAsideReasons.contains(p["reason"] as? String ?? "") { problems.append("set_aside needs a reason") }
            case "needs_research":
                if text(p, "question").isEmpty { problems.append("needs_research needs an explicit question or the missing evidence") }
            case "restore", "keep_aside":
                if text(p, "suppression_decision_id").isEmpty {
                    problems.append("\(action) needs a reference to the suppression being lifted or reaffirmed")
                }
            default:
                break
            }
        }
        return problems
    }
}

// MARK: - Event chain

/// One append-only event, as the export carries it. A task's events form one
/// linear chain: every new event supersedes the task's current terminal, so
/// the importer never sees two unlinked terminals (a conflict that blocks the
/// task). A retraction ends the chain with no effective decision.
struct DeskEventRecord: Hashable, Sendable {
    let decisionID: String
    let sequence: Int
    let kind: String
    let taskID: String
    let taskRevision: String
    let subjectID: String
    let proposalID: String?
    let proposalVisible: Bool
    let action: String
    let payloadJSON: String
    let note: String?
    /// ISO 8601, stored once and re-emitted verbatim; the importer compares
    /// re-imported events by value.
    let decidedAt: String
    let supersedes: String?

    var isRetraction: Bool { kind == "retract" }
}

enum DeskLedger {
    static func newID() -> String { UUID().uuidString.lowercased() }

    static func timestamp(_ date: Date = .now) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static func terminal(_ events: [DeskEventRecord], task: String) -> DeskEventRecord? {
        events.filter { $0.taskID == task }.max { $0.sequence < $1.sequence }
    }

    /// The decision that counts for a task, nil when undecided or retracted.
    static func effective(_ events: [DeskEventRecord], task: String) -> DeskEventRecord? {
        guard let t = terminal(events, task: task), !t.isRetraction else { return nil }
        return t
    }

    static func payloadJSON(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func decision(
        on card: DeskCard, bank: DeskBank, action: String, payload: [String: Any], note: String?,
        after events: [DeskEventRecord], date: Date = .now
    ) throws -> DeskEventRecord {
        let problems = DeskRules.validate(bank.stack, bank.mode, action: action, payload: payload)
        guard problems.isEmpty else { throw DeskError.invalidPayload(problems) }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return DeskEventRecord(
            decisionID: newID(),
            sequence: (events.map(\.sequence).max() ?? 0) + 1,
            kind: "decision",
            taskID: card.taskID,
            taskRevision: card.taskRevision,
            subjectID: card.subjectID,
            proposalID: card.pinnedProposalID,
            proposalVisible: bank.mode == .assisted && card.proposal != nil,
            action: action,
            payloadJSON: try payloadJSON(payload),
            note: trimmed.isEmpty ? nil : trimmed,
            decidedAt: timestamp(date),
            supersedes: terminal(events, task: card.taskID)?.decisionID
        )
    }

    /// Undo: a retraction event that supersedes the effective decision. The
    /// original event stays in the record.
    static func retraction(of card: DeskCard, after events: [DeskEventRecord], date: Date = .now) throws -> DeskEventRecord {
        guard let target = effective(events, task: card.taskID) else { throw DeskError.nothingToUndo }
        return DeskEventRecord(
            decisionID: newID(),
            sequence: (events.map(\.sequence).max() ?? 0) + 1,
            kind: "retract",
            taskID: target.taskID,
            taskRevision: target.taskRevision,
            subjectID: target.subjectID,
            proposalID: target.proposalID,
            proposalVisible: target.proposalVisible,
            action: target.action,
            payloadJSON: "{}",
            note: nil,
            decidedAt: timestamp(date),
            supersedes: target.decisionID
        )
    }

    /// The `monad-defense/desk/1` envelope for a locked session.
    static func export(
        bank: DeskBank, sessionID: String, actorID: String, deviceID: String,
        events: [DeskEventRecord], exportedAt: String
    ) throws -> Data {
        let decisions: [[String: Any]] = try events.sorted { $0.sequence < $1.sequence }.map { e in
            let payload = try JSONSerialization.jsonObject(with: Data(e.payloadJSON.utf8))
            return [
                "decision_id": e.decisionID,
                "sequence": e.sequence,
                "kind": e.kind,
                "task_id": e.taskID,
                "task_revision": e.taskRevision,
                "subject_id": e.subjectID,
                "proposal_id": e.proposalID ?? NSNull(),
                "proposal_visible": e.proposalVisible,
                "action": e.action,
                "payload": payload,
                "note": e.note ?? NSNull(),
                "decided_at": e.decidedAt,
                "supersedes": e.supersedes ?? NSNull(),
            ]
        }
        let envelope: [String: Any] = [
            "schema": DeskSchema.export,
            "bank_id": bank.bankID,
            "session_id": sessionID,
            "actor_id": actorID,
            "device_id": deviceID,
            "mode": bank.mode.rawValue,
            "exported_at": exportedAt,
            "session_locked": true,
            "decisions": decisions,
        ]
        return try JSONSerialization.data(
            withJSONObject: envelope, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }
}

// MARK: - Receipt

struct DeskReceipt: Codable, Hashable, Sendable {
    let schema: String
    let receiptID: String
    let bankID: String
    let sessionID: String
    let issuedAt: String
    let rows: [Row]
    let summary: Summary

    struct Row: Codable, Hashable, Sendable {
        let decisionID: String
        let state: String
        let operationID: String?
        let blockers: [JSONValue]?

        enum CodingKeys: String, CodingKey {
            case decisionID = "decision_id"
            case state
            case operationID = "operation_id"
            case blockers
        }
    }

    struct Summary: Codable, Hashable, Sendable {
        let states: [String: Int]
        let recorded: Int
        let complete: Bool
        let recoveryOperations: [String]

        enum CodingKeys: String, CodingKey {
            case states, recorded, complete
            case recoveryOperations = "recovery_operations"
        }
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case receiptID = "receipt_id"
        case bankID = "bank_id"
        case sessionID = "session_id"
        case issuedAt = "issued_at"
        case rows, summary
    }

    static func load(_ data: Data) throws -> DeskReceipt {
        let receipt = try JSONDecoder().decode(DeskReceipt.self, from: data)
        guard receipt.schema == DeskSchema.receipt else {
            throw DeskError.unsupportedSchema(receipt.schema, expected: DeskSchema.receipt)
        }
        return receipt
    }

    /// Plain words for a journal state.
    static func label(_ state: String) -> String {
        switch state {
        case "recorded_only": "recorded"
        case "applied": "applied"
        case "vault_written_sync_pending": "note written, sync pending"
        case "blocked": "blocked"
        case "failed_before_write": "failed before write"
        case "reconciliation_required": "needs reconciliation"
        case "planned": "planned"
        default: state
        }
    }
}
