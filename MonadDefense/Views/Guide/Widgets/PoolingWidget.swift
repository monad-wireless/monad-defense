import Charts
import SwiftUI

/// M2: partial pooling of per-environment slopes. SYNTHETIC environments with
/// the row counts of the thesis's public cache (300, 300, 300, 10, 9, 10, 10);
/// the slopes are invented, the same draws as the deck widget.
struct PoolingWidget: View {
    @State private var tau = 0.4
    @State private var sigma = 3.0
    @State private var seed = 3.0

    private static let rows = [300.0, 300, 300, 10, 9, 10, 10]
    private static let names = ["W1", "W2", "W3", "M1", "M2", "M3", "M4"]

    var body: some View {
        var r1 = SeededRandom(seed: UInt32(900 + Int(seed)))
        let truth = Self.rows.map { _ in 2 + 0.4 * r1.normal() }
        var r2 = SeededRandom(seed: UInt32(1900 + Int(seed)))
        let own = truth.enumerated().map { i, b in b + sigma / Self.rows[i].squareRoot() * r2.normal() }
        let w = Self.rows.map { 1 / (sigma * sigma / $0 + tau * tau) }
        let mu = zip(own, w).reduce(0) { $0 + $1.0 * $1.1 } / w.reduce(0, +)
        let weight = Self.rows.map { n in (n / (sigma * sigma)) / (n / (sigma * sigma) + 1 / (tau * tau)) }
        let pooled = own.enumerated().map { i, b in weight[i] * b + (1 - weight[i]) * mu }
        WidgetLayout(
            formula: "\\tilde\\beta_e=w_e\\hat\\beta_e+(1-w_e)\\hat\\mu,\\quad w_e=\\frac{n_e/\\sigma^2}{n_e/\\sigma^2+1/\\tau^2}",
            readout: ["weight: 300-row env \(fmt(weight[0], 2)) · 9-row env \(fmt(weight[4], 2))"],
            words: "the 300-row environments keep their own slope; the 9- and 10-row environments are pulled toward the group. Shrink τ to complete pooling, grow it to no pooling. The row counts are the cache's; the slopes are invented."
        ) {
            Chart {
                RuleMark(y: .value("mu", mu)).foregroundStyle(GuideColors.alt).lineStyle(StrokeStyle(dash: [4, 3]))
                ForEach(0..<7, id: \.self) { i in
                    PointMark(x: .value("env", Self.names[i]), y: .value("own", own[i]))
                        .symbol(.circle)
                        .foregroundStyle(GuideColors.accent.opacity(0.35))
                    PointMark(x: .value("env", Self.names[i]), y: .value("pooled", pooled[i]))
                        .foregroundStyle(GuideColors.accent)
                    PointMark(x: .value("env", Self.names[i]), y: .value("truth", truth[i]))
                        .symbol(.cross)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: 0...4.5)
            .chartXAxisLabel("pale: own fit · solid: pooled · cross: true · red: group mean")
        } controls: {
            GSlider(label: "Between-env spread τ", value: $tau, range: 0.02...5, log: true)
            GSlider(label: "Row noise σ", value: $sigma, range: 0.5...8, digits: 1)
            GSlider(label: "Draw", value: $seed, range: 0...20, step: 1, digits: 0)
        }
    }
}
