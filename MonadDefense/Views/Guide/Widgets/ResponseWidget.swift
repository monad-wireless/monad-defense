import Charts
import SwiftUI

/// M2: the bounded variability V(N) and the level L(N, M) of Eq. (3.1), with
/// the slope and the count error a fixed 0.05-octave level error implies.
struct ResponseWidget: View {
    @State private var levelView: Bool
    @State private var A = 4.0
    @State private var K = 3.0
    @State private var s = 1.0
    @State private var b = 0.0
    @State private var V0 = 1.0
    @State private var N = 2.0

    init(initialView: String) {
        _levelView = State(initialValue: initialView != "variability")
    }

    var body: some View {
        let y: (Double) -> Double = { n in
            levelView ? GuideMath.level(n, A: A, K: K, b: b, s: s) : GuideMath.variability(n, V0: V0, A: A, K: K)
        }
        let slope = levelView ? GuideMath.levelSlope(N, A: A, K: K, s: s) : GuideMath.variabilitySlope(N, A: A, K: K)
        let err = 0.05 / abs(slope)
        let ceiling = levelView ? b + 0.5 * log2(1 + A) : V0 + A
        WidgetLayout(
            formula: levelView
                ? "L(\(tex(N, 1)))=\(tex(b, 2))+\\tfrac12\\log_2[1+\(tex(A, 1))(1-e^{-\(tex(s, 2))\\cdot\(tex(N, 1))/\(tex(K, 1))})]=\(tex(y(N), 3))"
                : "V(\(tex(N, 1)))=\(tex(V0, 1))+\(tex(A, 1))(1-e^{-\(tex(N, 1))/\(tex(K, 1))})=\(tex(y(N), 3))",
            readout: levelView
                ? ["slope L_N = \(fmt(slope, 4)) oct/person", "0.05-octave level error → count error ±\(fmt(err, 2))"]
                : ["marginal response V′ = \(fmt(slope, 3)) per person"],
            words: "the orange band is how far a 0.05-octave level error moves the count: narrow where the curve is steep, wide on the plateau. Raise $s(M)$: the same people look like more people."
        ) {
            Chart {
                if levelView {
                    RectangleMark(xStart: .value("lo", max(0, N - err)), xEnd: .value("hi", min(15, N + err)))
                        .foregroundStyle(GuideColors.amber.opacity(0.18))
                }
                RuleMark(y: .value("ceiling", ceiling)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [4, 3]))
                ForEach(sample(0, 15, 200, y)) { p in
                    LineMark(x: .value("N", p.x), y: .value("y", p.y)).foregroundStyle(GuideColors.accent)
                }
                PointMark(x: .value("N", N), y: .value("y", y(N))).foregroundStyle(GuideColors.amber).symbolSize(80)
            }
            .chartXScale(domain: 0...15)
            .chartXAxisLabel("people N · dashed: ceiling")
            .chartYAxisLabel(levelView ? "level L (octaves)" : "variability V")
        } controls: {
            GChoice(label: "Curve", selection: $levelView, options: [(false, "V(N)"), (true, "L(N, M)")])
            GSlider(label: "Amplitude A", value: $A, range: 0.2...10, digits: 1)
            GSlider(label: "Knee K", value: $K, range: 0.5...20, unit: "people", digits: 1, log: true)
            if levelView {
                GSlider(label: "Movement s(M)", value: $s, range: 0.2...3)
                GSlider(label: "Reference b", value: $b, range: -0.5...1, unit: "oct")
            } else {
                GSlider(label: "Empty-room V₀", value: $V0, range: 0...3)
            }
            GSlider(label: "People N", value: $N, range: 0...15, digits: 1)
        }
    }
}
