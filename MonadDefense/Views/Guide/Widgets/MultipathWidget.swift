import Charts
import SwiftUI

/// M1: H_k = Σ_p a_p e^(−j2πf_kτ_p) on the 52 HT20 tones of channel 48
/// (5,240 MHz). Three paths, direct, wall and body; the delays and amplitudes
/// are illustrative, not a surveyed ray trace.
struct MultipathWidget: View {
    @State private var tauBody = 32.0
    @State private var aBody = 0.45
    @State private var tauWall = 48.0
    @State private var aWall = 0.6

    static let tones = (-26...26).filter { $0 != 0 }

    static func ampDb(_ paths: [(Double, Double)]) -> [XY] {
        tones.enumerated().map { i, k in
            let f = 5.24e9 + Double(k) * 312.5e3
            var re = 0.0, im = 0.0
            for (a, tau) in paths {
                let ph = -2 * Double.pi * f * tau * 1e-9
                re += a * cos(ph)
                im += a * sin(ph)
            }
            return XY(id: i, x: Double(k) * 0.3125, y: 20 * log10(hypot(re, im) + 1e-9))
        }
    }

    var body: some View {
        let now = Self.ampDb([(1, 20), (aWall, tauWall), (aBody, tauBody)])
        let still = Self.ampDb([(1, 20), (aWall, tauWall)])
        WidgetLayout(
            formula: "H_k=e^{-j2\\pi f_k 20}+\(tex(aWall, 2))\\,e^{-j2\\pi f_k \(tex(tauWall, 1))}+\(tex(aBody, 2))\\,e^{-j2\\pi f_k \(tex(tauBody, 2))}",
            readout: ["body path \(fmt((tauBody - 20) * 29.98, 0)) cm longer than direct · 52 tones, 312.5 kHz apart"],
            words: "each path is an arrow that turns at its own rate across the subcarriers. A body moving a few centimetres reshapes the dips. The receiver sees the reshaping, not the number of bodies."
        ) {
            Chart {
                ForEach(still) { p in
                    LineMark(x: .value("MHz", p.x), y: .value("dB", p.y), series: .value("s", "still"))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 3]))
                }
                ForEach(now) { p in
                    LineMark(x: .value("MHz", p.x), y: .value("dB", p.y), series: .value("s", "body"))
                        .foregroundStyle(GuideColors.accent)
                    PointMark(x: .value("MHz", p.x), y: .value("dB", p.y))
                        .foregroundStyle(GuideColors.accent)
                        .symbolSize(10)
                }
            }
            .chartYScale(domain: -25...10)
            .chartXAxisLabel("subcarrier offset (MHz) · grey without the body path")
            .chartYAxisLabel("|H_k| (dB)")
        } controls: {
            GSlider(label: "Body path delay", value: $tauBody, range: 21...60, unit: "ns", digits: 2)
            GSlider(label: "Body path amplitude", value: $aBody, range: 0...0.9)
            GSlider(label: "Wall path delay", value: $tauWall, range: 21...80, unit: "ns", digits: 1)
            GSlider(label: "Wall path amplitude", value: $aWall, range: 0...0.9)
        }
    }
}
