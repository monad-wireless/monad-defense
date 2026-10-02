import Foundation

// MARK: - Thesis guide (read-only bundled content)
//
// The guide walks the reader through the thesis's mathematics in order, from
// school level to its own equations and figures. It is compiled from the vault
// guide notes (`edu/guides/thesis-math/`) by `monad-knowledge edu guide compile`
// into `Resources/ThesisGuide.json`; the same notes render the Slidev decks
// under `publications/thesis-math/`, so the phone and the projector cannot drift.
//
// Unlike the deck bank it is not scheduled. Reading a step marks it read and
// nothing else: a guided walk is not a test, and grading it would push the
// reader to skip what they do not yet understand.

struct ThesisGuide: Decodable {
    let schemaVersion: Int
    let guide: String
    let title: String
    let thesisRevision: String
    let guideVersion: String
    let generatedAt: String
    let modules: [GuideModule]

    static let supportedSchemaVersion = 1

    /// The bundled guide, or `nil` when the bank is absent or from a newer
    /// compiler. The tab then says so instead of crashing the whole app —
    /// the deck bank, which the rest of the app needs, is unaffected.
    static func loadBundled() -> ThesisGuide? {
        guard let url = Bundle.main.url(forResource: "ThesisGuide", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let guide = try? decoder.decode(ThesisGuide.self, from: data),
            guide.schemaVersion == supportedSchemaVersion
        else { return nil }
        return guide
    }

    var stepCount: Int { modules.reduce(0) { $0 + $1.stepCount } }
}

struct GuideModule: Decodable, Identifiable, Hashable {
    let id: String
    let slug: String
    let order: Int
    let title: String
    let subtitle: String
    let intro: String
    let lessons: [GuideLesson]

    var stepCount: Int { lessons.reduce(0) { $0 + $1.steps.count } }
    var code: String { id.uppercased() }
}

struct GuideLesson: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    /// Where in the thesis the lesson lives, e.g. "§3.9, Eq. (3.2), Fig. 3.4".
    let thesis: String
    let summary: String
    let steps: [GuideStep]
}

enum GuideStepKind: String, Decodable {
    case idea, equation, figure
}

struct GuideStep: Decodable, Identifiable, Hashable {
    let id: String
    let kind: GuideStepKind
    let title: String
    /// Light markdown: paragraphs, `-` and `1.` lists, pipe tables, `**bold**`
    /// and `$inline maths$`.
    let body: String
    let latex: String?
    /// The thesis equation number, e.g. "Eq. (3.1)".
    let label: String?
    let symbols: [GuideSymbol]
    let implies: [String]
    let widget: GuideWidgetRef?
    let figure: GuideFigureRef?
    let check: GuideCheck?
    let anchors: [String]
}

struct GuideSymbol: Decodable, Hashable {
    /// LaTeX of the symbol.
    let symbol: String
    let meaning: String
}

struct GuideFigureRef: Decodable, Hashable {
    /// Filename in the bundled `Guide/` folder (flattened into the bundle).
    let asset: String
    let label: String?
    let caption: String
}

struct GuideCheck: Decodable, Hashable {
    let question: String
    let answer: String
}

/// One of the closed set of widget ids in `monad_knowledge/edu/guide.py:WIDGETS`.
/// An id this build does not implement renders as a placeholder, so a guide
/// compiled by a newer pipeline degrades instead of failing to decode.
struct GuideWidgetRef: Decodable, Hashable {
    let id: String
    let params: [String: GuideParam]

    func string(_ key: String) -> String? {
        if case .string(let s) = params[key] { return s }
        return nil
    }
}

enum GuideParam: Decodable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else {
            self = .string(try c.decode(String.self))
        }
    }
}
