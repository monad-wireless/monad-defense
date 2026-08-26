import SwiftUI

// MARK: - A small display-maths typesetter
//
// The app has no third-party dependencies and iOS has no LaTeX renderer, so
// formula cards carry a *restricted* LaTeX subset that this file parses into a
// node tree and lays out with SwiftUI. It covers what the thesis's equations
// actually use: greek letters, upright operator names, sub/superscripts,
// fractions, radicals, accents, big operators and the usual relation symbols.
//
// Anything it cannot parse falls back to the raw source in a monospaced face.
// A formula that renders as its own LaTeX is ugly; a formula that crashes the
// session is worse.

// MARK: Node tree

indirect enum MathNode {
    case row([MathNode])
    case atom(String, MathAtomStyle)
    case fraction(MathNode, MathNode)
    case radical(MathNode)
    case scripted(base: MathNode, sub: MathNode?, sup: MathNode?)
    case bigOperator(String, lower: MathNode?, upper: MathNode?)
    case accent(String, MathNode)
    case space(CGFloat)
    case empty
}

enum MathAtomStyle {
    /// Single-letter variables and greek: italic, the maths convention.
    case variable
    /// Operator names, digits, units: upright.
    case upright
    /// Bold upright — vectors and matrices (`\mathbf`).
    case bold
    /// Relations and binary operators, which get air around them.
    case relation
    /// Delimiters and punctuation: upright, no extra air.
    case punctuation
}

// MARK: Symbol tables

private enum MathSymbols {
    /// Macro name → glyph, for macros that render as one italic atom.
    static let variables: [String: String] = [
        "alpha": "\u{03B1}", "beta": "\u{03B2}", "gamma": "\u{03B3}", "delta": "\u{03B4}",
        "epsilon": "\u{03B5}", "varepsilon": "\u{03B5}", "zeta": "\u{03B6}", "eta": "\u{03B7}",
        "theta": "\u{03B8}", "iota": "\u{03B9}", "kappa": "\u{03BA}", "lambda": "\u{03BB}",
        "mu": "\u{03BC}", "nu": "\u{03BD}", "xi": "\u{03BE}", "pi": "\u{03C0}",
        "rho": "\u{03C1}", "sigma": "\u{03C3}", "tau": "\u{03C4}", "upsilon": "\u{03C5}",
        "phi": "\u{03C6}", "varphi": "\u{03C6}", "chi": "\u{03C7}", "psi": "\u{03C8}",
        "omega": "\u{03C9}",
    ]

    /// Macro name → glyph, for macros that render upright.
    static let uprights: [String: String] = [
        "Gamma": "\u{0393}", "Delta": "\u{0394}", "Theta": "\u{0398}", "Lambda": "\u{039B}",
        "Xi": "\u{039E}", "Pi": "\u{03A0}", "Sigma": "\u{03A3}", "Phi": "\u{03A6}",
        "Psi": "\u{03A8}", "Omega": "\u{03A9}",
        "partial": "\u{2202}", "nabla": "\u{2207}", "infty": "\u{221E}",
        "ldots": "\u{2026}", "cdots": "\u{22EF}", "dots": "\u{2026}",
        "exp": "exp", "log": "log", "ln": "ln", "sin": "sin", "cos": "cos", "tan": "tan",
        "max": "max", "min": "min", "arg": "arg", "det": "det", "dim": "dim",
    ]

    /// Macro name → glyph, for relations and binary operators (spaced).
    static let relations: [String: String] = [
        "approx": "\u{2248}", "neq": "\u{2260}", "leq": "\u{2264}", "geq": "\u{2265}",
        "le": "\u{2264}", "ge": "\u{2265}", "equiv": "\u{2261}", "sim": "\u{223C}",
        "propto": "\u{221D}", "in": "\u{2208}", "notin": "\u{2209}", "subset": "\u{2282}",
        "to": "\u{2192}", "rightarrow": "\u{2192}", "leftarrow": "\u{2190}",
        "mapsto": "\u{21A6}", "times": "\u{00D7}", "cdot": "\u{22C5}", "pm": "\u{00B1}",
        "mp": "\u{2213}", "div": "\u{00F7}", "ast": "\u{2217}", "oplus": "\u{2295}",
        "Rightarrow": "\u{21D2}", "Leftarrow": "\u{21D0}", "Leftrightarrow": "\u{21D4}",
        "leftrightarrow": "\u{2194}", "implies": "\u{21D2}", "iff": "\u{21D4}",
        "ll": "\u{226A}", "gg": "\u{226B}", "simeq": "\u{2243}", "cong": "\u{2245}",
        "perp": "\u{22A5}", "cup": "\u{222A}", "cap": "\u{2229}", "setminus": "\u{2216}",
    ]

    /// Macro name → glyph, for operators that take limits above and below.
    static let bigOperators: [String: String] = [
        "sum": "\u{2211}", "prod": "\u{220F}", "int": "\u{222B}",
        "bigcup": "\u{22C3}", "bigcap": "\u{22C2}",
    ]

    /// Macro name → width as a fraction of the font size.
    static let spaces: [String: CGFloat] = [
        ",": 0.16, ":": 0.22, ";": 0.28, "!": -0.16, "quad": 1.0, "qquad": 2.0, " ": 0.3,
    ]

    static let accents: Set<String> = ["hat", "bar", "vec", "tilde", "dot", "overline"]

    /// Macros whose single argument changes the style of its contents.
    static let styleGroups: [String: MathAtomStyle] = [
        "mathrm": .upright, "operatorname": .upright, "text": .upright,
        "mathbf": .bold, "boldsymbol": .bold, "mathit": .variable,
    ]

    /// Macros that only exist to size a delimiter; the delimiter follows.
    static let delimiterSizers: Set<String> = ["left", "right", "big", "Big", "bigg", "Bigg"]
}

// MARK: Parser

struct MathParseError: Error {}

struct MathParser {
    private let source: [Character]
    private var index = 0

    init(_ latex: String) {
        source = Array(latex)
    }

    static func parse(_ latex: String) -> MathNode? {
        var parser = MathParser(latex)
        guard let node = try? parser.parseRow(until: nil) else { return nil }
        return node
    }

    // MARK: Scanning

    private var current: Character? { index < source.count ? source[index] : nil }

    private mutating func advance() -> Character? {
        guard index < source.count else { return nil }
        defer { index += 1 }
        return source[index]
    }

    private mutating func skipSpaces() {
        while let c = current, c == " " || c == "\n" || c == "\t" { index += 1 }
    }

    private mutating func readMacroName() -> String {
        // A macro is either a run of letters (\alpha) or a single symbol (\,).
        var name = ""
        while let c = current, c.isLetter {
            name.append(c)
            index += 1
        }
        if name.isEmpty, let c = advance() {
            name = String(c)
        }
        return name
    }

    // MARK: Grammar

    /// Parse a sequence of atoms up to `terminator` (or the end of input).
    private mutating func parseRow(until terminator: Character?) throws -> MathNode {
        var nodes: [MathNode] = []
        while let c = current {
            if let terminator, c == terminator {
                index += 1
                return .row(nodes)
            }
            let node = try parseAtomWithScripts(style: .variable)
            if case .empty = node { continue }
            nodes.append(node)
        }
        if terminator != nil { throw MathParseError() }  // unbalanced group
        return .row(nodes)
    }

    /// One atom plus any `_`/`^` scripts bound to it.
    private mutating func parseAtomWithScripts(style: MathAtomStyle) throws -> MathNode {
        let base = try parseAtom(style: style)
        var sub: MathNode?
        var sup: MathNode?
        while let c = current, c == "_" || c == "^" {
            index += 1
            let script = try parseAtom(style: style)
            if c == "_" { sub = script } else { sup = script }
        }
        if sub == nil, sup == nil { return base }
        if case .bigOperator(let glyph, _, _) = base {
            return .bigOperator(glyph, lower: sub, upper: sup)
        }
        return .scripted(base: base, sub: sub, sup: sup)
    }

    private mutating func parseAtom(style: MathAtomStyle) throws -> MathNode {
        skipSpaces()
        guard let c = current else { throw MathParseError() }
        if c == "{" {
            index += 1
            return try parseGroup(until: "}", style: style)
        }
        if c == "\\" {
            index += 1
            return try parseMacro(style: style)
        }
        if c == "}" { throw MathParseError() }  // stray close
        index += 1
        return .atom(String(c), atomStyle(for: c, inherited: style))
    }

    /// A braced group, parsed with an inherited style.
    private mutating func parseGroup(until terminator: Character, style: MathAtomStyle) throws -> MathNode {
        var nodes: [MathNode] = []
        while let c = current {
            if c == terminator {
                index += 1
                return .row(nodes)
            }
            let node = try parseAtomWithScripts(style: style)
            if case .empty = node { continue }
            nodes.append(node)
        }
        throw MathParseError()
    }

    private mutating func parseMacro(style: MathAtomStyle) throws -> MathNode {
        let name = readMacroName()
        guard !name.isEmpty else { throw MathParseError() }

        if let width = MathSymbols.spaces[name] { return .space(width) }
        if let glyph = MathSymbols.variables[name] { return .atom(glyph, .variable) }
        if let glyph = MathSymbols.uprights[name] { return .atom(glyph, .upright) }
        if let glyph = MathSymbols.relations[name] { return .atom(glyph, .relation) }
        if let glyph = MathSymbols.bigOperators[name] {
            return .bigOperator(glyph, lower: nil, upper: nil)
        }
        if MathSymbols.delimiterSizers.contains(name) {
            // `\left(` — drop the sizer, keep the delimiter that follows.
            skipSpaces()
            if let d = current, d != "\\" {
                index += 1
                if d == "." { return .empty }  // \left. is an invisible fence
                return .atom(String(d), .punctuation)
            }
            return .empty
        }
        if let groupStyle = MathSymbols.styleGroups[name] {
            return try parseArgument(style: groupStyle)
        }
        if MathSymbols.accents.contains(name) {
            return .accent(name, try parseArgument(style: style))
        }
        if name == "frac" || name == "dfrac" || name == "tfrac" {
            let numerator = try parseArgument(style: style)
            let denominator = try parseArgument(style: style)
            return .fraction(numerator, denominator)
        }
        if name == "sqrt" {
            return .radical(try parseArgument(style: style))
        }
        // An unknown macro is rendered upright rather than dropped, so the
        // reader sees the word instead of a hole.
        return .atom(name, .upright)
    }

    /// The next `{...}` group, or the next single atom if there are no braces.
    private mutating func parseArgument(style: MathAtomStyle) throws -> MathNode {
        skipSpaces()
        guard let c = current else { throw MathParseError() }
        if c == "{" {
            index += 1
            return try parseGroup(until: "}", style: style)
        }
        return try parseAtom(style: style)
    }

    private func atomStyle(for c: Character, inherited: MathAtomStyle) -> MathAtomStyle {
        if inherited == .upright || inherited == .bold { return inherited }
        if c.isNumber { return .upright }
        if "+-=<>~".contains(c) { return .relation }
        if "()[]|,.;:/!'".contains(c) { return .punctuation }
        return .variable
    }
}

// MARK: - Rendering

/// Typeset display maths. Falls back to the raw source if parsing fails.
struct MathView: View {
    let latex: String
    var size: CGFloat = 20

    var body: some View {
        if let node = MathParser.parse(latex) {
            MathNodeView(node: node, size: size)
        } else {
            Text(latex)
                .font(.system(size: size * 0.72, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct MathNodeView: View {
    let node: MathNode
    let size: CGFloat

    /// Scripts and limits never shrink below this, or they stop being legible.
    private var scriptSize: CGFloat { max(size * 0.68, 11) }

    var body: some View {
        switch node {
        case .empty:
            EmptyView()

        case .space(let width):
            Color.clear.frame(width: max(width * size, 0), height: 1)

        case .atom(let text, let style):
            atomText(text, style: style)

        case .row(let children):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MathNodeView(node: child, size: size)
                }
            }

        case .accent(let kind, let base):
            accentView(kind: kind, base: base)

        case .scripted(let base, let sub, let sup):
            scriptedView(base: base, sub: sub, sup: sup)

        case .fraction(let numerator, let denominator):
            fractionView(numerator, denominator)

        case .radical(let body):
            radicalView(body)

        case .bigOperator(let glyph, let lower, let upper):
            bigOperatorView(glyph, lower: lower, upper: upper)
        }
    }

    // MARK: Pieces

    private func atomText(_ text: String, style: MathAtomStyle) -> some View {
        let font: Font
        switch style {
        case .variable: font = .system(size: size, design: .serif).italic()
        case .upright, .punctuation: font = .system(size: size, design: .serif)
        case .bold: font = .system(size: size, weight: .bold, design: .serif)
        case .relation: font = .system(size: size, design: .serif)
        }
        let air = style == .relation ? size * 0.18 : 0
        return Text(text)
            .font(font)
            .padding(.horizontal, air)
    }

    private func accentView(kind: String, base: MathNode) -> some View {
        let mark: String
        switch kind {
        case "hat": mark = "\u{0302}"
        case "bar", "overline": mark = "\u{0304}"
        case "vec": mark = "\u{20D7}"
        case "tilde": mark = "\u{0303}"
        default: mark = "\u{0307}"
        }
        // Combining marks attach to the glyph, which is what the reader expects
        // for the single-letter bases these formulas use (N-hat, H-bar).
        return MathNodeView(node: appendCombining(base, mark), size: size)
    }

    private func appendCombining(_ node: MathNode, _ mark: String) -> MathNode {
        switch node {
        case .atom(let text, let style):
            return .atom(text + mark, style)
        case .row(let children):
            guard let first = children.first else { return node }
            return .row([appendCombining(first, mark)] + children.dropFirst())
        default:
            return node
        }
    }

    private func scriptedView(base: MathNode, sub: MathNode?, sup: MathNode?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            MathNodeView(node: base, size: size)
            if let sup, let sub {
                VStack(alignment: .leading, spacing: 0) {
                    MathNodeView(node: sup, size: scriptSize)
                    MathNodeView(node: sub, size: scriptSize)
                }
                .alignmentGuide(.firstTextBaseline) { d in
                    d[VerticalAlignment.center] + size * 0.28
                }
            } else if let sup {
                MathNodeView(node: sup, size: scriptSize)
                    .alignmentGuide(.firstTextBaseline) { d in
                        d[.firstTextBaseline] + size * 0.38
                    }
            } else if let sub {
                MathNodeView(node: sub, size: scriptSize)
                    .alignmentGuide(.firstTextBaseline) { d in
                        d[.firstTextBaseline] - size * 0.18
                    }
            }
        }
    }

    private func fractionView(_ numerator: MathNode, _ denominator: MathNode) -> some View {
        VStack(spacing: size * 0.12) {
            MathNodeView(node: numerator, size: scriptSize)
            Rectangle()
                .frame(height: max(size * 0.05, 1))
            MathNodeView(node: denominator, size: scriptSize)
        }
        .fixedSize()
        .padding(.horizontal, size * 0.1)
        // Sit the rule on the maths axis rather than on the text baseline.
        .alignmentGuide(.firstTextBaseline) { d in
            d[VerticalAlignment.center] + size * 0.30
        }
    }

    private func radicalView(_ body: MathNode) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\u{221A}")
                .font(.system(size: size * 1.15, design: .serif))
            MathNodeView(node: body, size: size)
                .padding(.horizontal, size * 0.06)
                .overlay(alignment: .top) {
                    Rectangle().frame(height: max(size * 0.05, 1))
                }
        }
    }

    private func bigOperatorView(_ glyph: String, lower: MathNode?, upper: MathNode?) -> some View {
        VStack(spacing: 0) {
            if let upper {
                MathNodeView(node: upper, size: scriptSize * 0.9)
            }
            Text(glyph)
                .font(.system(size: size * 1.4, design: .serif))
            if let lower {
                MathNodeView(node: lower, size: scriptSize * 0.9)
            }
        }
        .fixedSize()
        .padding(.horizontal, size * 0.1)
        .alignmentGuide(.firstTextBaseline) { d in
            d[VerticalAlignment.center] + size * 0.30
        }
    }
}

// MARK: - Display block

/// A formula in its own slab — centred, scrollable sideways when it is long.
struct FormulaBlock: View {
    let latex: String
    var size: CGFloat = 21

    var body: some View {
        // Shrink before scrolling: a formula that runs off the edge is one the
        // reader has to discover is scrollable. Only when even the smallest
        // size will not fit does it become a horizontal scroller.
        ViewThatFits(in: .horizontal) {
            slab(size)
            slab(size * 0.82)
            slab(size * 0.68)
            ScrollView(.horizontal, showsIndicators: false) {
                slab(size * 0.68)
            }
            .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity)
    }

    private func slab(_ pointSize: CGFloat) -> some View {
        MathView(latex: latex, size: pointSize)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 18) {
        FormulaBlock(latex: #"\mathrm{Var}\,|H| \approx \sigma^{2}\left(1 - e^{-K/K_{0}}\right)"#)
        FormulaBlock(latex: #"\frac{\partial \rho}{\partial t} + \nabla \cdot (\rho \mathbf{v}) = 0"#)
        FormulaBlock(latex: #"H(t) = H_{0} + \sum_{k=1}^{K} a_{k} e^{j\varphi_{k}(t)}"#)
        FormulaBlock(latex: #"\hat{N} \quad \mathrm{RSSI}(d) = \mathrm{RSSI}(d_{0}) - 10 n \log_{10}(d/d_{0})"#)
    }
    .padding()
}
