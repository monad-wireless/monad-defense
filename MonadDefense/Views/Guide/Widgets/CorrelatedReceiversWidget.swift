import Charts
import SwiftUI

/// M5, §6.6.1: the mean of n equally correlated errors.
/// Var = σ²(1 + (n − 1)ρ)/n and n_eff = n/(1 + (n − 1)ρ). The fleet's
/// forecast errors correlated across receivers at 0.60 to 0.97.
struct CorrelatedReceiversWidget: View {
    @State private var n = 10.0
    @State private var rho = 0.6

    /// Histogram of 3,000 seeded averages, in 0.15-σ bins over [−3, 3).
    private func histogram(_ nn: Int) -> [Double] {
        var rng = SeededRandom(seed: 42)
        var bins = [Double](repeating: 0, count: 40)
        for _ in 0..<3000 {
            let common = rng.normal()
            var s = 0.0
            for _ in 0..<nn { s += rho.squareRoot() * common + (1 - rho).squareRoot() * rng.normal() }
            let b = Int(((s / Double(nn)) + 3) / 0.15)
            if b >= 0 && b < 40 { bins[b] += 1 }
        }
        return bins
    }

    var body: some View {
        let nn = Int(n)
        let (factor, nEff) = GuideMath.correlatedMean(n: nn, rho: rho)
        let sdTrue = factor.squareRoot()
        let sdNaive = 1 / Double(nn).squareRoot()
        let bins = histogram(nn)
        WidgetLayout(
            formula: "\\operatorname{Var}(\\bar\\epsilon)=\\frac{1+(\(nn)-1)\\cdot\(tex(rho, 2))}{\(nn)}\\sigma^2=\(tex(factor, 3))\\,\\sigma^2,\\quad n_{\\mathrm{eff}}=\(tex(nEff, 2))",
            readout: ["true SD \(fmt(sdTrue, 3)) σ · if independent \(fmt(sdNaive, 3)) σ"],
            words: "the red curve is what a likelihood that multiplies receivers as independent believes. With the fleet's correlations, ten receivers are worth one or two, and the posterior it reports is too narrow."
        ) {
            Chart {
                ForEach(0..<40, id: \.self) { i in
                    BarMark(x: .value("e", -3 + 0.15 * (Double(i) + 0.5)), y: .value("d", bins[i] / (3000 * 0.15)), width: .fixed(6))
                        .foregroundStyle(GuideColors.accent.opacity(0.3))
                }
                ForEach(sample(-3, 3, 150) { GuideMath.normPdf($0, sd: sdTrue) }) { p in
                    LineMark(x: .value("e", p.x), y: .value("d", p.y), series: .value("s", "true")).foregroundStyle(GuideColors.accent)
                }
                ForEach(sample(-3, 3, 150) { GuideMath.normPdf($0, sd: sdNaive) }) { p in
                    LineMark(x: .value("e", p.x), y: .value("d", p.y), series: .value("s", "naive"))
                        .foregroundStyle(GuideColors.alt)
                        .lineStyle(StrokeStyle(dash: [5, 3]))
                }
            }
            .chartXScale(domain: -3...3)
            .chartXAxisLabel("averaged error (σ units) · blue true · red if independent")
        } controls: {
            GSlider(label: "Receivers n", value: $n, range: 1...20, step: 1, digits: 0)
            GSlider(label: "Error correlation ρ", value: $rho, range: 0...0.99)
            GChoice(label: "Fleet range", selection: $rho, options: [(0.6, "ρ = 0.60"), (0.97, "ρ = 0.97"), (0.0, "independent")])
        }
    }
}
