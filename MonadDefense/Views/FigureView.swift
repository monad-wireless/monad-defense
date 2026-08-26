import Charts
import SwiftUI

// MARK: - The figure layer
//
// One entry point for everything a card can show. `FigureView` switches on the
// kind and nothing else in the app knows how many kinds there are — adding an
// animation later means one more case here and one more view file.
//
// Every figure renders as: the picture, then its caption. The caption is not
// decoration. A picture without one asserts something the reader has to guess.

struct FigureView: View {
    let figure: Figure
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if !figure.caption.isEmpty {
                Text(figure.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var content: some View {
        switch figure {
        case .plot(let plot):
            PlotFigureView(plot: plot, tint: tint)
        case .diagram(let diagram):
            DiagramFigureView(diagram: diagram, tint: tint)
        case .image(let image):
            ImageFigureView(image: image)
        case .table(let table):
            TableFigureView(table: table, tint: tint)
        case .sequence(let sequence):
            SequenceFigureView(sequence: sequence, tint: tint)
        case .code(let code):
            CodeFigureView(figure: code, tint: tint)
        case .unsupported(let kind):
            Label(
                "This card has a \(kind) figure a newer version of the app can show.",
                systemImage: "questionmark.square.dashed"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

/// Render a card's figures in declared order.
struct FigureStack: View {
    let figures: [Figure]?
    var tint: Color = Theme.accent

    var body: some View {
        if let figures, !figures.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(figures) { figure in
                    FigureView(figure: figure, tint: tint)
                }
            }
        }
    }
}

// MARK: - Plot
//
// Curves arrive pre-sampled from the vault compiler, so this view draws points
// and nothing else — no expression evaluator, no interpolation guessing. Line
// segments are straight between samples, because a smoothed curve would assert
// behaviour between points that was never computed.

struct PlotFigureView: View {
    let plot: PlotFigure
    var tint: Color = Theme.accent

    @State private var frameIndex = 0

    private var frame: PlotFrame { plot.frames[min(frameIndex, plot.frames.count - 1)] }
    private var showLegend: Bool { frame.curves.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            chart
                .frame(height: 200)
                .chartXAxisLabel(plot.xLabel, alignment: .center)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartLegend(showLegend ? .visible : .hidden)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                .chartForegroundStyleScale(range: paletteRange)
                // Holding the y domain across frames is what makes a sweep
                // readable: an axis that rescales per frame hides the very
                // change the slider exists to show.
                .chartYScale(domain: yDomain)
                .padding(.leading, 2)
                .animation(.snappy, value: frameIndex)
            // The y quantity names itself under the chart rather than in a
            // rotated axis label: a vertical caption clips at this height, and
            // a clipped unit is worse than none.
            Text(plot.yLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let parameter = plot.parameter, plot.isInteractive {
                FrameScrubber(
                    count: plot.frames.count,
                    caption: parameter.caption(at:),
                    index: $frameIndex,
                    tint: tint)
            }
        }
    }

    private var paletteRange: [Color] {
        Array(([tint] + Theme.series.dropFirst()).prefix(max(frame.curves.count, 1)))
    }

    /// The union of every frame's range, padded, so the axis never moves.
    private var yDomain: ClosedRange<Double> {
        let ys = plot.frames.flatMap { $0.curves.flatMap { $0.samples.map(\.y) } }
        guard let low = ys.min(), let high = ys.max(), low < high else { return 0...1 }
        let pad = (high - low) * 0.06
        return (low - pad)...(high + pad)
    }

    private var chart: some View {
        Chart {
            ForEach(frame.curves) { curve in
                ForEach(curve.samples, id: \.x) { sample in
                    LineMark(
                        x: .value(plot.xLabel, sample.x),
                        y: .value(plot.yLabel, sample.y)
                    )
                    .foregroundStyle(by: .value("Curve", curve.label))
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 2.2, lineCap: .round,
                            dash: curve.dashed ? [5, 4] : []))
                }
            }
            ForEach(plot.markers) { marker in
                if marker.isVertical {
                    RuleMark(x: .value(plot.xLabel, marker.value))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(
                            position: .top, alignment: .leading,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) { markerLabel(marker.label) }
                } else {
                    RuleMark(y: .value(plot.yLabel, marker.value))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(
                            position: .top, alignment: .trailing,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) { markerLabel(marker.label) }
                }
            }
        }
    }

    private func markerLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.background.opacity(0.85), in: .capsule)
    }
}

// MARK: - Diagram
//
// Structure that no function of x can draw: a station/access-point topology, a
// protocol stack, an advertising timeline. Nodes carry normalised coordinates,
// so the figure fits whatever width it is given, reads correctly in both
// themes, and needs no raster and no vector parser.

struct DiagramFigureView: View {
    let diagram: DiagramFigure
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(diagram.edges) { edge in
                    edgeShape(edge, in: size)
                }
                ForEach(diagram.nodes) { node in
                    nodeShape(node, in: size)
                }
            }
        }
        .aspectRatio(diagram.aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    // MARK: Nodes

    @ViewBuilder
    private func nodeShape(_ node: DiagramNode, in size: CGSize) -> some View {
        let frame = CGSize(width: node.w * size.width, height: node.h * size.height)
        let centre = CGPoint(x: node.x * size.width, y: node.y * size.height)
        let stroke = node.emphasis ? tint : Color.secondary
        let fill = node.emphasis ? tint.opacity(0.12) : Color.secondary.opacity(0.07)

        Group {
            switch node.shape {
            case "lane":
                // A band rather than a box: the backdrop a timeline sits on.
                RoundedRectangle(cornerRadius: 6)
                    .fill(fill)
                    .overlay(alignment: .leading) {
                        Text(node.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(stroke)
                            .padding(.leading, 6)
                    }
            case "note":
                Text(node.label)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            default:
                shapePath(node.shape)
                    .fill(fill)
                    .overlay { shapePath(node.shape).stroke(stroke, lineWidth: 1.4) }
                    .overlay {
                        Text(node.label)
                            .font(.caption2.weight(node.emphasis ? .semibold : .regular))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(node.emphasis ? stroke : .primary)
                            .padding(3)
                    }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(centre)
    }

    private func shapePath(_ shape: String) -> AnyShape {
        switch shape {
        case "box": AnyShape(Rectangle())
        case "ellipse": AnyShape(Ellipse())
        default: AnyShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Edges

    @ViewBuilder
    private func edgeShape(_ edge: DiagramEdge, in size: CGSize) -> some View {
        if let a = diagram.node(edge.source), let b = diagram.node(edge.target) {
            let start = CGPoint(x: a.x * size.width, y: a.y * size.height)
            let end = CGPoint(x: b.x * size.width, y: b.y * size.height)
            // Stop the line at each node's boundary, not its centre, so the
            // arrowhead lands where the reader expects it.
            let p0 = boundaryPoint(from: start, toward: end, node: a, in: size)
            let p1 = boundaryPoint(from: end, toward: start, node: b, in: size)

            Path { path in
                path.move(to: p0)
                path.addLine(to: p1)
            }
            .stroke(
                Color.secondary.opacity(0.65),
                style: StrokeStyle(
                    lineWidth: 1.2, lineCap: .round, dash: edge.dashed ? [4, 3] : []))

            if edge.arrow == "end" || edge.arrow == "both" {
                arrowHead(at: p1, from: p0)
            }
            if edge.arrow == "both" {
                arrowHead(at: p0, from: p1)
            }
            if let label = edge.label {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .background(.background.opacity(0.9), in: .capsule)
                    .position(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
            }
        }
    }

    /// Where the line from `origin` towards `other` leaves the node's box.
    private func boundaryPoint(
        from origin: CGPoint, toward other: CGPoint, node: DiagramNode, in size: CGSize
    ) -> CGPoint {
        let dx = other.x - origin.x
        let dy = other.y - origin.y
        guard dx != 0 || dy != 0 else { return origin }
        let halfW = node.w * size.width / 2 + 2
        let halfH = node.h * size.height / 2 + 2
        // Scale the direction until it hits whichever edge it reaches first.
        let scaleX = dx == 0 ? Double.infinity : halfW / abs(dx)
        let scaleY = dy == 0 ? Double.infinity : halfH / abs(dy)
        let scale = min(scaleX, scaleY)
        return CGPoint(x: origin.x + dx * scale, y: origin.y + dy * scale)
    }

    private func arrowHead(at tip: CGPoint, from origin: CGPoint) -> some View {
        let angle = atan2(tip.y - origin.y, tip.x - origin.x)
        let length: CGFloat = 7
        let spread: CGFloat = .pi / 7
        return Path { path in
            path.move(to: tip)
            path.addLine(
                to: CGPoint(
                    x: tip.x - length * cos(angle - spread),
                    y: tip.y - length * sin(angle - spread)))
            path.move(to: tip)
            path.addLine(
                to: CGPoint(
                    x: tip.x - length * cos(angle + spread),
                    y: tip.y - length * sin(angle + spread)))
        }
        .stroke(Color.secondary.opacity(0.65), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }
}

// MARK: - Image

struct ImageFigureView: View {
    let image: ImageFigure

    var body: some View {
        if let ui = UIImage(named: image.asset) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityLabel(image.alt)
        } else {
            // A missing asset is a content bug, not a crash. Say which one.
            Label("Figure \(image.asset) is not in this build.", systemImage: "photo.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Symbol table

/// The "fields" of a formula: every letter in it, and what it stands for.
struct FormulaFieldsTable: View {
    let fields: [FormulaField]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                if index > 0 { Divider() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    MathView(latex: field.symbol, size: 15)
                        .frame(minWidth: 44, alignment: .leading)
                    Text(field.meaning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 7)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}
