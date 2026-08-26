import SwiftUI

// MARK: - SequenceFigureView
//
// A protocol exchange is a picture of TIME: who speaks, to whom, in what
// order. Actors get evenly spaced lifelines and each message takes the next
// row, so layout is computed from the order rather than authored — a
// reordered exchange needs no repositioning, and the diagram cannot come out
// crooked.
//
// The bank supplies actors and messages; everything below is geometry.

struct SequenceFigureView: View {
    let sequence: SequenceFigure
    var tint: Color = Theme.accent

    private var rowHeight: CGFloat { 40 }
    private var headerHeight: CGFloat { 30 }

    var body: some View {
        GeometryReader { geo in
            let lanes = lanePositions(in: geo.size.width)
            ZStack(alignment: .topLeading) {
                lifelines(lanes, height: geo.size.height)
                actorHeaders(lanes)
                ForEach(Array(sequence.messages.enumerated()), id: \.offset) { index, message in
                    messageRow(message, at: index, lanes: lanes)
                }
            }
        }
        .frame(height: headerHeight + CGFloat(sequence.messages.count) * rowHeight + 12)
    }

    // MARK: Geometry

    /// Actors are spread across the width, inset so a label at either end has
    /// room to centre on its lifeline.
    private func lanePositions(in width: CGFloat) -> [CGFloat] {
        let count = max(sequence.actors.count, 1)
        guard count > 1 else { return [width / 2] }
        let inset = min(width * 0.16, 70)
        let span = width - inset * 2
        return (0..<count).map { inset + span * CGFloat($0) / CGFloat(count - 1) }
    }

    private func lane(of actor: String, in lanes: [CGFloat]) -> CGFloat {
        guard let index = sequence.actors.firstIndex(of: actor), lanes.indices.contains(index)
        else { return lanes.first ?? 0 }
        return lanes[index]
    }

    // MARK: Pieces

    private func lifelines(_ lanes: [CGFloat], height: CGFloat) -> some View {
        ForEach(Array(lanes.enumerated()), id: \.offset) { _, x in
            Path { path in
                path.move(to: CGPoint(x: x, y: headerHeight))
                path.addLine(to: CGPoint(x: x, y: height))
            }
            .stroke(
                Color.secondary.opacity(0.3),
                style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
    }

    private func actorHeaders(_ lanes: [CGFloat]) -> some View {
        ForEach(Array(sequence.actors.enumerated()), id: \.offset) { index, actor in
            Text(actor)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(width: 96)
                .padding(.vertical, 4)
                .background(tint.opacity(0.12), in: .capsule)
                .position(x: lanes[index], y: headerHeight / 2)
        }
    }

    @ViewBuilder
    private func messageRow(_ message: SequenceMessage, at index: Int, lanes: [CGFloat])
        -> some View
    {
        let y = headerHeight + CGFloat(index) * rowHeight + rowHeight / 2
        let from = lane(of: message.source, in: lanes)
        let to = lane(of: message.target, in: lanes)
        let stroke = Color.secondary.opacity(0.7)
        let style = StrokeStyle(
            lineWidth: 1.3, lineCap: .round, dash: message.dashed ? [4, 3] : [])

        if message.selfMessage || from == to {
            // A message an actor sends to itself: a local step, a timeout.
            // Drawn as a loop to the right of its own lifeline.
            Path { path in
                path.move(to: CGPoint(x: from, y: y - 8))
                path.addLine(to: CGPoint(x: from + 26, y: y - 8))
                path.addLine(to: CGPoint(x: from + 26, y: y + 8))
                path.addLine(to: CGPoint(x: from + 4, y: y + 8))
            }
            .stroke(stroke, style: style)
            arrowHead(at: CGPoint(x: from + 4, y: y + 8), pointingLeft: true, colour: stroke)
            Text(message.label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .background(.background.opacity(0.9), in: .capsule)
                .position(x: from + 78, y: y)
        } else {
            Path { path in
                path.move(to: CGPoint(x: from, y: y))
                path.addLine(to: CGPoint(x: to, y: y))
            }
            .stroke(stroke, style: style)
            arrowHead(at: CGPoint(x: to, y: y), pointingLeft: to < from, colour: stroke)
            Text(message.label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .background(.background.opacity(0.9), in: .capsule)
                .position(x: (from + to) / 2, y: y - 11)
        }
    }

    private func arrowHead(at tip: CGPoint, pointingLeft: Bool, colour: Color) -> some View {
        let dx: CGFloat = pointingLeft ? 7 : -7
        return Path { path in
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x + dx, y: tip.y - 4))
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x + dx, y: tip.y + 4))
        }
        .stroke(colour, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }
}
