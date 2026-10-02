import Charts
import SwiftUI

/// M3: Eq. (3.2). (N, K, r) ↦ (cN, cK, r/c) leaves the CSI law (through N/K)
/// and the device mean (rN) unchanged. Defaults are those of Fig. 3.4a–b.
struct ScaleSymmetryWidget: View {
    @State private var c = 2.0
    @State private var K = 3.0
    @State private var r = 0.6
    @State private var device = false

    var body: some View {
        let A = 4.0
        let world1 = sample(0, 8, 100) { device ? r * $0 : GuideMath.level($0, A: A, K: K) }
        let world2 = sample(0, 8, 100) { device ? (r / c) * (c * $0) : GuideMath.level(c * $0, A: A, K: c * K) }
        let maxDiff = (0...8).map { abs(GuideMath.level(Double($0), A: A, K: K) - GuideMath.level(c * Double($0), A: A, K: c * K)) }.max() ?? 0
        WidgetLayout(
            formula: "(5,\\ \(tex(K, 1)),\\ \(tex(r, 2)))\\longmapsto(\(tex(5 * c, 2)),\\ \(tex(c * K, 2)),\\ \(tex(r / c, 3)))",
            readout: ["both worlds: N/K = \(fmt(5 / K, 3)), rN = \(fmt(5 * r, 2))", "largest level difference over N = 0…8: \(sig(maxDiff)) oct"],
            words: "move $c$ anywhere. World 2 has $c$ times the people, and both observation laws stay on top of world 1. No amount of CSI and device data separates them."
        ) {
            Chart {
                ForEach(world1) { p in
                    LineMark(x: .value("N", p.x), y: .value("y", p.y), series: .value("s", "1"))
                        .foregroundStyle(GuideColors.accent.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 8))
                }
                ForEach(world2) { p in
                    LineMark(x: .value("N", p.x), y: .value("y", p.y), series: .value("s", "2"))
                        .foregroundStyle(.primary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
            }
            .chartXAxisLabel("original count N · wide: world 1 · dashed: world 2")
            .chartYAxisLabel(device ? "expected devices" : "CSI level (octaves)")
        } controls: {
            GChoice(label: "Law", selection: $device, options: [(false, "CSI law (a)"), (true, "device law (b)")])
            GSlider(label: "Scale c", value: $c, range: 0.25...4, unit: "×", log: true)
            GSlider(label: "Knee K (world 1)", value: $K, range: 0.5...10, unit: "people", digits: 1)
            GSlider(label: "Devices per person r", value: $r, range: 0.1...2)
        }
    }
}
