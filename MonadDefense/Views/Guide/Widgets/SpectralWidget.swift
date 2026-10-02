import Charts
import SwiftUI

/// M2: off-DC band energy E and normalised second moment m₂ of a feature
/// spectrum. The spectrum is an illustration (DC peak + Gaussian motion lobe),
/// cut at the Nyquist limit fs/2.
struct SpectralWidget: View {
    @State private var motion = 0.4
    @State private var bw = 1.5
    @State private var fs = 25.0
    @State private var lo = 0.3
    @State private var hi = 6.0

    private func S(_ f: Double) -> Double {
        3 * exp(-0.5 * pow(f / 0.08, 2)) + motion * exp(-0.5 * pow(f / bw, 2))
    }

    /// Band energy and normalised second moment by a 0.01 Hz Riemann sum.
    private func moments(_ a: Double, _ b: Double) -> (E: Double, m2: Double) {
        var E = 0.0, M2 = 0.0
        var f = a
        while f < b {
            E += S(f) * 0.01
            M2 += f * f * S(f) * 0.01
            f += 0.01
        }
        return (E, E > 0 ? M2 / E : 0)
    }

    var body: some View {
        let fN = fs / 2
        let a = min(lo, hi), b = min(max(lo, hi), fN)
        let (E, m2) = moments(a, b)
        let visible = sample(0, fN, 300) { S($0) }
        WidgetLayout(
            formula: "E_{\\mathcal B}=\\int_{\(tex(a, 1))}^{\(tex(b, 1))}S(f)\\,df=\(tex(E, 3)),\\quad \\sqrt{m_2}=\(tex(m2.squareRoot(), 2))\\,\\mathrm{Hz}",
            readout: ["visible up to \(fmt(fN, 1)) Hz · band \(fmt(a, 2))–\(fmt(b, 2)) Hz"],
            words: "the DC spike is the still room and is excluded. Lower the delivered rate: fast motion falls beyond fs/2 and disappears from E and m₂. The band and the rate are part of the feature."
        ) {
            Chart {
                ForEach(visible.filter { $0.x >= a && $0.x <= b }) { p in
                    AreaMark(x: .value("f", p.x), y: .value("S", min(p.y, 1.2))).foregroundStyle(GuideColors.accent.opacity(0.2))
                }
                ForEach(visible) { p in
                    LineMark(x: .value("f", p.x), y: .value("S", min(p.y, 1.2))).foregroundStyle(GuideColors.accent)
                }
                RuleMark(x: .value("fN", fN)).foregroundStyle(GuideColors.alt).lineStyle(StrokeStyle(dash: [4, 3]))
            }
            .chartXScale(domain: 0...15)
            .chartYScale(domain: 0...1.2)
            .chartXAxisLabel("feature frequency f (Hz) · red: fs/2")
        } controls: {
            GSlider(label: "Motion energy", value: $motion, range: 0...1)
            GSlider(label: "Motion bandwidth", value: $bw, range: 0.1...6, unit: "Hz")
            GSlider(label: "Delivered rate fs", value: $fs, range: 4...100, unit: "Hz", digits: 1, log: true)
            GSlider(label: "Band from", value: $lo, range: 0.05...10, unit: "Hz")
            GSlider(label: "Band to", value: $hi, range: 0.1...15, unit: "Hz")
        }
    }
}
