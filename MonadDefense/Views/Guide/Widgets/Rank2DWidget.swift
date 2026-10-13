import SwiftUI

/// M0: two linear measurements of (x, y). One leaves a line of answers; two at
/// a shallow angle leave a long thin sliver. Condition number = cot(θ/2).
struct Rank2DWidget: View {
    @State private var angle = 60.0
    @State private var noise = 0.15
    @State private var two = true

    var body: some View {
        let theta = angle * .pi / 180
        let cond = 1 / tan(theta / 2)
        let area = 4 * noise * noise / sin(theta)
        let noise = self.noise
        let two = self.two
        WidgetLayout(
            formula: two
                ? "\\kappa=\\cot\\tfrac{\\theta}{2}=\(tex(cond, 2)),\\quad \\text{area}=\\frac{4\\epsilon^2}{\\sin\\theta}=\(tex(area, 3))"
                : "\\operatorname{rank}=1",
            readout: [two ? "identified · condition number \(fmt(cond, 2))" : "not identified: a whole line fits"],
            words: "one measurement leaves a line. Two cut it to a point, but a shallow angle stretches the overlap into a sliver: identified in principle, poorly conditioned in practice. Two measurements that react almost alike behave like a shallow angle."
        ) {
            Canvas { ctx, size in
                let s = min(size.width, size.height) / 3
                let o = CGPoint(x: size.width / 2, y: size.height / 2)
                func band(_ n: CGPoint, _ color: Color) {
                    let t = CGPoint(x: -n.y, y: n.x)
                    var p = Path()
                    for (k, sgn) in [(-6.0, 1.0), (6.0, 1.0), (6.0, -1.0), (-6.0, -1.0)].enumerated().map({ $0.element }) {
                        let pt = CGPoint(x: o.x + s * (k * t.x + sgn * noise * n.x), y: o.y - s * (k * t.y + sgn * noise * n.y))
                        if p.isEmpty { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    p.closeSubpath()
                    ctx.fill(p, with: .color(color.opacity(0.25)))
                    var l = Path()
                    l.move(to: CGPoint(x: o.x - s * 6 * t.x, y: o.y + s * 6 * t.y))
                    l.addLine(to: CGPoint(x: o.x + s * 6 * t.x, y: o.y - s * 6 * t.y))
                    ctx.stroke(l, with: .color(color), lineWidth: 2)
                }
                band(CGPoint(x: 0, y: 1), GuideColors.accent)
                if two { band(CGPoint(x: sin(theta), y: cos(theta)), GuideColors.alt) }
                ctx.fill(Path(ellipseIn: CGRect(x: o.x - 4, y: o.y - 4, width: 8, height: 8)), with: .color(.primary))
            }
            .overlay(alignment: .topLeading) {
                Text("blue: measurement 1 · red: measurement 2 · dot: truth").font(.caption2).foregroundStyle(.secondary)
            }
        } controls: {
            GChoice(label: "Measurements", selection: $two, options: [(false, "one"), (true, "two")])
            GSlider(label: "Angle between them θ", value: $angle, range: 1...90, step: 1, unit: "°", digits: 0)
            GSlider(label: "Noise ε", value: $noise, range: 0.02...0.4)
        }
    }
}
