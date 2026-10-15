import SwiftUI

// MARK: - Desk card faces (IP-161)
//
// The collapsed card answers: what am I judging, which evidence supports it,
// and (assisted only) what did the agent propose. Tap expands to the full
// evidence, what is missing, and the technical identities. A blind card never
// shows a proposal; the bank does not carry one.

struct DeskCardFace: View {
    let bank: DeskBank
    let card: DeskCard
    let expanded: Bool
    var review: DeskTermReview? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text(card.question)
                .font(card.stack == .fidelity ? .subheadline : .headline)
                .foregroundStyle(card.stack == .fidelity ? .secondary : .primary)
            switch card.stack {
            case .vocabulary: VocabularyEvidence(card: card, expanded: expanded)
            case .fidelity: FidelityEvidence(card: card, expanded: expanded, review: review)
            case .citation: CitationEvidence(card: card, expanded: expanded)
            case .reference: ReferenceEvidence(card: card, expanded: expanded)
            case .proposition: PropositionEvidence(card: card, expanded: expanded)
            }
            if bank.mode == .assisted, let proposal = card.proposal {
                ProposalBlock(proposal: proposal)
            }
            if expanded { details }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(card.stack.title, systemImage: card.stack.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            DeskBadge(text: bank.mode.rawValue, tint: bank.mode == .blind ? .purple : .teal)
            if bank.isFixture { DeskBadge(text: "fixture", tint: .gray) }
            Spacer()
            if card.evidence.complete {
                Label("complete", systemImage: "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Label("evidence incomplete", systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if !card.evidence.missing.isEmpty {
                Text("Missing evidence")
                    .font(.caption.weight(.semibold))
                ForEach(card.evidence.missing, id: \.self) { item in
                    Text(item)
                        .font(.caption.monospaced())
                        .foregroundStyle(.orange)
                }
            }
            Group {
                Text("subject \(card.subjectID)")
                Text("task \(card.taskID)")
                Text("revision \(card.taskRevision.prefix(23))…")
                if let rubric = card.rubricVersion { Text("rubric \(rubric)") }
                if let ref = card.proposalRef, bank.mode == .blind {
                    Text("sealed proposal \(ref.proposalID.prefix(8)), revealed only after import")
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
            .textSelection(.enabled)
        }
    }
}

struct DeskBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: .capsule)
    }
}

/// A labelled quote of retained source text, marked with the shared evidence
/// style: a vocabulary term wherever it occurs, or the whole quote when the
/// quote is itself a stored evidence span.
private struct SourceQuote: View {
    enum Mark {
        case none
        case term(String)
        case whole
    }

    let text: String
    let caption: String
    var mark: Mark = .none

    private var attributed: AttributedString {
        switch mark {
        case .none: AttributedString(text)
        case .term(let term): Evidence.marked(text, term: term)
        case .whole: Evidence.marked(text, range: text.startIndex..<text.endIndex, exact: true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(attributed)
                .font(EvidenceStyle.serif)
                .lineSpacing(3)
                .textSelection(.enabled)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

private func pageText(_ value: JSONValue?, verified: Bool?) -> String? {
    guard let page = value?.int else { return nil }
    return verified == true ? "p. \(page)" : "p. \(page) (unverified)"
}

// MARK: Vocabulary

private struct VocabularyEvidence: View {
    let card: DeskCard
    let expanded: Bool

    private var f: DeskEvidence { card.evidence }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(f["name"]?.string ?? card.subjectID)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 10) {
                    Text(f["kind"]?.string ?? "")
                    Text("\(f["papers"]?.int ?? 0) papers")
                    Text("\(f["load_bearing"]?.int ?? 0) load-bearing")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            let excerpts = f["excerpts"]?.array ?? []
            if !excerpts.isEmpty {
                Text("Excerpts")
                    .font(.caption.weight(.semibold))
                ForEach(Array(excerpts.enumerated()), id: \.offset) { _, e in
                    if e["text_available"]?.bool == false {
                        Text("\(e["title"]?.string ?? e["paper_id"]?.string ?? "") — text not retained")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        SourceQuote(
                            text: e["text"]?.string ?? "",
                            caption: [
                                e["title"]?.string ?? e["paper_id"]?.string,
                                e["section"]?.string,
                                pageText(e["page"], verified: false),
                                e["load_bearing"]?.bool == true ? "load-bearing" : nil,
                            ].compactMap { $0 }.joined(separator: " · "),
                            mark: .term(f["name"]?.string ?? ""))
                    }
                }
            }
            if let more = f["excerpts_remaining"]?.int, more > 0 {
                Text("\(more) further matching paragraph(s) are not in this bank.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let near = f["near_matches"]?.array ?? []
            if !near.isEmpty {
                Text("Near matches")
                    .font(.caption.weight(.semibold))
                ForEach(Array(near.enumerated()), id: \.offset) { _, m in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m["name"]?.string ?? m["slug"]?.string ?? "")
                            .font(.subheadline.weight(.medium))
                        if let def = m["definition"]?.string, !def.isEmpty {
                            Text(def)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(expanded ? nil : 3)
                        }
                    }
                }
            }

            // IP-171 Phase 3: other spellings the resolver groups with this one. A proposal, never applied.
            if let cluster = f["cluster"] {
                let members = (cluster["members"]?.array ?? []).filter { $0["slug"]?.string != f["slug"]?.string }
                if !members.isEmpty {
                    Text("Same concept? (\(members.count) other spelling\(members.count == 1 ? "" : "s"))")
                        .font(.caption.weight(.semibold))
                    ForEach(Array((expanded ? members : Array(members.prefix(5))).enumerated()), id: \.offset) { _, m in
                        Text("\(m["name"]?.string ?? m["slug"]?.string ?? "") · \(m["papers"]?.int ?? 0) papers")
                            .font(.caption)
                    }
                }
                if let target = cluster["curated_suggestion"], let name = target["name"]?.string {
                    Text("Suggested curated target: \(name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let papers = f["paper_list"]?.array ?? []
            if !papers.isEmpty {
                Text("Sources (\(papers.count))")
                    .font(.caption.weight(.semibold))
                ForEach(Array((expanded ? papers : Array(papers.prefix(3))).enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: p["load_bearing"]?.bool == true ? "star.fill" : "doc.text")
                            .font(.caption2)
                            .foregroundStyle(p["load_bearing"]?.bool == true ? .orange : .secondary)
                        Text(p["title"]?.string ?? p["paper_id"]?.string ?? "")
                            .font(.caption)
                        if let year = p["year"]?.int {
                            Text(String(year))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !expanded, papers.count > 3 {
                    Text("Tap for all \(papers.count) sources.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: Fidelity

/// The reviewer's marks on the terms a claim mentions, per task, for the
/// sitting. They travel as `term_review` on the fidelity verdict: ledger-only
/// signals for the vocabulary queue, never a vault edit.
@MainActor @Observable
final class DeskTermReview {
    static let order: [String?] = [nil, "fits", "wrong_term"]

    private var marks: [String: [String: String]] = [:]

    static func key(_ term: JSONValue) -> String {
        "\(term["kind"]?.string ?? "term"):\(term["slug"]?.string ?? term["name"]?.string ?? "")"
    }

    func mark(_ task: String, _ term: String) -> String? { marks[task]?[term] }

    func cycle(_ task: String, _ term: String) {
        let now = Self.order.firstIndex(of: mark(task, term)) ?? 0
        marks[task, default: [:]][term] = Self.order[(now + 1) % Self.order.count]
    }

    func payload(_ task: String) -> [String: Any] {
        let review = marks[task] ?? [:]
        return review.isEmpty ? [:] : ["term_review": review]
    }
}

private struct FidelityEvidence: View {
    let card: DeskCard
    let expanded: Bool
    let review: DeskTermReview?

    private var f: DeskEvidence { card.evidence }
    private var claim: String { f["claim_text"]?.string ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("THE CLAIM")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                Text(claim)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                Text([f["producer"]?.string?.replacingOccurrences(of: "_", with: " "), f["claim_type"]?.string]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.35), lineWidth: 1))

            vocabulary
            articles

            if let note = f["locator_note"]?.string {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if expanded {
                FidelityRubric()
            } else {
                Text("Tap the card for whole paragraphs and the rubric.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Where the claim was made

    private var titles: [String: String] {
        Dictionary(
            (f["papers"]?.array ?? []).compactMap { p in
                p["paper_id"]?.string.map { ($0, p["title"]?.string ?? $0) }
            },
            uniquingKeysWith: { a, _ in a })
    }

    @ViewBuilder
    private var articles: some View {
        let origins = f["origins"]?.array ?? []
        let twins = f["same_text"]?.array ?? []
        VStack(alignment: .leading, spacing: 10) {
            // IP-171 citation fidelity: origins carry a role ("citing" or "cited"); the question is
            // whether the cited paper says what the citing sentence attributes to it.
            let isCitation = origins.contains { $0["role"]?.string == "cited" }
            Text(isCitation
                 ? "The citing sentence, then the cited paper"
                 : (twins.isEmpty ? "Where it was made" : "Where it was made · \(origins.count + twins.count) articles"))
                .font(.subheadline.weight(.semibold))
            ForEach(Array(origins.enumerated()), id: \.offset) { _, o in
                ArticleBlock(
                    title: o["paper"]?.string.flatMap { titles[$0] } ?? o["paper"]?.string ?? "Unknown paper",
                    meta: [o["paper"]?.string, o["section"]?.string, pageText(o["page"], verified: o["page_verified"]?.bool)]
                        .compactMap { $0 }.joined(separator: " · "),
                    paragraph: o["text"]?.string ?? "",
                    claim: claim,
                    claimID: f["claim_id"]?.string,
                    badge: o["role"]?.string == "cited"
                        ? "cited paper"
                        : (o["role"]?.string == "citing" ? "citing sentence" : "extracted here"),
                    expanded: expanded,
                    terms: [])
            }
            ForEach(Array(twins.enumerated()), id: \.offset) { _, t in
                ArticleBlock(
                    title: t["title"]?.string ?? t["paper_id"]?.string ?? "Unknown paper",
                    meta: [t["paper_id"]?.string, t["year"]?.int.map(String.init), t["section"]?.string]
                        .compactMap { $0 }.joined(separator: " · "),
                    paragraph: t["text"]?.string ?? "",
                    claim: claim,
                    claimID: t["claim_id"]?.string,
                    badge: "same words",
                    expanded: expanded,
                    terms: t["terms"]?.array ?? [])
            }
            if f["same_text_more"]?.bool == true {
                Text("More papers store these exact words. They are not in this bank.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !twins.isEmpty {
                Label("Same words are not two confirmations. Check each paragraph on its own.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Vocabulary

    @ViewBuilder
    private var vocabulary: some View {
        let terms = f["terms"]?.array ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Vocabulary it mentions")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !terms.isEmpty, review != nil {
                    Text("tap: fits · wrong term")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if terms.isEmpty {
                Text("No vocabulary term is linked to this claim. A missing term is a vocabulary gap, not a fidelity defect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(Array(terms.enumerated()), id: \.offset) { _, term in
                        TermChip(term: term, mark: review?.mark(card.taskID, DeskTermReview.key(term))) {
                            review?.cycle(card.taskID, DeskTermReview.key(term))
                        }
                    }
                }
                ForEach(repeatedNames(terms), id: \.name) { row in
                    Label("“\(row.name)” is in \(row.kinds.count) vocabularies: \(row.kinds.joined(separator: ", ")).",
                          systemImage: "square.on.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func repeatedNames(_ terms: [JSONValue]) -> [(name: String, kinds: [String])] {
        var kinds: [String: [String]] = [:]
        var display: [String: String] = [:]
        for t in terms {
            guard let name = t["name"]?.string, let kind = t["kind"]?.string else { continue }
            let key = name.lowercased()
            display[key] = display[key] ?? name
            if !(kinds[key] ?? []).contains(kind) { kinds[key, default: []].append(kind) }
        }
        return kinds.filter { $0.value.count > 1 }
            .map { (name: display[$0.key] ?? $0.key, kinds: $0.value) }
            .sorted { $0.name < $1.name }
    }
}

/// One article that carries the claim: title, locator, the paragraph with the
/// claim marked, and that record's own terms. The mark is the stored evidence
/// span when the Desk API knows the claim and this is its paragraph; otherwise
/// a word match, underlined dotted, and said so.
private struct ArticleBlock: View {
    @Environment(DeskConnection.self) private var connection
    @Environment(ClaimSpanCache.self) private var spans

    let title: String
    let meta: String
    let paragraph: String
    let claim: String
    var claimID: String? = nil
    let badge: String
    let expanded: Bool
    let terms: [JSONValue]

    var body: some View {
        let exact = claimID.flatMap { spans.range($0, in: paragraph) }
        let hit = exact ?? Evidence.locate(claim, in: paragraph)
        content(hit: hit, exact: exact != nil)
            .task(id: claimID) {
                if let claimID { await spans.load(claimID, via: connection) }
            }
    }

    private func content(hit: Range<String.Index>?, exact: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.turn.down.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(expanded ? nil : 2)
                    Spacer(minLength: 4)
                    DeskBadge(text: badge, tint: badge == "same words" ? .orange : .teal)
                }
                Text(meta)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if paragraph.isEmpty {
                    Text("Paragraph text was not kept.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !expanded, let hit {
                    // No text selection here: a press-and-drag during a swipe
                    // selected paragraph text instead of moving the card.
                    let window = Evidence.sentence(paragraph, around: hit)
                    Text(Evidence.marked(window, range: window.range(of: String(paragraph[hit])), exact: exact))
                        .font(EvidenceStyle.serif)
                        .lineSpacing(3)
                        .lineLimit(6)
                } else {
                    Text(Evidence.marked(paragraph, range: hit, exact: exact))
                        .font(EvidenceStyle.serif)
                        .lineSpacing(3)
                        .lineLimit(expanded ? nil : 4)
                }
                if !paragraph.isEmpty, hit != nil {
                    Text(exact ? "stored evidence span" : "located by matching words")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !terms.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(Array(terms.enumerated()), id: \.offset) { _, t in
                            Text(t["name"]?.string ?? "")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: .capsule)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 12))
    }
}

private struct TermChip: View {
    let term: JSONValue
    let mark: String?
    let toggle: () -> Void

    private var curated: Bool { term["curated"]?.bool == true }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                switch mark {
                case "fits": Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case "wrong_term": Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                default: EmptyView()
                }
                Text(term["name"]?.string ?? "")
                    .font(.caption.weight(.semibold))
                    .strikethrough(mark == "wrong_term")
                Text(term["kind"]?.string ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background((curated ? Theme.accent : Color.gray).opacity(0.12), in: .capsule)
            .overlay(
                Capsule().stroke(
                    curated ? Theme.accent.opacity(0.5) : Color.gray.opacity(0.6),
                    style: StrokeStyle(lineWidth: 1, dash: curated ? [] : [3, 2])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(term["name"]?.string ?? ""), \(term["kind"]?.string ?? ""), \(curated ? "curated" : "candidate")"))
        .accessibilityValue(Text(mark?.replacingOccurrences(of: "_", with: " ") ?? "not reviewed"))
    }
}

private struct FidelityRubric: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rubric (fidelity-rubric/1)")
                .font(.caption.weight(.semibold))
            Text("Faithful: proposition, attribution, conditions, direction and qualifiers kept; wording may differ.")
            Text("Partial: core kept, a hedge, population, condition, quantity or attribution dropped or changed.")
            Text("Wrong: unsupported, or attribution, direction or quantity materially changed.")
            Text("Cannot assess: evidence missing, incomplete, ambiguous or unreadable.")
            Text("Faithfulness to the shown source, not whether the paper is right.")
                .italic()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

// MARK: Citation

private struct CitationEvidence: View {
    let card: DeskCard
    let expanded: Bool

    private var f: DeskEvidence { card.evidence }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            paper("Source", f["source"])
            Image(systemName: "arrow.down")
                .font(.caption)
                .foregroundStyle(.secondary)
            paper("Should it cite", f["target"])
            HStack(spacing: 10) {
                if let rank = f["rank"]?.int { Text("rank \(rank)") }
                if let score = f["score"]?.double { Text(String(format: "score %.3g", score)) }
                if let scorer = f["scorer"]?.string { Text(scorer) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            works("Shared references", f["shared_references"], total: f["shared_references_total"]?.int)
            works("Works linking them", f["linking_works"], total: f["linking_works_total"]?.int)
            Text("Ranked by graph structure only. Judge from the titles, abstracts and reference lists.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func paper(_ label: String, _ value: JSONValue?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value?["title"]?.string ?? value?["paper_id"]?.string ?? "")
                .font(.headline)
            Text([value?["paper_id"]?.string, value?["year"]?.int.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func works(_ label: String, _ value: JSONValue?, total: Int?) -> some View {
        let items = value?.array ?? []
        if !items.isEmpty {
            Text("\(label) (\(total ?? items.count))")
                .font(.caption.weight(.semibold))
            ForEach(Array((expanded ? items : Array(items.prefix(4))).enumerated()), id: \.offset) { _, w in
                Text("• " + (w["title"]?.string ?? w["id"]?.string ?? w.string ?? ""))
                    .font(.caption)
            }
            if let total, total > items.count {
                Text("\(total - items.count) more not in this bank.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Reference (IP-171 Phase 3)

private struct ReferenceEvidence: View {
    let card: DeskCard
    let expanded: Bool

    private var f: DeskEvidence { card.evidence }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            work("Cited as", f["reference"])
            Image(systemName: "equal.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            work("Vault paper", f["vault"])
            HStack(spacing: 10) {
                Text(reason)
                if let gap = f["year_gap"]?.int { Text("year gap \(gap)") }
                if f["authors_compatible"]?.bool == false {
                    Label("first authors differ", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            citers
            Text("Same work means the same paper: a title variant or a preprint of it. Another edition or a sibling paper is a different work.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var reason: String {
        switch f["reason"]?.string {
        case "year_conflict": "same title, years differ"
        case "fuzzy_title": f["score"]?.double.map { String(format: "similar title, score %.2f", $0) } ?? "similar title"
        default: f["reason"]?.string ?? ""
        }
    }

    private func work(_ label: String, _ value: JSONValue?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value?["title"]?.string ?? "")
                .font(.headline)
            Text(
                [
                    value?["year"]?.int.map(String.init),
                    value?["first_author"]?.string,
                    value?["paper_id"]?.string,
                ].compactMap { $0 }.joined(separator: " · ")
            )
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var citers: some View {
        let items = f["reference"]?["citers"]?.array ?? []
        let total = f["reference"]?["citers_total"]?.int ?? items.count
        if !items.isEmpty {
            Text("Cited by (\(total))")
                .font(.caption.weight(.semibold))
            ForEach(Array((expanded ? items : Array(items.prefix(3))).enumerated()), id: \.offset) { _, p in
                Text("• " + [p["title"]?.string, p["year"]?.int.map(String.init)].compactMap { $0 }.joined(separator: ", "))
                    .font(.caption)
            }
            if total > items.count {
                Text("\(total - items.count) more not in this bank.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Proposition (IP-171 Phase 3)

private struct PropositionEvidence: View {
    let card: DeskCard
    let expanded: Bool

    private var f: DeskEvidence { card.evidence }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            claim(f["a"])
            Image(systemName: "equal.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            claim(f["b"])
            let shared = (f["shared_entities"]?.array ?? []).compactMap { $0.string }
            Text(
                [
                    f["cosine"]?.double.map { String(format: "cosine %.2f", $0) },
                    shared.isEmpty ? nil : "both mention " + shared.joined(separator: ", "),
                ].compactMap { $0 }.joined(separator: " · ")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("Same proposition means one paper's statement would count as support for the other's. A narrower or broader claim, another condition, population or value, or the opposite direction is a different proposition.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func claim(_ value: JSONValue?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value?["text"]?.string ?? "")
                .font(.headline)
            if let evidence = value?["evidence"]?.string, !evidence.isEmpty {
                SourceQuote(text: evidence, caption: "stored evidence span", mark: .whole)
                    .lineLimit(expanded ? nil : 4)
            } else {
                Text("evidence sentence not available")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 6) {
                Text([value?["title"]?.string, value?["year"]?.int.map(String.init)].compactMap { $0 }.joined(separator: ", "))
                if value?["attribution"]?.string == "cited" {
                    Label("restates cited work", systemImage: "quote.bubble")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: Proposal (assisted only)

private struct ProposalBlock: View {
    let proposal: DeskProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Agent proposal: \(proposal.action.replacingOccurrences(of: "_", with: " "))", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
            if let definition = proposal.payload["definition"]?.string {
                Text(definition)
                    .font(.callout)
            }
            if let target = proposal.payload["target"], let slug = target["slug"]?.string {
                Text("alias of \(slug)")
                    .font(.callout)
            }
            if let reason = proposal.payload["reason"]?.string {
                Text("reason: \(reason.replacingOccurrences(of: "_", with: " "))")
                    .font(.callout)
            }
            if let rationale = proposal.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.08), in: .rect(cornerRadius: 10))
    }
}
