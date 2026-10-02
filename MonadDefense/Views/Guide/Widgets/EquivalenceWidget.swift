import Charts
import SwiftUI

/// M0 / M4 / M5: is a difference distinguishable from zero, and is it inside
/// a practical margin? Presets are the thesis intervals (§5.5, §6.9.2, §6.10.1).
struct EquivalenceWidget: View {
    private struct Preset {
        let est: Double, lo: Double, hi: Double, margin: Double
        let unit: String, what: String
    }

    private static let presets: [String: Preset] = [
        "trigger": Preset(est: 0.034, lo: 0.002, hi: 0.066, margin: 0.05, unit: "persons", what: "MAE, trigger − fixed (90 % CI, six seeds)"),
        "balanced": Preset(est: -0.0031, lo: -0.0034, hi: -0.0027, margin: 0.1, unit: "persons/m²", what: "RMSE, smoothing − physics, balanced flow (95 % CI)"),
        "directed": Preset(est: -0.0023, lo: -0.0034, hi: -0.0013, margin: 0.1, unit: "persons/m²", what: "RMSE, smoothing − physics, directed flow (95 % CI)"),
        "band": Preset(est: 1.06, lo: 0.30, hi: 1.83, margin: 0.5, unit: "Hz", what: "delivered rate, 5 GHz − 2.4 GHz (95 % t CI, six pairs); the margin is an assumption"),
    ]

    @State private var preset: String
    @State private var est: Double
    @State private var half: Double
    @State private var margin: Double

    init(preset: String) {
        let key = preset == "continuity" ? "balanced" : (Self.presets[preset] == nil ? "trigger" : preset)
        let p = Self.presets[key]!
        _preset = State(initialValue: key)
        _est = State(initialValue: p.est)
        _half = State(initialValue: (p.hi - p.lo) / 2)
        _margin = State(initialValue: p.margin)
    }

    var body: some View {
        let p = Self.presets[preset]!
        let lo = est - half, hi = est + half
        let span = max(p.margin * 1.8, abs(lo) * 1.2, abs(hi) * 1.2)
        let excludesZero = lo > 0 || hi < 0
        let inside = lo > -margin && hi < margin
        let verdict = inside
            ? (excludesZero ? "distinguishable from zero, practically negligible" : "practically equivalent")
            : (excludesZero ? "different from zero, not shown to be negligible" : "inconclusive")
        let d = p.margin < 0.2 ? 4 : 2
        WidgetLayout(
            formula: "[\(tex(lo, d)),\\ \(tex(hi, d))]\\ \(inside ? "\\subset" : "\\nsubset")\\ (-\(tex(margin, d)),\\ \(tex(margin, d)))",
            readout: [verdict, p.what],
            words: "the whole interval must sit inside the shaded margin to claim no practical difference. Excluding zero is a separate question."
        ) {
            Chart {
                RectangleMark(xStart: .value("lo", -margin), xEnd: .value("hi", margin))
                    .foregroundStyle(GuideColors.accent.opacity(0.15))
                RuleMark(x: .value("0", 0)).foregroundStyle(.primary)
                RuleMark(xStart: .value("lo", lo), xEnd: .value("hi", hi), y: .value("y", 0.5))
                    .foregroundStyle(inside ? GuideColors.accent : GuideColors.alt)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                PointMark(x: .value("est", est), y: .value("y", 0.5))
                    .foregroundStyle(inside ? GuideColors.accent : GuideColors.alt)
                    .symbolSize(120)
            }
            .chartXScale(domain: -span...span)
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .chartXAxisLabel("difference (\(p.unit)) · shaded: margin ±Δ")
        } controls: {
            GChoice(label: "Thesis result", selection: $preset,
                    options: [("trigger", "trigger"), ("balanced", "cont. bal."), ("directed", "cont. dir."), ("band", "EXP-011")])
            GSlider(label: "Estimate", value: $est, range: -span...span, unit: p.unit, digits: d)
            GSlider(label: "CI half-width", value: $half, range: (p.margin / 200)...span, unit: p.unit, digits: d)
            GSlider(label: "Margin Δ", value: $margin, range: (p.margin / 200)...span, unit: p.unit, digits: d)
        }
        .onChange(of: preset) {
            let q = Self.presets[preset]!
            est = q.est
            half = (q.hi - q.lo) / 2
            margin = q.margin
        }
    }
}
