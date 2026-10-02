import Charts
import SwiftUI

/// M0: a delayed copy of a wave is a phase shift 2πfτ.
struct WavePhaseWidget: View {
    @State private var fGHz = 5.24
    @State private var tauNs = 0.1

    var body: some View {
        let c = 299_792_458.0
        let cycles = fGHz * tauNs
        let deg = (cycles * 360).truncatingRemainder(dividingBy: 360)
        let span = 2.2 / fGHz
        WidgetLayout(
            formula: "2\\pi f\\tau=2\\pi\\cdot\(tex(fGHz, 2))\\,\\mathrm{GHz}\\cdot\(tex(tauNs, 3))\\,\\mathrm{ns}=\(tex(cycles, 3))\\ \\text{cycles}",
            readout: [
                "wavelength \(fmt(c / (fGHz * 1e9) * 100, 2)) cm · extra path \(fmt(c * tauNs * 1e-9 * 100, 1)) cm",
                "phase shift \(fmt(deg, 0))°",
            ],
            words: "a delay of one period (about 0.19 ns at 5.24 GHz, a 5.7 cm longer path) brings the copy back into step. The same delay gives a different phase at a different frequency."
        ) {
            Chart {
                ForEach(sample(0, span, 240) { cos(2 * .pi * fGHz * $0) }) { p in
                    LineMark(x: .value("t", p.x), y: .value("a", p.y), series: .value("s", "direct"))
                        .foregroundStyle(.secondary)
                }
                ForEach(sample(0, span, 240) { cos(2 * .pi * fGHz * ($0 - tauNs)) }) { p in
                    LineMark(x: .value("t", p.x), y: .value("a", p.y), series: .value("s", "delayed"))
                        .foregroundStyle(GuideColors.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
            }
            .chartYScale(domain: -1.2...1.2)
            .chartXAxisLabel("time (ns) · grey direct · blue delayed by τ")
        } controls: {
            GSlider(label: "Frequency f", value: $fGHz, range: 2.4...5.9, unit: "GHz", digits: 2)
            GSlider(label: "Extra delay τ", value: $tauNs, range: 0...1, unit: "ns", digits: 3)
        }
    }
}
