import SwiftUI

/// M4: F(S) = Σ_z w_z max_{ℓ∈S} c_ℓz on an illustrative 10 × 6 zone grid with
/// nine candidate receivers; greedy against the brute-force optimum.
/// Submodularity guarantees F(greedy) ≥ (1 − 1/e) F(optimum).
struct CoverageGreedyWidget: View {
    @State private var k = 2.0
    @State private var reach = 2.2

    private struct Zone { let x: Double, y: Double, w: Double }

    private static let zones: [Zone] = (0..<10).flatMap { i in
        (0..<6).map { j in
            let x = Double(i), y = Double(j)
            let hot = exp(-(pow(x - 2, 2) + pow(y - 1.5, 2)) / 4) + 0.8 * exp(-(pow(x - 7.5, 2) + pow(y - 4, 2)) / 3)
            return Zone(x: x + 0.5, y: y + 0.5, w: 0.15 + hot)
        }
    }
    private static let candidates: [(Double, Double)] = [(1, 1), (3, 2), (5, 1), (8, 1), (2, 4.5), (5, 3.5), (7.5, 4), (9, 5), (5, 5.5)]

    private func cover(_ c: (Double, Double), _ z: Zone) -> Double { exp(-hypot(c.0 - z.x, c.1 - z.y) / reach) }

    private func F(_ set: [Int]) -> Double {
        guard !set.isEmpty else { return 0 }
        return Self.zones.reduce(0) { acc, z in acc + z.w * set.map { cover(Self.candidates[$0], z) }.max()! }
    }

    private func combos(_ n: Int, _ r: Int, _ start: Int = 0) -> [[Int]] {
        if r == 0 { return [[]] }
        guard start < n else { return [] }
        return (start..<n).flatMap { i in combos(n, r - 1, i + 1).map { [i] + $0 } }
    }

    private func greedyPick(_ kk: Int) -> [Int] {
        var greedy: [Int] = []
        for _ in 0..<kk {
            let best = (0..<Self.candidates.count).filter { !greedy.contains($0) }.max { F(greedy + [$0]) < F(greedy + [$1]) }!
            greedy.append(best)
        }
        return greedy
    }

    var body: some View {
        let kk = Int(k)
        let greedy = greedyPick(kk)
        let optimum = combos(Self.candidates.count, kk).max { F($0) < F($1) } ?? []
        let ratio = F(greedy) / F(optimum)
        WidgetLayout(
            formula: "\\frac{F(S_{\\mathrm{greedy}})}{F(S^\\star)}=\(tex(ratio, 3))\\ \\ge\\ 1-1/e=0.632",
            readout: ["greedy order: " + greedy.map { "\($0 + 1)" }.joined(separator: " → ")],
            words: "each new receiver adds less coverage than the one before (submodularity), which is why picking the best next one is never far from the best set. The guarantee is about this score, not about counting accuracy."
        ) {
            Canvas { ctx, size in
                let s = min(size.width / 10, size.height / 6.4)
                for z in Self.zones {
                    let c = greedy.isEmpty ? 0 : greedy.map { cover(Self.candidates[$0], z) }.max()!
                    let rect = CGRect(x: (z.x - 0.5) * s, y: (z.y - 0.5) * s, width: s - 1, height: s - 1)
                    ctx.fill(Path(rect), with: .color(GuideColors.accent.opacity(0.06 + 0.5 * c)))
                    ctx.draw(Text(fmt(z.w, 1)).font(.system(size: 8)).foregroundStyle(.secondary), at: CGPoint(x: z.x * s, y: z.y * s))
                }
                for (i, c) in Self.candidates.enumerated() {
                    let p = CGPoint(x: c.0 * s, y: c.1 * s)
                    let dot = Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
                    ctx.fill(dot, with: .color(greedy.contains(i) ? GuideColors.alt : .white))
                    ctx.stroke(dot, with: .color(.primary), lineWidth: 1.2)
                    if optimum.contains(i) {
                        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)),
                                   with: .color(.green), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text("red: greedy · green ring: best set · numbers: zone weight").font(.caption2).foregroundStyle(.secondary)
            }
        } controls: {
            GSlider(label: "Receivers k", value: $k, range: 1...5, step: 1, digits: 0)
            GSlider(label: "Coverage reach", value: $reach, range: 0.6...5, unit: "cells", digits: 1)
        }
    }
}
