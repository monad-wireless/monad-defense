import Foundation
import SwiftUI

// MARK: - Deck bank (read-only bundled content, IP-124)

struct DeckBank: Decodable {
    let schemaVersion: Int
    let bankVersion: String
    let generatedAt: String
    let decks: [Deck]
    let cards: [Card]
    /// IP-151 — the vault's dwell selection, projected so the Dwell review
    /// stack can hide decided cards offline. Absent on a bank compiled before
    /// the note existed.
    let dwellSelection: DwellSelection?

    static let supportedSchemaVersion = 1

    static func loadBundled() -> DeckBank {
        guard let url = Bundle.main.url(forResource: "DeckBank", withExtension: "json") else {
            fatalError("DeckBank.json missing from bundle — run `edu deck compile` and rebuild")
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let bank = try decoder.decode(DeckBank.self, from: data)
            guard bank.schemaVersion == supportedSchemaVersion else {
                fatalError("DeckBank schema v\(bank.schemaVersion) is not supported (app understands v\(supportedSchemaVersion))")
            }
            return bank
        } catch {
            fatalError("DeckBank.json failed to decode: \(error)")
        }
    }

    /// When the bundled bank was compiled. The content refresh is deliberately
    /// an explicit step rather than an Xcode build phase — the build stays fast
    /// and offline, and a vault error cannot break the app build. The cost of
    /// that choice is that a stale bank is invisible, so the app says so
    /// instead of letting it be discovered mid-session.
    var generatedDate: Date? {
        ISO8601DateFormatter().date(from: generatedAt)
    }

    /// Days since the bank was compiled, for the staleness notice.
    var ageInDays: Int? {
        guard let generatedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: generatedDate, to: .now).day
    }
}

/// What the vault has decided about cards for the phone (IP-151).
/// `included` maps a card id to the digest of the block that was accepted;
/// a card whose compiled `dwellDigest` differs is *stale* and returns to the
/// review stack first.
struct DwellSelection: Decodable, Hashable {
    let included: [String: String]
    let excluded: [String]

    static let empty = DwellSelection(included: [:], excluded: [])

    enum Status: Hashable {
        case included, stale, excluded, undecided
    }

    func status(of card: Card) -> Status {
        if let accepted = included[card.id] {
            return accepted == card.dwellDigest ? .included : .stale
        }
        return excluded.contains(card.id) ? .excluded : .undecided
    }
}

/// The phone-facing compression of a card (IP-151): what a participant reads
/// on the 11 s dwell panels. Written from a Claude Code session, shipped only
/// after a right-swipe here.
struct DwellBlock: Decodable, Hashable {
    /// The term in plain words — the `foundation` panel.
    let definition: String
    /// A concrete instance with a number the card carries — the `wild` panel.
    let fact: String?
    /// One dry line after the fact.
    let quip: String?
}

struct Deck: Decodable, Identifiable, Hashable {
    let slug: String
    let title: String
    let track: Track
    let difficulty: Difficulty
    let defense: Bool
    let deckVersion: Int
    let tags: [String]
    let cardCount: Int

    var id: String { slug }

    /// Title without the "TRACK · " prefix, for rows already grouped by track.
    var shortTitle: String {
        guard let range = title.range(of: " · ") else { return title }
        return String(title[range.upperBound...])
    }
}

/// Declaration order is reading order: vocabulary, then the courses it lets you
/// read, then the thesis, then the document chapter by chapter.
enum Track: String, Decodable, CaseIterable, Identifiable, Hashable {
    case core
    case ws501 = "WS501"
    case loc502 = "LOC502"
    case crd503 = "CRD503"
    case prb504 = "PRB504"
    case fm505 = "FM505"
    case sim507 = "SIM507"
    case thesis
    case chapters

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .core: "Fundamentals"
        case .ws501: "Wi-Fi CSI Sensing"
        case .loc502: "BLE & RF Localization"
        case .crd503: "Crowd Dynamics"
        case .prb504: "Statistical Methods"
        case .fm505: "Formal Modelling"
        case .sim507: "Simulation Toolkits"
        case .thesis: "Thesis Results"
        case .chapters: "The Chapters"
        }
    }

    var code: String {
        switch self {
        case .core: "CORE"
        case .thesis: "THESIS"
        case .chapters: "CH"
        default: rawValue
        }
    }

    var tint: Color {
        switch self {
        case .core: .mint
        case .ws501: .blue
        case .loc502: .teal
        case .crd503: .orange
        case .prb504: .purple
        case .fm505: .brown
        case .sim507: .green
        case .thesis: Theme.accent
        case .chapters: .pink
        }
    }

    var symbol: String {
        switch self {
        case .core: "character.book.closed"
        case .ws501: "wifi"
        case .loc502: "dot.radiowaves.left.and.right"
        case .crd503: "figure.walk.motion"
        case .prb504: "chart.bar.xaxis"
        case .fm505: "checkmark.seal"
        case .sim507: "cube.transparent"
        case .thesis: "graduationcap"
        case .chapters: "book.pages"
        }
    }
}

enum Difficulty: String, Decodable, CaseIterable, Identifiable, Comparable {
    case basics, core, advanced

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var tint: Color {
        switch self {
        case .basics: .green
        case .core: .orange
        case .advanced: .red
        }
    }

    private var rank: Int {
        switch self {
        case .basics: 0
        case .core: 1
        case .advanced: 2
        }
    }

    static func < (lhs: Difficulty, rhs: Difficulty) -> Bool { lhs.rank < rhs.rank }
}

enum CardKind: String, Decodable {
    case flash, mcq, formula

    var displayName: String {
        switch self {
        case .flash: "Flashcard"
        case .mcq: "Multiple choice"
        case .formula: "Formula"
        }
    }

    var symbol: String {
        switch self {
        case .flash: "rectangle.on.rectangle.angled"
        case .mcq: "checklist"
        case .formula: "function"
        }
    }
}

// MARK: - Formula card payload

/// One row of a formula's symbol table — what a letter in the equation stands for.
struct FormulaField: Decodable, Hashable {
    let symbol: String
    let meaning: String
}

// MARK: - Figures
//
// What a card can SHOW, beyond words. One list, discriminated by `kind`, on
// every card kind — so a flashcard about a topology carries a diagram exactly
// as a formula card carries a plot. Adding a new way to show something (an
// animation, say) means one case here and one view in FigureView, and nothing
// else moves.

struct PlotSample: Hashable {
    let x: Double
    let y: Double
}

/// A sampled curve. The compiler evaluated the declared expression over its
/// domain, so the app draws points and carries no expression evaluator.
struct PlotCurve: Decodable, Hashable, Identifiable {
    let label: String
    let dashed: Bool
    let points: [[Double]]

    var id: String { label }

    var samples: [PlotSample] {
        points.compactMap { $0.count == 2 ? PlotSample(x: $0[0], y: $0[1]) : nil }
    }
}

/// A reference line: a crossover, a capacity point, a saturation scale.
struct PlotMarker: Decodable, Hashable, Identifiable {
    let axis: String  // "x" or "y"
    let value: Double
    let label: String

    var id: String { "\(axis)|\(value)|\(label)" }
    var isVertical: Bool { axis == "x" }
}

/// One pre-sampled state of a plot. A plot without a swept parameter has
/// exactly one frame, which is what keeps the drawing path uniform.
struct PlotFrame: Decodable, Hashable, Identifiable {
    let value: Double?
    let curves: [PlotCurve]

    var id: Double { value ?? 0 }
}

/// A quantity swept across frames. Values are declared by the author, so the
/// slider can only land on a state somebody chose to show.
struct PlotParameter: Decodable, Hashable {
    let label: String
    let unit: String?
    let values: [Double]
    let scenarios: [String]?

    /// What to print for frame `index`: its scenario name where the author
    /// gave one, otherwise the value with its unit.
    func caption(at index: Int) -> String {
        if let scenarios, scenarios.indices.contains(index) { return scenarios[index] }
        guard values.indices.contains(index) else { return label }
        let number = values[index].formatted(.number.precision(.fractionLength(0...3)))
        return unit.map { "\(label) = \(number) \($0)" } ?? "\(label) = \(number)"
    }
}

struct PlotFigure: Decodable, Hashable {
    let caption: String
    let xLabel: String
    let yLabel: String
    let frames: [PlotFrame]
    let markers: [PlotMarker]
    let parameter: PlotParameter?

    var isInteractive: Bool { parameter != nil && frames.count > 1 }
}

/// Values that are a list rather than a shape.
struct TableFigure: Decodable, Hashable {
    let caption: String
    let columns: [String]
    let rows: [[String]]
    let emphasis: [Int]
}

struct SequenceMessage: Decodable, Hashable, Identifiable {
    let source: String
    let target: String
    let label: String
    let dashed: Bool
    let selfMessage: Bool

    var id: String { "\(source)->\(target):\(label)" }
}

/// Actors and the ordered messages between them. Layout is computed from the
/// order, so the picture is of TIME rather than of position.
struct SequenceFigure: Decodable, Hashable {
    let caption: String
    let actors: [String]
    let messages: [SequenceMessage]
}

/// One labelled thing on a diagram canvas, positioned in the unit square with
/// the origin at top-left.
struct DiagramNode: Decodable, Hashable, Identifiable {
    let id: String
    let label: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let shape: String  // box | rounded | ellipse | note | lane
    let emphasis: Bool
}

struct DiagramEdge: Decodable, Hashable, Identifiable {
    let source: String
    let target: String
    let label: String?
    let dashed: Bool
    let arrow: String  // none | end | both

    var id: String { "\(source)->\(target)" }
}

struct DiagramFigure: Decodable, Hashable {
    let caption: String
    let aspect: Double
    let nodes: [DiagramNode]
    let edges: [DiagramEdge]

    func node(_ id: String) -> DiagramNode? { nodes.first { $0.id == id } }
}

/// A bundled raster — the one case a drawn figure cannot serve: showing what
/// real measured data actually looks like.
struct ImageFigure: Decodable, Hashable {
    let caption: String
    /// Filename inside the bundled `Figures/` directory.
    let asset: String
    let alt: String
}

/// One command, what it printed, and why you would run it.
struct CodeStep: Decodable, Hashable, Identifiable {
    let run: String
    let output: String?
    let note: String?

    var id: String { run }
}

/// Commands and their output — the term as the machine reports it.
///
/// A definition of PHY is one thing; `iw dev` on a real card is another, and
/// the second is what makes the first stick. Text, not a raster, so it scales
/// with the reader's type size like everything else here.
struct CodeFigure: Decodable, Hashable {
    let caption: String
    /// `shell` | `python` | `text`. Only `shell` gets a prompt character.
    let language: String
    let steps: [CodeStep]

    var prompt: String { language == "shell" ? "$" : "" }
}

/// The discriminated figure. An unknown `kind` decodes to `.unsupported`
/// rather than failing the whole bank — a bank compiled by a newer pipeline
/// should degrade to "this card has a picture you cannot see yet", never to a
/// crash on launch.
enum Figure: Decodable, Hashable, Identifiable {
    case plot(PlotFigure)
    case diagram(DiagramFigure)
    case image(ImageFigure)
    case table(TableFigure)
    case sequence(SequenceFigure)
    case code(CodeFigure)
    case unsupported(String)

    private enum CodingKeys: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        let kind = try decoder.container(keyedBy: CodingKeys.self)
            .decode(String.self, forKey: .kind)
        switch kind {
        case "plot": self = .plot(try PlotFigure(from: decoder))
        case "diagram": self = .diagram(try DiagramFigure(from: decoder))
        case "image": self = .image(try ImageFigure(from: decoder))
        case "table": self = .table(try TableFigure(from: decoder))
        case "sequence": self = .sequence(try SequenceFigure(from: decoder))
        case "code": self = .code(try CodeFigure(from: decoder))
        default: self = .unsupported(kind)
        }
    }

    var caption: String {
        switch self {
        case .plot(let f): f.caption
        case .diagram(let f): f.caption
        case .image(let f): f.caption
        case .table(let f): f.caption
        case .sequence(let f): f.caption
        case .code(let f): f.caption
        case .unsupported: ""
        }
    }

    var id: String {
        switch self {
        case .plot(let f): "plot|\(f.caption)"
        case .diagram(let f): "diagram|\(f.caption)"
        case .image(let f): "image|\(f.asset)"
        case .table(let f): "table|\(f.caption)"
        case .sequence(let f): "sequence|\(f.caption)"
        case .code(let f): "code|\(f.caption)"
        case .unsupported(let k): "unsupported|\(k)"
        }
    }
}

// MARK: - Card

struct Card: Decodable, Identifiable, Hashable {
    let id: String
    let kind: CardKind
    let deck: String
    let track: Track
    let difficulty: Difficulty
    let defense: Bool
    /// Validated knowledge-base anchors — argument-chain links and hypothesis
    /// slugs. Resolvable against the vault, unlike `sources`.
    let anchors: [String]
    /// Free-form provenance. Never validated.
    let sources: [String]
    let tags: [String]

    /// One named instance of the thing, with its own numbers. Its own field
    /// rather than a paragraph inside `back`, because a definition and an
    /// example fail differently: prose with no example still reads as
    /// finished. Given its own heading below, so a reader looks for it.
    let example: String?

    // flash
    let front: String?
    let back: String?
    let why: String?

    // mcq + formula
    let question: String?
    let explanation: String?

    // mcq
    let choices: [String]?
    let correct: Int?

    // formula
    let latex: String?
    let reading: String?
    let fields: [FormulaField]?

    /// What this card shows. Any card kind may carry any figure kind.
    let figures: [Figure]?

    /// The `###` heading above the card in its deck note — a short human name
    /// where the prompt is a whole question.
    let title: String?

    /// Cards this one leads to. Symmetric by construction — the compiler
    /// makes every declared link two-way, so there are no one-way streets.
    let seeAlso: [String]?

    /// IP-151 — the dwell block and the compiler's digest of it. The digest is
    /// compared, never computed, on this side.
    let dwell: DwellBlock?
    let dwellDigest: String?

    static func == (lhs: Card, rhs: Card) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var prompt: String {
        switch kind {
        case .flash: front ?? ""
        case .mcq, .formula: question ?? ""
        }
    }
}
