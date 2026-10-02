import SwiftUI
import UIKit

// MARK: - Prose with inline maths
//
// Guide prose carries `$…$` maths inside sentences ("the knee $K$ sets…"). A
// display formula can be laid out as views, but a sentence has to wrap, and
// only `Text` wraps. So inline maths is parsed with the same `MathParser` as
// display maths and flattened into concatenated `Text`: italic serif for
// variables, baseline-shifted smaller runs for scripts, a slash for fractions.
// That loses the stacked fraction and keeps the sentence readable, which is
// the trade a sentence needs.

enum InlineMath {
    /// `source` with `$…$` maths and `**bold**`, as one wrapping `Text`.
    static func text(_ source: String, size: CGFloat) -> Text {
        var out = Text("")
        for (i, part) in split(source).enumerated() {
            if i % 2 == 1 {
                out = cat(out, math(part, size: size))
            } else if !part.isEmpty {
                out = cat(out, Text(cardMarkdownInline(part)).font(.system(size: size)))
            }
        }
        return out
    }

    /// Join styled runs into one wrapping `Text`. iOS 26 deprecates `Text + Text`
    /// in favour of interpolation, which keeps each run's font and offset.
    private static func cat(_ parts: Text...) -> Text {
        parts.reduce(Text("")) { Text("\($0)\($1)") }
    }

    /// Alternating prose / maths segments; an unpaired `$` stays prose.
    static func split(_ source: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var previous: Character?
        for c in source {
            if c == "$", previous != "\\" {
                parts.append(current)
                current = ""
            } else {
                current.append(c)
            }
            previous = c
        }
        parts.append(current)
        if parts.count % 2 == 0 {
            // Odd number of dollars: glue the stray one back on.
            let last = parts.removeLast()
            parts[parts.count - 1] += "$" + last
        }
        return parts
    }

    static func math(_ latex: String, size: CGFloat) -> Text {
        guard let node = MathParser.parse(latex) else {
            return Text(latex).font(.system(size: size * 0.9, design: .monospaced))
        }
        return render(node, size: size)
    }

    /// `shift` is the baseline offset accumulated from enclosing scripts. Each
    /// run carries its absolute offset, because an offset applied to a joined
    /// `Text` does not compound with the offsets of the runs inside it.
    private static func render(_ node: MathNode, size: CGFloat, shift: CGFloat = 0) -> Text {
        switch node {
        case .empty:
            return Text("")
        case .space(let width):
            return Text(width >= 0.9 ? "\u{2003}" : width > 0.2 ? " " : "\u{2009}").font(.system(size: size))
        case .atom(let s, let style):
            return atom(s, style: style, size: size).baselineOffset(shift)
        case .row(let children):
            return children.reduce(Text("")) { cat($0, render($1, size: size, shift: shift)) }
        case .accent(let kind, let base):
            return render(appendMark(base, kind), size: size, shift: shift)
        case .scripted(let base, let sub, let sup):
            var t = render(base, size: size, shift: shift)
            let small = max(size * 0.72, 10)
            if let sub { t = cat(t, render(sub, size: small, shift: shift - size * 0.22)) }
            if let sup { t = cat(t, render(sup, size: small, shift: shift + size * 0.38)) }
            return t
        case .fraction(let num, let den):
            let slash = Text("/").font(.system(size: size, design: .serif)).baselineOffset(shift)
            return cat(group(num, size: size, shift: shift), slash, group(den, size: size, shift: shift))
        case .radical(let body):
            let root = Text("\u{221A}").font(.system(size: size, design: .serif)).baselineOffset(shift)
            return cat(root, group(body, size: size, shift: shift, force: true))
        case .bigOperator(let glyph, let lower, let upper):
            var t = Text(glyph).font(.system(size: size * 1.05, design: .serif)).baselineOffset(shift)
            let small = max(size * 0.68, 10)
            if let lower { t = cat(t, render(lower, size: small, shift: shift - size * 0.22)) }
            if let upper { t = cat(t, render(upper, size: small, shift: shift + size * 0.38)) }
            return t
        }
    }

    private static func atom(_ s: String, style: MathAtomStyle, size: CGFloat) -> Text {
        switch style {
        case .variable:
            return Text(s).font(.system(size: size, design: .serif)).italic()
        case .bold:
            return Text(s).font(.system(size: size, weight: .bold, design: .serif))
        case .relation:
            let glyph = s == "-" ? "\u{2212}" : s
            return Text("\u{2009}\(glyph)\u{2009}").font(.system(size: size, design: .serif))
        case .upright, .punctuation:
            return Text(s).font(.system(size: size, design: .serif))
        }
    }

    /// Parenthesise a fraction part unless it is a single symbol.
    private static func group(_ node: MathNode, size: CGFloat, shift: CGFloat, force: Bool = false) -> Text {
        if !force, case .atom = node { return render(node, size: size, shift: shift) }
        if !force, case .row(let children) = node, children.count == 1 { return render(node, size: size, shift: shift) }
        let paren = { (s: String) in Text(s).font(.system(size: size, design: .serif)).baselineOffset(shift) }
        return cat(paren("("), render(node, size: size, shift: shift), paren(")"))
    }

    private static func appendMark(_ node: MathNode, _ kind: String) -> MathNode {
        let mark: String
        switch kind {
        case "hat", "widehat": mark = "\u{0302}"
        case "bar", "overline": mark = "\u{0304}"
        case "vec": mark = "\u{20D7}"
        case "tilde", "widetilde": mark = "\u{0303}"
        default: mark = "\u{0307}"
        }
        switch node {
        case .atom(let s, let style): return .atom(s + mark, style)
        case .row(let children) where !children.isEmpty:
            return .row([appendMark(children[0], kind)] + children.dropFirst())
        default: return node
        }
    }

    private static func cardMarkdownInline(_ raw: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw)
    }
}

/// A run of guide prose at a Dynamic Type text style.
struct InlineMathText: View {
    let source: String
    var style: UIFont.TextStyle
    @Environment(\.dynamicTypeSize) private var dynamicType

    init(_ source: String, font style: UIFont.TextStyle = .body) {
        self.source = source
        self.style = style
    }

    var body: some View {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        InlineMath.text(source, size: size)
            .fixedSize(horizontal: false, vertical: true)
            .id(dynamicType)
    }
}

// MARK: - Light markdown blocks

/// Paragraphs, `-` lists, `1.` lists and pipe tables — the subset the guide
/// notes use. Anything else stays a paragraph, so an unexpected construct
/// shows as text rather than vanishing.
struct GuideMarkdown: View {
    let source: String
    var style: UIFont.TextStyle = .body

    private enum Block: Hashable {
        case paragraph(String)
        case bullets([String])
        case numbered([String])
        case table(header: [String], rows: [[String]])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.blocks(source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            InlineMathText(text, font: style)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.accent)
                        InlineMathText(item, font: style)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).").font(.body.monospacedDigit()).foregroundStyle(Theme.accent)
                        InlineMathText(item, font: style)
                    }
                }
            }
        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            InlineMathText("**\(cell)**", font: .footnote)
                        }
                    }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                InlineMathText(cell, font: .footnote)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(.background.secondary, in: .rect(cornerRadius: 12))
        }
    }

    private static func blocks(_ source: String) -> [Block] {
        let chunks = source.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return chunks.map { chunk in
            let lines = chunk.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            if lines.allSatisfy({ $0.hasPrefix("- ") }) {
                return .bullets(lines.map { String($0.dropFirst(2)) })
            }
            if lines.allSatisfy({ $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil }) {
                return .numbered(lines.map { $0.replacingOccurrences(of: #"^\d+\. "#, with: "", options: .regularExpression) })
            }
            if lines.count >= 2, lines.allSatisfy({ $0.hasPrefix("|") }) {
                let cells = lines
                    .filter { $0.range(of: #"^\|[\s\-:|]+\|$"#, options: .regularExpression) == nil }
                    .map { line in
                        line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                            .components(separatedBy: "|")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                    }
                return .table(header: cells.first ?? [], rows: Array(cells.dropFirst()))
            }
            return .paragraph(lines.joined(separator: " "))
        }
    }
}
