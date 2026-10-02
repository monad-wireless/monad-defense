import Charts
import SwiftUI

/// M1: stored CSI = g_r H e^(j[φ + kψ + δ_r]) + noise. Each frame draws a new
/// φ, ψ and gain; the chain ratio cancels what both chains share. Channel and
/// impairment sizes are illustrative, the same as in the deck widget.
struct ImpairmentsWidget: View {
    @State private var ratio: Bool
    @State private var frame = 0.0
    @State private var psiMax = 0.12
    @State private var sharedTiming = true

    init(initialView: String) {
        _ratio = State(initialValue: initialView == "ratio")
    }

    private static let paths1: [(Double, Double)] = [(1, 20), (0.6, 48), (0.45, 32)]
    private static let paths2: [(Double, Double)] = [(1, 20.05), (0.55, 47.6), (0.5, 32.3)]
    private static let delta = (0.4, -0.9)

    private static func H(_ k: Int, _ paths: [(Double, Double)]) -> (Double, Double) {
        let f = 5.24e9 + Double(k) * 312.5e3
        var re = 0.0, im = 0.0
        for (a, tau) in paths {
            let ph = -2 * Double.pi * f * tau * 1e-9
            re += a * cos(ph)
            im += a * sin(ph)
        }
        return (re, im)
    }

    private static func angle(_ z: (Double, Double)) -> Double { atan2(z.1, z.0) }

    var body: some View {
        var rng = SeededRandom(seed: UInt32(1000 + Int(frame)))
        let phi = (rng.uniform() * 2 - 1) * .pi
        let psi = (rng.uniform() * 2 - 1) * psiMax
        let psi2 = sharedTiming ? psi : (rng.uniform() * 2 - 1) * psiMax
        let gDb = (rng.uniform() * 2 - 1) * 3
        let wrap = { (p: Double) in atan2(sin(p), cos(p)) }
        let tones = MultipathWidget.tones
        let truth: [XY] = tones.enumerated().map { i, k in
            let h1 = Self.H(k, Self.paths1), h2 = Self.H(k, Self.paths2)
            let y = ratio ? wrap(Self.angle(h1) - Self.angle(h2) + Self.delta.0 - Self.delta.1) : Self.angle(h1)
            return XY(id: i, x: Double(k) * 0.3125, y: y)
        }
        let stored: [XY] = tones.enumerated().map { i, k in
            let h1 = Self.H(k, Self.paths1), h2 = Self.H(k, Self.paths2)
            let raw1 = Self.angle(h1) + phi + Double(k) * psi + Self.delta.0
            let raw2 = Self.angle(h2) + phi + Double(k) * psi2 + Self.delta.1
            return XY(id: i, x: Double(k) * 0.3125, y: wrap(ratio ? raw1 - raw2 : raw1))
        }
        WidgetLayout(
            formula: "\\phi=\(tex(phi, 2)),\\ \\psi=\(tex(psi, 3)),\\ g=\(tex(gDb, 1))\\,\\mathrm{dB}",
            readout: [ratio ? "the ratio keeps H₁/H₂ and a fixed offset" : "the stored phase is mostly instrument"],
            words: "φ and ψ change every frame and swamp the true phase. Dividing two chains cancels them, if both chains carry them. Give chain 2 its own timing and the ratio inherits a slope again."
        ) {
            Chart {
                ForEach(truth) { p in
                    LineMark(x: .value("MHz", p.x), y: .value("rad", p.y), series: .value("s", "true"))
                        .foregroundStyle(.secondary)
                }
                ForEach(stored) { p in
                    PointMark(x: .value("MHz", p.x), y: .value("rad", p.y))
                        .foregroundStyle(ratio ? GuideColors.accent : GuideColors.alt)
                        .symbolSize(16)
                }
            }
            .chartYScale(domain: -3.3...3.3)
            .chartXAxisLabel(ratio ? "grey: true H₁/H₂ · blue: stored ratio" : "grey: true phase · red: stored, this frame")
            .chartYAxisLabel("phase (rad)")
        } controls: {
            GChoice(label: "Show", selection: $ratio, options: [(false, "one chain, raw"), (true, "chain ratio")])
            GSlider(label: "Frame", value: $frame, range: 0...30, step: 1, digits: 0)
            GSlider(label: "Timing slope range", value: $psiMax, range: 0...0.3, unit: "rad/tone", digits: 3)
            GChoice(label: "Chain 2 timing", selection: $sharedTiming, options: [(true, "shared ψ"), (false, "its own ψ′")])
        }
    }
}
