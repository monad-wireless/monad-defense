import Foundation

// MARK: - What a bank asks and what an answer changes (IP-172)
//
// A bank is one frozen batch of questions of a single kind, compiled on the Mac
// (`kb desk compile`) and published (`kb desk publish`). Its stack says which
// question; its catalogue kind and view narrow it. These lines say it in words
// on the bank row, so a bank is chosen by its job, not by its id.

struct BankGuide {
    let title: String
    let question: String
    let effect: String
    /// A small set built to explore or practise, not to change the graph at scale.
    let exploratory: Bool

    init(_ bank: DeskBank) {
        let kind = bank.catalogue?.kind
        exploratory = bank.view != nil && bank.view != "active"
        switch bank.stack {
        case .vocabulary:
            title = "Vocabulary" + (kind.map { " · \($0)" } ?? "")
            question = "Is this candidate term a real concept, another name for one, or noise?"
            effect = "Your answers create or extend the curated term notes in the vault."
        case .fidelity where kind == "citation_fidelity":
            title = "Citation fidelity"
            question = "Does the cited paper say what the citing sentence claims it says?"
            effect = "Your answers are recorded and compared with the model's sealed verdict (`kb desk report`)."
        case .fidelity:
            title = "Claim fidelity"
            question = "Does the claim say what its paragraph says?"
            effect = "Your answers are recorded in the Desk ledger; they change no claim."
        case .citation:
            title = "Missing citations"
            question = "Should this paper cite that one?"
            effect = "Your answers label citation proposals; nothing is added to the graph."
        case .reference:
            title = "Reference matching"
            question = "Is this cited reference the same work as this vault paper?"
            effect = "A yes links the citation to the vault paper on the next nightly run."
        case .proposition:
            title = "Same statement"
            question = "Do these two claims from different papers state the same thing?"
            effect = "Yes-pairs become propositions: one statement with its supporting papers."
        }
    }
}
