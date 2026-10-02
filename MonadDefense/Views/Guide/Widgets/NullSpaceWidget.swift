import Charts
import SwiftUI

/// M4: one link sees two zones, y = h₁n₁ + h₂n₂. With h₁ = h₂ the move
/// (−1, +1) is in the null space: the zones are not identified, the total is.
struct NullSpaceWidget: View {
    @State private var h1 = 1.0
    @State private var h2 = 1.0
    @State private var n1 = 2.0
    @State private var n2 = 3.0
    @State private var eps = 0.25

    private static let grid: [(Int, Int)] = (0...8).flatMap { (a: Int) -> [(Int, Int)] in (0...8).map { (a, $0) } }

    private func fitting(_ y: Double) -> [(Int, Int)] {
        Self.grid.filter { (p: (Int, Int)) -> Bool in
            let predicted = h1 * Double(p.0) + h2 * Double(p.1)
            return abs(predicted - y) <= eps
        }
    }

    var body: some View {
        let y = h1 * n1 + h2 * n2
        let grid = Self.grid
        let fits = fitting(y)
        let totals: [Int] = Array(Set(fits.map { $0.0 + $0.1 })).sorted()
        WidgetLayout(
            formula: "y=\(tex(h1, 2))\\,n_1+\(tex(h2, 2))\\,n_2=\(tex(y, 2))",
            readout: ["\(fits.count) zone splits fit · totals among them: \(totals.map(String.init).joined(separator: ", "))",
                      "the move v = (−1, +1) is invisible exactly when h₁ = h₂"],
            words: "with equal sensitivities every fitting split has the same total: the count is identified, the zones are not. Make the sensitivities differ and the fitting splits disagree about the total too."
        ) {
            Chart {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, p in
                    PointMark(x: .value("n1", p.0), y: .value("n2", p.1))
                        .foregroundStyle(.secondary.opacity(0.25))
                        .symbolSize(10)
                }
                ForEach(Array(fits.enumerated()), id: \.offset) { _, p in
                    PointMark(x: .value("n1", p.0), y: .value("n2", p.1))
                        .foregroundStyle(GuideColors.accent)
                        .symbolSize(70)
                }
                PointMark(x: .value("n1", n1), y: .value("n2", n2))
                    .symbol(.square)
                    .foregroundStyle(GuideColors.alt)
                    .symbolSize(110)
            }
            .chartXScale(domain: -0.5...8.5)
            .chartYScale(domain: -0.5...8.5)
            .chartXAxisLabel("people in zone 1 · red: truth · blue: splits that fit")
            .chartYAxisLabel("zone 2")
        } controls: {
            GSlider(label: "Sensitivity to zone 1", value: $h1, range: 0...2)
            GSlider(label: "Sensitivity to zone 2", value: $h2, range: 0...2)
            GSlider(label: "True n₁", value: $n1, range: 0...8, step: 1, digits: 0)
            GSlider(label: "True n₂", value: $n2, range: 0...8, step: 1, digits: 0)
            GSlider(label: "Measurement tolerance", value: $eps, range: 0.01...1)
        }
    }
}
