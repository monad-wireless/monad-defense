import Foundation

// MARK: - Library payloads (IP-172, `monad_knowledge/desk_api/reads.py`)
//
// Offsets `evidenceStart` / `evidenceEnd` count Unicode scalars into the
// paragraph text (Python string indices), never UTF-16 units.

struct PaperSummary: Codable, Hashable, Identifiable, Sendable {
    let key: String
    let title: String
    let year: Int?
    let claims: Int

    var id: String { key }
}

struct ClaimSlots: Codable, Hashable, Sendable {
    let metric: String?
    let value: String?
    let unit: String?
    let condition: String?

    var line: String? {
        guard let metric, !metric.isEmpty else { return nil }
        let amount = [value, unit].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let cond = (condition ?? "").isEmpty ? "" : " · \(condition!)"
        return "\(metric): \(amount)\(cond)"
    }
}

struct ClaimRow: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let text: String?
    let claimType: String?
    let attribution: String?
    let citationMarker: String?
    let evidenceStart: Int?
    let evidenceEnd: Int?
    let slots: ClaimSlots?

    var isCited: Bool { attribution == "cited" }

    enum CodingKeys: String, CodingKey {
        case id, text, slots, attribution
        case claimType = "claim_type"
        case citationMarker = "citation_marker"
        case evidenceStart = "evidence_start"
        case evidenceEnd = "evidence_end"
    }
}

struct ParagraphRow: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let text: String?
    let page: Int?
    let section: String?
    let claims: [ClaimRow]
}

struct PaperDetail: Codable, Hashable, Sendable {
    let key: String
    let title: String
    let year: Int?
    let claims: Int
    let skipReason: String?
    let paragraphs: [ParagraphRow]

    enum CodingKeys: String, CodingKey {
        case key, title, year, claims, paragraphs
        case skipReason = "skip_reason"
    }
}

struct CitedTarget: Codable, Hashable, Sendable {
    let key: String?
    let title: String?
    let inVault: Bool?
    let fidelity: String?
    let fidelityReason: String?

    enum CodingKeys: String, CodingKey {
        case key, title, fidelity
        case inVault = "in_vault"
        case fidelityReason = "fidelity_reason"
    }
}

struct PropositionRef: Codable, Hashable, Sendable {
    let id: String
    let support: Int?
}

struct MentionRef: Codable, Hashable, Sendable {
    let kind: String?
    let name: String?
}

struct ParagraphRef: Codable, Hashable, Sendable {
    let id: String?
    let text: String?
    let page: Int?
    let section: String?
}

struct PaperRef: Codable, Hashable, Sendable {
    let key: String?
    let title: String?
    let year: Int?
}

struct ClaimDetail: Codable, Hashable, Sendable {
    let claim: ClaimRow
    let paragraph: ParagraphRef
    let paper: PaperRef
    let cites: [CitedTarget]
    let propositions: [PropositionRef]
    let mentions: [MentionRef]
}

struct ClaimHit: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let text: String
    let claimType: String?
    let attribution: String?
    let paperKey: String
    let paperTitle: String

    enum CodingKeys: String, CodingKey {
        case id, text, attribution
        case claimType = "claim_type"
        case paperKey = "paper_key"
        case paperTitle = "paper_title"
    }
}

struct SearchResult: Codable, Sendable {
    let papers: [PaperSummary]
    let claims: [ClaimHit]
}

struct PaperList: Codable, Sendable {
    let papers: [PaperSummary]
}

struct BankSummary: Codable, Hashable, Identifiable, Sendable {
    let bankID: String
    let stack: String
    let mode: String
    let kind: String?
    let compiledAt: String?
    let cards: Int
    let etag: String

    var id: String { bankID }

    enum CodingKeys: String, CodingKey {
        case stack, mode, kind, cards, etag
        case bankID = "bank_id"
        case compiledAt = "compiled_at"
    }
}

struct BankList: Codable, Sendable {
    let banks: [BankSummary]
}
