import SwiftUI

// MARK: - A Desk sitting on the triage deck (IP-161)
//
// Gestures are shortcuts to semantic actions, per stack and mode:
//
//   stack / mode          right               left                    up (sheet)                 hold
//   vocabulary assisted   define              set aside (reason)      resolve: define/alias/research   defer
//   vocabulary blind      merits definition   set aside (reason)      alias or research          defer
//   vocabulary set-aside  restore             keep aside              needs research             defer
//   fidelity              faithful            wrong (defect)          partial (defect)           cannot assess (reason)
//   citation              related             not related (reason)    cited but missed (where)   cannot assess (reason)
//   reference             same work           different work (reason) other version              cannot assess (reason)
//
// Right on an assisted vocabulary card accepts the shown definition only when
// the agent proposed one that passes the rules; otherwise it opens the editor.

struct DeskDeckView: View {
    @Environment(DeskStore.self) private var desk

    let bank: DeskBank
    let session: DeskSession
    /// Frozen when the sitting opens: the cards without an effective decision.
    let cards: [DeskCard]

    /// Term marks for this sitting; they ride on the next fidelity verdict.
    @State private var review = DeskTermReview()

    var body: some View {
        TriageDeckView(spec: spec)
    }

    private var spec: TriageSpec<DeskCard> {
        let actions = DeskActions(desk: desk, bank: bank, session: session, review: review)
        let (right, left, up, hold) = actions.gestures()
        return TriageSpec(
            title: bank.title,
            cards: cards,
            render: { [review] card, expanded in
                AnyView(DeskCardFace(bank: bank, card: card, expanded: expanded, review: review))
            },
            right: right,
            left: left,
            up: up,
            longPress: hold,
            finishedHint: "Every task in this sitting has a disposition. Lock and export the session from the Desk.",
            upOpensNote: false,
            undo: { card in actions.undo(card) },
            noun: "task(s)"
        )
    }
}

@MainActor
private struct DeskActions {
    let desk: DeskStore
    let bank: DeskBank
    let session: DeskSession
    let review: DeskTermReview

    typealias Action = TriageAction<DeskCard>

    /// Every save goes through here, so a fidelity verdict from a button, a
    /// swipe or an editor sheet carries the same term marks.
    func commit(_ card: DeskCard) -> DeskCommit {
        { action, payload, note in
            var payload = payload
            if bank.stack == .fidelity {
                payload.merge(review.payload(card.taskID)) { mine, _ in mine }
            }
            do {
                try desk.record(session, bank: bank, card: card, action: action, payload: payload, note: note)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

    func direct(_ card: DeskCard, _ action: String, _ payload: [String: Any], _ note: String) -> TriageOutcome {
        if let problem = commit(card)(action, payload, note) { return .failed(problem) }
        return .saved
    }

    func undo(_ card: DeskCard) -> TriageOutcome {
        do {
            try desk.undo(session, card: card)
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func sheet(_ build: @escaping (_ finish: @escaping () -> Void) -> some View) -> TriageOutcome {
        .edit { finish in AnyView(build(finish)) }
    }

    func gestures() -> (Action, Action, Action, Action) {
        switch bank.stack {
        case .vocabulary: vocabulary()
        case .fidelity: fidelity()
        case .citation: citation()
        case .reference: reference()
        }
    }

    private func reasonSheet(_ card: DeskCard, title: String, action: String, reasons: [String], explanationKey: String?, note: String) -> TriageOutcome {
        let commit = commit(card)
        return sheet { finish in
            DeskReasonEditor(
                title: title, action: action, reasons: reasons, explanationKey: explanationKey,
                commit: commit, finish: finish, note: note)
        }
    }

    private func textSheet(_ card: DeskCard, title: String, action: String, key: String, prompt: String, footer: String, note: String) -> TriageOutcome {
        let commit = commit(card)
        return sheet { finish in
            DeskTextSheet(
                title: title, action: action, key: key, prompt: prompt, footer: footer, note: note,
                commit: commit, finish: finish)
        }
    }

    private var defer_: Action {
        Action(label: "Defer", symbol: "clock.arrow.circlepath", tint: .blue) { card, note in
            direct(card, "defer", [:], note)
        }
    }

    // MARK: Vocabulary

    private func vocabulary() -> (Action, Action, Action, Action) {
        let setAside = Action(label: "Set aside", symbol: "archivebox", tint: .red) { card, note in
            reasonSheet(card, title: "Set aside", action: "set_aside", reasons: DeskRules.setAsideReasons, explanationKey: nil, note: note)
        }
        if bank.mode == .assisted, bank.view == "set-aside" || bank.view == "changed" {
            return suppressed()
        }
        let resolveLabel = bank.mode == .assisted ? "Resolve" : "Alias / research"
        let resolve = Action(label: resolveLabel, symbol: "arrow.triangle.merge", tint: .orange) { card, note in
            let commit = commit(card)
            return sheet { finish in DeskResolveSheet(card: card, bank: bank, note: note, commit: commit, finish: finish) }
        }
        if bank.mode == .blind {
            let merits = Action(label: "Merits definition", symbol: "checkmark.seal", tint: .green) { card, note in
                direct(card, "merits_definition", [:], note)
            }
            return (merits, setAside, resolve, defer_)
        }
        let define = Action(label: "Define", symbol: "checkmark.seal", tint: .green) { card, note in
            if let p = card.proposal, p.action == "promote" {
                let payload = p.payload.mapValues(\.any)
                if DeskRules.validate(bank.stack, bank.mode, action: "promote", payload: payload).isEmpty {
                    return direct(card, "promote", payload, note)
                }
            }
            let commit = commit(card)
            return sheet { finish in
                NavigationStack { DeskDefinitionEditor(card: card, commit: commit, finish: finish, note: note) }
            }
        }
        return (define, setAside, resolve, defer_)
    }

    /// The set-aside and changed views ask another question: lift or keep the suppression.
    private func suppressed() -> (Action, Action, Action, Action) {
        func suppression(_ card: DeskCard) -> String? {
            guard card.history?["state"]?.string == "set_aside" else { return nil }
            return card.history?["decision_id"]?.string
        }
        let restore = Action(label: "Restore", symbol: "arrow.uturn.left.circle", tint: .green) { card, note in
            guard let id = suppression(card) else { return .failed("This card carries no suppression to lift.") }
            return direct(card, "restore", ["suppression_decision_id": id], note)
        }
        let keep = Action(label: "Keep aside", symbol: "archivebox", tint: .red) { card, note in
            guard let id = suppression(card) else { return .failed("This card carries no suppression to keep.") }
            return direct(card, "keep_aside", ["suppression_decision_id": id], note)
        }
        let research = Action(label: "Research", symbol: "magnifyingglass", tint: .orange) { card, note in
            textSheet(
                card, title: "Needs research", action: "needs_research", key: "question",
                prompt: "The question, or the evidence that is missing",
                footer: "Goes to the research queue. It never counts as a resolved term.", note: note)
        }
        return (restore, keep, research, defer_)
    }

    // MARK: Fidelity

    private func fidelity() -> (Action, Action, Action, Action) {
        let faithful = Action(label: "Faithful", symbol: "checkmark.circle", tint: .green) { card, note in
            let refs = (card.evidence["origins"]?.array ?? []).compactMap { $0["paragraph_id"]?.string }
            guard !refs.isEmpty else { return .failed("No source paragraph is identified. Record cannot assess.") }
            return direct(card, "faithful", ["source_refs": refs], note)
        }
        func defect(_ action: String) -> (DeskCard, String) -> TriageOutcome {
            { card, note in
                let commit = commit(card)
                return sheet { finish in DeskDefectEditor(action: action, card: card, commit: commit, finish: finish, note: note) }
            }
        }
        let wrong = Action(label: "Wrong", symbol: "xmark.circle", tint: .red, perform: defect("wrong"))
        let partial = Action(label: "Partial", symbol: "circle.lefthalf.filled", tint: .orange, perform: defect("partial"))
        let cannot = Action(label: "Cannot assess", symbol: "questionmark.circle", tint: .blue) { card, note in
            textSheet(
                card, title: "Cannot assess", action: "cannot_assess", key: "reason",
                prompt: "What prevents a verdict?",
                footer: "Never counted as faithful, never dropped from the sample.", note: note)
        }
        return (faithful, wrong, partial, cannot)
    }

    // MARK: Citation

    private func citation() -> (Action, Action, Action, Action) {
        let related = Action(label: "Related", symbol: "link.badge.plus", tint: .green) { card, note in
            direct(card, "related", [:], note)
        }
        let unrelated = Action(label: "Not related", symbol: "link.badge.minus", tint: .red) { card, note in
            reasonSheet(
                card, title: "Not related", action: "not_related", reasons: DeskRules.citationRejectionReasons,
                explanationKey: "explanation", note: note)
        }
        let missed = Action(label: "Cited, missed", symbol: "doc.text.magnifyingglass", tint: .orange) { card, note in
            textSheet(
                card, title: "Cited but missed", action: "cited_but_missed", key: "where",
                prompt: "Reference number or page where the source cites it",
                footer: "The graph lost this edge. It goes to the parser repair list.", note: note)
        }
        let cannot = Action(label: "Cannot assess", symbol: "questionmark.circle", tint: .blue) { card, note in
            textSheet(
                card, title: "Cannot assess", action: "cannot_assess", key: "reason",
                prompt: "What prevents a verdict?", footer: "For example: no full text on hand.", note: note)
        }
        return (related, unrelated, missed, cannot)
    }

    // MARK: Reference

    /// IP-171 Phase 3. The verdict is recorded only; the reference resolver in
    /// monad-knowledge reads it back on every run, so it survives a rebuilt graph.
    private func reference() -> (Action, Action, Action, Action) {
        let same = Action(label: "Same work", symbol: "link", tint: .green) { card, note in
            direct(card, "same_work", [:], note)
        }
        let different = Action(label: "Different work", symbol: "link.badge.minus", tint: .red) { card, note in
            reasonSheet(
                card, title: "Different work", action: "different_work", reasons: DeskRules.referenceRejectionReasons,
                explanationKey: "explanation", note: note)
        }
        let version = Action(label: "Other version", symbol: "doc.on.doc", tint: .orange) { card, note in
            direct(card, "different_work", ["reason": "other_version"], note)
        }
        let cannot = Action(label: "Cannot assess", symbol: "questionmark.circle", tint: .blue) { card, note in
            textSheet(
                card, title: "Cannot assess", action: "cannot_assess", key: "reason",
                prompt: "What prevents a verdict?", footer: "For example: the reference list is not on hand.", note: note)
        }
        return (same, different, version, cannot)
    }
}
