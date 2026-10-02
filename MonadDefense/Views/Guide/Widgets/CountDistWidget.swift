import Charts
import SwiftUI

/// M0 / M3: Poisson and negative-binomial counts. The device preset sets the
/// mean to d₀ + rN, the device emission of §3.9.
struct CountDistWidget: View {
    let devices: Bool
    @State private var meanDirect = 6.0
    @State private var N = 5.0
    @State private var r = 0.6
    @State private var d0 = 3.0
    @State private var phi = 4.0

    var body: some View {
        let mu = devices ? d0 + r * N.rounded() : meanDirect
        let variance = mu + mu * mu / phi
        let kMax = max(15, Int((mu + 4 * variance.squareRoot()).rounded(.up)))
        let ks = Array(0...kMax)
        WidgetLayout(
            formula: devices
                ? "\\mu=d_0+rN=\(tex(d0, 1))+\(tex(r, 2))\\cdot\(tex(N.rounded(), 0))=\(tex(mu, 2))"
                : "\\mathrm{Var}_{\\mathrm{NegBin}}=\\mu+\\frac{\\mu^2}{\\phi}=\(tex(variance, 2))",
            readout: ["mean \(fmt(mu, 2)) · NegBin variance \(fmt(variance, 2)) · Poisson variance \(fmt(mu, 2))"],
            words: devices
                ? "the mean depends on $N$ and $r$ only through $rN$. Double $N$ and halve $r$: the bars do not move. That is half of the scale symmetry of Eq. (3.2)."
                : "a small $\\phi$ spreads the counts far beyond the Poisson; a large $\\phi$ makes the two agree."
        ) {
            Chart {
                ForEach(ks, id: \.self) { k in
                    BarMark(x: .value("d", k), y: .value("p", GuideMath.negBinPmf(k, mu: mu, phi: phi)))
                        .foregroundStyle(GuideColors.accent.opacity(0.75))
                    PointMark(x: .value("d", k), y: .value("p", GuideMath.poissonPmf(k, mu)))
                        .foregroundStyle(GuideColors.alt)
                        .symbolSize(20)
                }
                RuleMark(x: .value("mean", mu)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [4, 3]))
            }
            .chartXAxisLabel("count d · bars NegBin · red dots Poisson")
        } controls: {
            if devices {
                GSlider(label: "People N", value: $N, range: 0...20, step: 1, digits: 0)
                GSlider(label: "Devices per person r", value: $r, range: 0...3)
                GSlider(label: "Background d₀", value: $d0, range: 0...15, step: 0.5, digits: 1)
            } else {
                GSlider(label: "Mean μ", value: $meanDirect, range: 0.5...25, step: 0.5, digits: 1)
            }
            GSlider(label: "Dispersion φ", value: $phi, range: 0.5...100, digits: 1, log: true)
        }
    }
}
