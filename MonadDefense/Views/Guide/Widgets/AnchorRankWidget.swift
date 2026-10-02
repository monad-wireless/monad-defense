import Charts
import SwiftUI

/// M3: Jacobian rows (1, ∂L/∂log A, ∂L/∂log K) of an anchor design at A = 4,
/// K = 3, its rank and singular values. Presets are the designs of Table 3.4 /
/// Fig. 3.5 (smallest singular values 0, ≈0, 0.036, 0.181).
struct AnchorRankWidget: View {
    @State private var design = 3
    @State private var counts: [Double] = GuideMath.anchorDesigns[3].counts

    var body: some View {
        let J = counts.map { GuideMath.sensitivityRow($0, A: 4, K: 3) }
        let sv = GuideMath.singularValues(J)
        let rank = GuideMath.numericalRank(J)
        WidgetLayout(
            formula: "\\operatorname{rank}J=\(rank),\\quad \\sigma_{\\min}=\(tex(sv.last ?? 0, 4))",
            readout: [
                "σ = " + sv.map { sig($0) }.joined(separator: ", "),
                rank < 3 ? "\(3 - rank) parameter direction(s) invisible" : "all three directions seen",
            ],
            words: "each anchor adds one row. A repeated count adds the same row again, so the rank does not rise. Spread the counts and the weakest singular value grows: nearby positives give 0.036, the staircase 0.181.",
            chartHeight: 150 + 34 * CGFloat(counts.count + 1)
        ) {
            VStack(spacing: 8) {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("N").bold()
                        Text("∂L/∂b").bold()
                        Text("∂L/∂log A").bold()
                        Text("∂L/∂log K").bold()
                        Text("")
                    }
                    ForEach(Array(counts.enumerated()), id: \.offset) { i, n in
                        GridRow {
                            Text("\(Int(n))")
                            Text(fmt(J[i][0], 3))
                            Text(fmt(J[i][1], 3))
                            Text(fmt(J[i][2], 3))
                            Stepper("", value: Binding(get: { counts[i] }, set: { counts[i] = $0 }), in: 0...10)
                                .labelsHidden()
                        }
                    }
                }
                .font(.caption.monospacedDigit())
                Chart {
                    ForEach(Array(sv.enumerated()), id: \.offset) { i, s in
                        BarMark(x: .value("σ", "σ\(i + 1)"), y: .value("value", s))
                            .foregroundStyle(i == sv.count - 1 ? GuideColors.alt : GuideColors.accent)
                    }
                }
                .frame(height: 80)
            }
        } controls: {
            Picker("Design", selection: $design) {
                ForEach(Array(GuideMath.anchorDesigns.enumerated()), id: \.offset) { i, d in
                    Text(d.name).tag(i)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Add anchor") { if counts.count < 6 { counts.append(1) } }
                Spacer()
                Button("Remove last") { if counts.count > 1 { counts.removeLast() } }
            }
            .font(.footnote)
        }
        .onChange(of: design) { counts = GuideMath.anchorDesigns[design].counts }
    }
}
