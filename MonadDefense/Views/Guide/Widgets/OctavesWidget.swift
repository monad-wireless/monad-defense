import Charts
import SwiftUI

/// M0: log₂ counts doublings; ½ log₂ of a variance ratio is log₂ of the SD ratio.
struct OctavesWidget: View {
    @State private var ratio = 4.0
    @State private var variance = false

    var body: some View {
        let oct = variance ? 0.5 * log2(ratio) : log2(ratio)
        let db = (variance ? 10 : 20) * log10(ratio)
        WidgetLayout(
            formula: variance
                ? "\\tfrac12\\log_2 \(tex(ratio, 2))=\\log_2\\sqrt{\(tex(ratio, 2))}=\(tex(oct, 3))"
                : "\\log_2 \(tex(ratio, 2))=\(tex(oct, 3))\\ \\text{octaves}",
            readout: ["\(fmt(oct, 3)) octaves · \(fmt(db, 2)) dB"],
            words: "each doubling of an amplitude adds one octave and about 6 dB. A variance doubles when the amplitude grows by √2, so a variance doubling is half an octave of amplitude: that is why a level built from a variance carries a factor ½."
        ) {
            Chart {
                ForEach(sample(0.25, 16, 200) { log2($0) }) { p in
                    LineMark(x: .value("x", p.x), y: .value("y", p.y), series: .value("s", "log2"))
                        .foregroundStyle(.secondary)
                }
                ForEach(sample(0.25, 16, 200) { 0.5 * log2($0) }) { p in
                    LineMark(x: .value("x", p.x), y: .value("y", p.y), series: .value("s", "half"))
                        .foregroundStyle(GuideColors.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
                PointMark(x: .value("x", ratio), y: .value("y", oct))
                    .foregroundStyle(GuideColors.alt)
                    .symbolSize(90)
            }
            .chartXAxisLabel("ratio x · grey log₂ x · blue ½ log₂ x")
        } controls: {
            GSlider(label: "Ratio x", value: $ratio, range: 0.25...16, unit: "×", digits: 2, log: true)
            GChoice(label: "x is a ratio of", selection: $variance, options: [(false, "amplitudes"), (true, "variances")])
        }
    }
}
