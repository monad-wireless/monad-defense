import Charts
import SwiftUI

/// M3: one positive anchor (N_a, L_a) with b = 0 fixes A(K) for every knee and
/// leaves a family of curves. Defaults: N_a = 3, L_a = 1.12 octaves, knee grid
/// 0.5–20 (§3.9.1, Fig. 3.4c); L(8) then ranges 1.121–1.647 octaves.
struct AnchorFamilyWidget: View {
    @State private var K = 3.0
    @State private var Na = 3.0
    @State private var La = 1.12
    @State private var at = 8.0

    var body: some View {
        let A = GuideMath.amplitudeThroughAnchor(K, Na: Na, La: La)
        let family = GuideMath.kneeGrid.map { ($0, GuideMath.amplitudeThroughAnchor($0, Na: Na, La: La)) }
        let envelope: [(x: Double, lo: Double, hi: Double)] = (0...120).map { i in
            let n = 12 * Double(i) / 120
            let v = family.map { GuideMath.level(n, A: $0.1, K: $0.0) }
            return (n, v.min() ?? 0, v.max() ?? 0)
        }
        let atValues = family.map { GuideMath.level(at, A: $0.1, K: $0.0) }
        WidgetLayout(
            formula: "A(K)=\\frac{2^{2\\cdot\(tex(La, 2))}-1}{1-e^{-\(tex(Na, 0))/\(tex(K, 2))}}=\(tex(A, 3)),\\quad L(\(tex(at, 0)))=\(tex(GuideMath.level(at, A: A, K: K), 3))",
            readout: ["over K = 0.5–20, L(\(Int(at))) ranges \(fmt(atValues.min() ?? 0, 3))–\(fmt(atValues.max() ?? 0, 3)) oct"],
            words: "the shaded band is every curve the two anchors allow. At the default anchor, the level at 8 people can be anything from 1.121 to 1.647 octaves. One headcount fixes a point, not the curve."
        ) {
            Chart {
                ForEach(Array(envelope.enumerated()), id: \.offset) { _, e in
                    AreaMark(x: .value("N", e.x), yStart: .value("lo", e.lo), yEnd: .value("hi", e.hi))
                        .foregroundStyle(GuideColors.accent.opacity(0.15))
                }
                ForEach(sample(0, 12, 160) { GuideMath.level($0, A: A, K: K) }) { p in
                    LineMark(x: .value("N", p.x), y: .value("L", p.y)).foregroundStyle(GuideColors.accent)
                }
                RuleMark(x: .value("at", at)).foregroundStyle(GuideColors.alt).lineStyle(StrokeStyle(dash: [4, 3]))
                PointMark(x: .value("N", 0), y: .value("L", 0)).foregroundStyle(.primary)
                PointMark(x: .value("N", Na), y: .value("L", La)).foregroundStyle(.primary).symbolSize(90)
            }
            .chartXScale(domain: 0...12)
            .chartYScale(domain: 0...2)
            .chartXAxisLabel("assumed occupancy (people) · dots: empty and positive anchor")
        } controls: {
            GSlider(label: "Knee K", value: $K, range: 0.5...20, unit: "people", log: true)
            GSlider(label: "Anchor count N_a", value: $Na, range: 1...6, step: 1, unit: "people", digits: 0)
            GSlider(label: "Anchor level L_a", value: $La, range: 0.3...1.6, unit: "oct")
            GSlider(label: "Predict at N", value: $at, range: 1...12, step: 1, unit: "people", digits: 0)
        }
    }
}
