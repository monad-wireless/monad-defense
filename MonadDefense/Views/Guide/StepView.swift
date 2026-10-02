import SwiftUI

/// One guide step, top to bottom in the order a reader needs it: what it is,
/// the figure or the words, the formula, each symbol, the widget to try, what
/// follows from it, and a check whose answer stays hidden until asked for.
struct StepView: View {
    let step: GuideStep
    let lessonTitle: String
    @State private var answerShown = false
    @State private var zoomed = false

    var body: some View {
        #if DEBUG
        if DebugRouter.widgetOnly, let widget = step.widget {
            GuideWidgetView(ref: widget)
        } else {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let figure = step.figure {
                figureBlock(figure)
            }
            if !step.body.isEmpty {
                GuideMarkdown(source: step.body)
                    .fontDesign(.serif)
            }
            if let latex = step.latex {
                VStack(alignment: .trailing, spacing: 4) {
                    FormulaBlock(latex: latex)
                    if let label = step.label {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            if !step.symbols.isEmpty {
                section("Symbol by symbol", symbol: "character.textbox") {
                    symbolTable
                }
            }
            if let widget = step.widget {
                section("Try it", symbol: "slider.horizontal.3") {
                    GuideWidgetView(ref: widget)
                }
            }
            if !step.implies.isEmpty {
                section("What it implies", symbol: "arrow.turn.down.right") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(step.implies, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(Theme.accent)
                                InlineMathText(line)
                            }
                        }
                    }
                }
            }
            if let check = step.check {
                checkCard(check)
            }
            if !step.anchors.isEmpty {
                SourceChips(anchors: step.anchors, sources: [])
            }
        }
        .fullScreenCover(isPresented: $zoomed) {
            if let figure = step.figure { FigureZoom(figure: figure) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(kindName, systemImage: kindSymbol)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.14), in: .capsule)
                    .foregroundStyle(Theme.accent)
                if let label = step.label ?? step.figure?.label {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(step.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var kindName: String {
        switch step.kind {
        case .idea: "Idea"
        case .equation: "Equation"
        case .figure: "Figure"
        }
    }

    private var kindSymbol: String {
        switch step.kind {
        case .idea: "lightbulb"
        case .equation: "function"
        case .figure: "photo"
        }
    }

    private func figureBlock(_ figure: GuideFigureRef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = UIImage(named: figure.asset) {
                Button {
                    zoomed = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .background(Color.white, in: .rect(cornerRadius: 12))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .padding(6)
                                .background(.thinMaterial, in: .circle)
                                .padding(6)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enlarge \(figure.label ?? "figure")")
            } else {
                Label("Figure \(figure.asset) is not in the bundle", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            InlineMathText((figure.label.map { "**\($0).** " } ?? "") + figure.caption, font: .footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var symbolTable: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
            ForEach(step.symbols, id: \.self) { row in
                GridRow {
                    MathView(latex: row.symbol, size: 18)
                        .gridColumnAlignment(.leading)
                        .fixedSize()
                    InlineMathText(row.meaning, font: .subheadline)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.accent)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private func checkCard(_ check: GuideCheck) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Check yourself", systemImage: "questionmark.circle")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.accent)
            InlineMathText(check.question)
            if answerShown {
                InlineMathText(check.answer)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 10))
            } else {
                Button("Show the answer") {
                    withAnimation { answerShown = true }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.35)))
    }
}

/// A thesis figure full screen, pinch to zoom. Thesis figures are drawn for
/// an A4 page, so on a phone they need a way to be read at their own size.
private struct FigureZoom: View {
    let figure: GuideFigureRef
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    if let image = UIImage(named: figure.asset) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width * scale * pinch)
                            .padding()
                            .background(Color.white)
                    }
                }
            }
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in scale = min(max(scale * value.magnification, 1), 5) }
            )
            .navigationTitle(figure.label ?? "Figure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
