import Charts
import SwiftUI

/// M4: R(d) = R(d₀) − 10n log₁₀(d/d₀) + ε. Inverting a measured RSSI with a
/// shadowing SD gives a distance interval. R(d₀) = −60 dBm at 1 m is an
/// illustrative BLE value, not a fleet calibration.
struct PathLossWidget: View {
    @State private var n = 2.2
    @State private var shadow = 4.0
    @State private var measured = -75.0

    var body: some View {
        let R0 = -60.0
        let curve = sample(0.5, 20, 200) { R0 - 10 * n * log10($0) }
        let dHat = pow(10, (R0 - measured) / (10 * n))
        let dLo = pow(10, (R0 - measured - 1.645 * shadow) / (10 * n))
        let dHi = pow(10, (R0 - measured + 1.645 * shadow) / (10 * n))
        WidgetLayout(
            formula: "\\hat d=10^{\\frac{R(d_0)-R}{10n}}=10^{\\frac{-60-(\(tex(measured, 0)))}{10\\cdot\(tex(n, 1))}}=\(tex(dHat, 2))\\,\\mathrm{m}",
            readout: ["90 % interval \(fmt(dLo, 1))–\(fmt(dHi, 1)) m"],
            words: "distance sits inside a logarithm, so ±4 dB of shadowing is a factor of distance, not a few centimetres. A point estimate without this interval is the \"unjustifiably precise location\" of §4.9."
        ) {
            Chart {
                RectangleMark(xStart: .value("lo", dLo), xEnd: .value("hi", min(dHi, 20)))
                    .foregroundStyle(GuideColors.amber.opacity(0.18))
                ForEach(curve) { p in
                    AreaMark(x: .value("d", p.x), yStart: .value("lo", p.y - 1.645 * shadow), yEnd: .value("hi", p.y + 1.645 * shadow))
                        .foregroundStyle(GuideColors.accent.opacity(0.12))
                    LineMark(x: .value("d", p.x), y: .value("R", p.y)).foregroundStyle(GuideColors.accent)
                }
                RuleMark(y: .value("measured", measured)).foregroundStyle(GuideColors.alt).lineStyle(StrokeStyle(dash: [4, 3]))
                RuleMark(x: .value("dHat", dHat)).foregroundStyle(GuideColors.alt)
            }
            .chartXScale(domain: 0...20)
            .chartYScale(domain: -110...(-45))
            .chartXAxisLabel("distance d (m) · orange: distances the RSSI allows")
            .chartYAxisLabel("RSSI (dBm)")
        } controls: {
            GSlider(label: "Exponent n", value: $n, range: 1.6...4)
            GSlider(label: "Shadowing SD", value: $shadow, range: 0.5...10, unit: "dB", digits: 1)
            GSlider(label: "Measured RSSI", value: $measured, range: -100...(-50), step: 1, unit: "dBm", digits: 0)
        }
    }
}
