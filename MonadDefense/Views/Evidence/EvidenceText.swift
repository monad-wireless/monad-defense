import SwiftUI
import UIKit

// MARK: - Evidence: a claim marked in the paragraph it came from (IP-172)
//
// The JCDL demo's reading move, as one component: the claim first, then "Show
// where it came from" reveals the source sentence with the evidence marked,
// and the whole paragraph is one more tap away. The Library reader and the
// Desk cards share the mark colour, so a highlighted span means the same
// thing everywhere in the app.

enum EvidenceStyle {
    /// The JCDL mark (#FBE39A) on light ground; a muted gold on dark ground.
    static let mark = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.49, green: 0.40, blue: 0.10, alpha: 1)
                : UIColor(red: 0.984, green: 0.890, blue: 0.604, alpha: 1)
        })
    /// A claim that is not the one in focus, still findable in the paragraph.
    static let faint = Color.yellow.opacity(0.18)
    static let serif = Font.system(.body, design: .serif)
}

/// A span of a paragraph, in Unicode scalars (the server's Python offsets).
struct EvidenceSpan: Hashable, Sendable {
    let start: Int
    let end: Int
    let id: String
}

enum Evidence {
    /// The String range of a scalar-offset span, or nil when it does not fit the text.
    static func range(in text: String, start: Int, end: Int) -> Range<String.Index>? {
        let scalars = text.unicodeScalars
        guard start >= 0, end > start, end <= scalars.count else { return nil }
        let lo = scalars.index(scalars.startIndex, offsetBy: start)
        let hi = scalars.index(lo, offsetBy: end - start)
        return lo..<hi
    }

    /// The paragraph with every span marked; the focused one strong, the others faint.
    /// A span that does not fit the text is skipped: the paragraph still reads.
    static func marked(_ text: String, spans: [EvidenceSpan], focus: String? = nil, linked: Bool = false) -> AttributedString {
        var out = AttributedString(text)
        for span in spans {
            guard let r = range(in: text, start: span.start, end: span.end),
                let lo = AttributedString.Index(r.lowerBound, within: out),
                let hi = AttributedString.Index(r.upperBound, within: out)
            else { continue }
            let strong = focus == nil || focus == span.id
            out[lo..<hi].backgroundColor = strong ? EvidenceStyle.mark : EvidenceStyle.faint
            if linked, let url = URL(string: "claim:\(span.id)") { out[lo..<hi].link = url }
        }
        return out
    }

    /// The sentence that holds the span, with ellipses where the paragraph goes on.
    static func sentence(_ text: String, span: EvidenceSpan) -> String? {
        guard let r = range(in: text, start: span.start, end: span.end) else { return nil }
        return sentence(text, around: r)
    }

    static func sentence(_ text: String, around r: Range<String.Index>) -> String {
        let start = text.range(of: ". ", options: .backwards, range: text.startIndex..<r.lowerBound)?.upperBound
            ?? text.startIndex
        let end = text.range(of: ". ", range: r.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
        let head = start > text.startIndex ? "… " : ""
        let tail = end < text.endIndex ? ". …" : ""
        return head + String(text[start..<end]).trimmingCharacters(in: .whitespaces) + tail
    }

    // MARK: Located by words (no stored offsets)

    /// Where a claim sits in a paragraph when no offsets were stored: the longest
    /// run of the claim's leading words (five or more) that occurs verbatim,
    /// else the sentence sharing the most content words. A locator for the eye,
    /// not a verdict: a paraphrase may land on the wrong sentence.
    static func locate(_ claim: String, in paragraph: String) -> Range<String.Index>? {
        let words = claim.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).split(separator: " ")
        if words.count >= 5 {
            for n in stride(from: words.count, through: 5, by: -1) {
                if let hit = paragraph.range(of: words.prefix(n).joined(separator: " "), options: .caseInsensitive) {
                    return hit
                }
            }
        }
        return closestSentence(paragraph, claim)
    }

    private static func closestSentence(_ paragraph: String, _ claim: String) -> Range<String.Index>? {
        func words(_ s: Substring) -> Set<String> {
            Set(s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 4 })
        }
        let wanted = words(Substring(claim))
        var best: (score: Int, range: Range<String.Index>)?
        var start = paragraph.startIndex
        while start < paragraph.endIndex {
            let stop = paragraph.range(of: ". ", range: start..<paragraph.endIndex)?.upperBound ?? paragraph.endIndex
            let score = words(paragraph[start..<stop]).intersection(wanted).count
            if score > (best?.score ?? 2) { best = (score, start..<stop) }
            start = stop
        }
        return best?.range
    }

    /// The text with one String range marked. `exact` is a stored span; a word
    /// match gets the same colour, underlined, so the two are told apart.
    static func marked(_ text: String, range r: Range<String.Index>?, exact: Bool) -> AttributedString {
        var out = AttributedString(text)
        guard let r, let lo = AttributedString.Index(r.lowerBound, within: out),
            let hi = AttributedString.Index(r.upperBound, within: out)
        else { return out }
        out[lo..<hi].backgroundColor = EvidenceStyle.mark
        if !exact { out[lo..<hi].underlineStyle = Text.LineStyle(pattern: .dot) }
        return out
    }

    /// Every case-insensitive occurrence of `term` marked: a vocabulary term in its excerpt.
    static func marked(_ text: String, term: String) -> AttributedString {
        var out = AttributedString(text)
        let needle = term.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return out }
        var from = text.startIndex
        while let r = text.range(of: needle, options: .caseInsensitive, range: from..<text.endIndex) {
            if let lo = AttributedString.Index(r.lowerBound, within: out),
                let hi = AttributedString.Index(r.upperBound, within: out)
            {
                out[lo..<hi].backgroundColor = EvidenceStyle.mark
            }
            from = r.upperBound
        }
        return out
    }
}

// MARK: - Exact spans fetched for bank cards

/// Banks carry claim text and paragraphs but no offsets. When the Desk API is
/// connected, a card asks for its claim's stored span once; the answer is kept
/// for the app's lifetime. Without a connection, or for a claim the server does
/// not know, the card falls back to the word match.
@MainActor
@Observable
final class ClaimSpanCache {
    struct Span: Equatable {
        let paragraph: String
        let start: Int
        let end: Int
    }

    private(set) var spans: [String: Span] = [:]
    private var asked: Set<String> = []

    /// The stored span, only when it was taken from this very paragraph text:
    /// a bank card may show the claim's paragraph or another paper's.
    func range(_ claimID: String, in paragraph: String) -> Range<String.Index>? {
        guard let s = spans[claimID], s.paragraph == paragraph else { return nil }
        return Evidence.range(in: paragraph, start: s.start, end: s.end)
    }

    func load(_ claimID: String, via connection: DeskConnection) async {
        guard !claimID.isEmpty, connection.isConfigured, asked.insert(claimID).inserted else { return }
        guard let detail = try? await connection.decode(ClaimDetail.self, "/api/claims/\(claimID)"),
            let start = detail.claim.evidenceStart, let end = detail.claim.evidenceEnd
        else { return }
        spans[claimID] = Span(paragraph: detail.paragraph.text ?? "", start: start, end: end)
    }
}

/// Claim first; the source sentence on request; the paragraph after that.
struct SourceReveal: View {
    let claim: String
    let paragraph: String
    let span: EvidenceSpan?
    var label: String? = nil

    @State private var revealed = false
    @State private var whole = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let label {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
            }
            Text(claim)
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            if !revealed {
                Button {
                    withAnimation(.snappy) { revealed = true }
                } label: {
                    Label("Show where it came from", systemImage: "text.magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            } else {
                source
            }
        }
    }

    @ViewBuilder
    private var source: some View {
        let spans = span.map { [$0] } ?? []
        VStack(alignment: .leading, spacing: 10) {
            if paragraph.isEmpty {
                Text("The paragraph text was not kept.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if !whole, let span, let line = Evidence.sentence(paragraph, span: span) {
                let offset = line.hasPrefix("… ") ? 2 : 0
                let local = Evidence.range(in: paragraph, start: span.start, end: span.end).map { String(paragraph[$0]) }
                Text(markedLine(line, evidence: local, offset: offset))
                    .font(EvidenceStyle.serif)
                    .lineSpacing(4)
                Button("Read the whole paragraph") { withAnimation(.snappy) { whole = true } }
                    .font(.callout)
            } else {
                if span == nil {
                    Text("No evidence span is stored for this claim; the paragraph is shown unmarked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(Evidence.marked(paragraph, spans: spans))
                    .font(EvidenceStyle.serif)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func markedLine(_ line: String, evidence: String?, offset: Int) -> AttributedString {
        var out = AttributedString(line)
        if let evidence, let r = out.range(of: evidence) {
            out[r].backgroundColor = EvidenceStyle.mark
        }
        return out
    }
}

/// Claim type and attribution as two small labels, the way the reader scans them.
struct ClaimTags: View {
    let type: String?
    let attribution: String?
    let marker: String?

    var body: some View {
        HStack(spacing: 6) {
            if let type, !type.isEmpty {
                Text(type)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.14), in: .capsule)
                    .foregroundStyle(Theme.accent)
            }
            if attribution == "cited" {
                Text("cited \(marker ?? "")".trimmingCharacters(in: .whitespaces))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.16), in: .capsule)
                    .foregroundStyle(.orange)
            }
        }
    }
}
