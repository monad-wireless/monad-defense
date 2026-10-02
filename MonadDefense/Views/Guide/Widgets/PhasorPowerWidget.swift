import Charts
import SwiftUI

/// M2: E|Σ a e^(jφᵢ)|² = N a² for independent uniform phases. Seeded Monte
/// Carlo, 400 draws per N, the same seeds as the deck widget.
struct PhasorPowerWidget: View {
    @State private var N = 6.0
    @State private var a = 1.0

    var body: some View {
        let points: [XY] = (1...20).map { n in
            var rng = SeededRandom(seed: UInt32(77 + n))
            var total = 0.0
            for _ in 0..<400 {
                var re = 0.0, im = 0.0
                for _ in 0..<n {
                    let p = 2 * Double.pi * rng.uniform()
                    re += a * cos(p)
                    im += a * sin(p)
                }
                total += re * re + im * im
            }
            return XY(id: n, x: Double(n), y: total / 400)
        }
        let n = Int(N)
        WidgetLayout(
            formula: "\\mathbb{E}\\Big|\\sum_{i=1}^{\(n)}a\\,e^{j\\varphi_i}\\Big|^2=\(n)\\cdot\(tex(a, 2))^2=\(tex(Double(n) * a * a, 2))",
            readout: ["Monte Carlo mean at N = \(n): \(fmt(points[n - 1].y, 2))"],
            words: "one draw can be large or small; the average over draws grows in a straight line. Random independent phasors do not saturate. A flattening response needs another mechanism."
        ) {
            Chart {
                LineMark(x: .value("N", 0), y: .value("P", 0), series: .value("s", "theory"))
                    .foregroundStyle(.secondary)
                LineMark(x: .value("N", 20.5), y: .value("P", 20.5 * a * a), series: .value("s", "theory"))
                    .foregroundStyle(.secondary)
                ForEach(points) { p in
                    PointMark(x: .value("N", p.x), y: .value("P", p.y))
                        .foregroundStyle(Int(p.x) == n ? GuideColors.alt : GuideColors.accent)
                        .symbolSize(Int(p.x) == n ? 90 : 30)
                }
            }
            .chartXAxisLabel("scatterers N · grey line N·a²")
            .chartYAxisLabel("mean power")
        } controls: {
            GSlider(label: "Scatterers N", value: $N, range: 1...20, step: 1, digits: 0)
            GSlider(label: "Amplitude a", value: $a, range: 0.3...1.5)
        }
    }
}
