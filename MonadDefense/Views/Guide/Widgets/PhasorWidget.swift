import SwiftUI

/// M0: complex numbers as arrows — sum (interference), product and ratio.
struct PhasorWidget: View {
    @State private var mode: String
    @State private var a1 = 1.0
    @State private var p1 = 30.0
    @State private var a2 = 0.8
    @State private var p2 = 150.0

    init(initialMode: String) {
        _mode = State(initialValue: initialMode)
    }

    private func vec(_ a: Double, _ deg: Double) -> CGPoint {
        CGPoint(x: a * cos(deg * .pi / 180), y: a * sin(deg * .pi / 180))
    }

    var body: some View {
        let z1 = vec(a1, p1)
        let z2 = vec(a2, p2)
        let res: CGPoint = {
            switch mode {
            case "sum": return CGPoint(x: z1.x + z2.x, y: z1.y + z2.y)
            case "product": return vec(a1 * a2, p1 + p2)
            default: return vec(a1 / a2, p1 - p2)
            }
        }()
        let mag = hypot(res.x, res.y)
        let ang = atan2(res.y, res.x) * 180 / .pi
        let cross = 2 * a1 * a2 * cos((p1 - p2) * .pi / 180)
        WidgetLayout(
            formula: mode == "sum"
                ? "|z_1+z_2|^2=\(tex(a1 * a1, 2))+\(tex(a2 * a2, 2))\(cross >= 0 ? "+" : "-")\(tex(abs(cross), 2))=\(tex(mag * mag, 3))"
                : mode == "product"
                    ? "z_1z_2=\(tex(a1 * a2, 2))\\,e^{j(\(tex(p1, 0))+\(tex(p2, 0)))^\\circ}"
                    : "\\frac{z_1}{z_2}=\(tex(a1 / a2, 2))\\,e^{j(\(tex(p1, 0))-\(tex(p2, 0)))^\\circ}",
            readout: ["result: length \(fmt(mag, 3)), angle \(fmt(ang, 0))°"],
            words: "sum puts the arrows head to tail (interference); product multiplies lengths and adds angles; ratio divides lengths and subtracts angles, so a factor both share cancels."
        ) {
            Canvas { ctx, size in
                let scale = min(size.width, size.height) / 3.4
                let o = CGPoint(x: size.width / 2, y: size.height / 2)
                let P = { (p: CGPoint) in CGPoint(x: o.x + scale * p.x, y: o.y - scale * p.y) }
                var axes = Path()
                axes.move(to: CGPoint(x: 0, y: o.y)); axes.addLine(to: CGPoint(x: size.width, y: o.y))
                axes.move(to: CGPoint(x: o.x, y: 0)); axes.addLine(to: CGPoint(x: o.x, y: size.height))
                ctx.stroke(axes, with: .color(.secondary.opacity(0.4)))
                ctx.stroke(Path(ellipseIn: CGRect(x: o.x - scale, y: o.y - scale, width: 2 * scale, height: 2 * scale)),
                           with: .color(.secondary.opacity(0.4)), style: StrokeStyle(dash: [4, 4]))
                func arrow(_ from: CGPoint, _ to: CGPoint, _ color: Color, _ w: CGFloat) {
                    let a = P(from), b = P(to)
                    var p = Path(); p.move(to: a); p.addLine(to: b)
                    ctx.stroke(p, with: .color(color), lineWidth: w)
                    let ang = atan2(b.y - a.y, b.x - a.x)
                    var head = Path()
                    head.move(to: b)
                    head.addLine(to: CGPoint(x: b.x - 10 * cos(ang - 0.4), y: b.y - 10 * sin(ang - 0.4)))
                    head.addLine(to: CGPoint(x: b.x - 10 * cos(ang + 0.4), y: b.y - 10 * sin(ang + 0.4)))
                    head.closeSubpath()
                    ctx.fill(head, with: .color(color))
                }
                arrow(.zero, z1, .secondary, 2.5)
                if mode == "sum" { arrow(z1, res, GuideColors.accent, 2.5) } else { arrow(.zero, z2, GuideColors.accent, 2.5) }
                arrow(.zero, res, GuideColors.alt, 3)
            }
            .overlay(alignment: .topLeading) {
                Text("grey z₁ · blue z₂ · red result").font(.caption2).foregroundStyle(.secondary)
            }
        } controls: {
            GChoice(label: "Operation", selection: $mode, options: [("sum", "sum"), ("product", "product"), ("ratio", "ratio")])
            GSlider(label: "Length of z₁", value: $a1, range: 0.1...1.4)
            GSlider(label: "Angle of z₁", value: $p1, range: -180...180, step: 1, unit: "°", digits: 0)
            GSlider(label: "Length of z₂", value: $a2, range: 0.1...1.4)
            GSlider(label: "Angle of z₂", value: $p2, range: -180...180, step: 1, unit: "°", digits: 0)
        }
    }
}
