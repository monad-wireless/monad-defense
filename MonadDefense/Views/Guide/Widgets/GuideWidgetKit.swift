import SwiftUI

// MARK: - Shared pieces of the guide widgets
//
// Every widget has the same five parts as its twin in the Slidev decks: a
// picture, named controls with their range and unit, the formula with the
// current values substituted, a readout, and one "In words" line. The decks'
// widgets are in publications/thesis-math/components/; a default here prints
// the number the deck prints, because both come from the same model
// (GuideMath ⇔ models.js).

/// The frame every widget fills.
struct WidgetLayout<Chart: View, Controls: View>: View {
    var formula: String?
    var readout: [String] = []
    let words: String
    /// Height of the picture. A table-plus-chart picture needs more than a chart.
    var chartHeight: CGFloat = 230
    @ViewBuilder var chart: () -> Chart
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chart()
                .frame(height: chartHeight)
            VStack(spacing: 6) { controls() }
            if let formula {
                FormulaBlock(latex: formula, size: 16)
            }
            if !readout.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(readout, id: \.self) { line in
                        InlineMathText("**\(line)**", font: .footnote)
                    }
                }
            }
            InlineMathText("**In words:** " + words, font: .footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A labelled slider with its range and unit. `log` puts the thumb on a
/// logarithmic scale for quantities that span decades (knees, dispersion).
struct GSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var unit: String = ""
    var digits: Int = 2
    var log: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(fmt(value, digits))\(unit.isEmpty ? "" : " " + unit)")
                    .font(.subheadline.monospacedDigit().weight(.bold))
            }
            if log {
                Slider(value: logBinding, in: log10(range.lowerBound)...log10(range.upperBound))
            } else if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var logBinding: Binding<Double> {
        Binding(get: { log10(max(value, range.lowerBound)) }, set: { value = pow(10, $0) })
    }
}

/// A labelled segmented choice.
struct GChoice<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold))
            Picker(label, selection: $selection) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Fixed-decimal text with a true minus sign.
func fmt(_ x: Double, _ digits: Int) -> String {
    guard x.isFinite else { return x < 0 ? "−∞" : "∞" }
    var s = String(format: "%.\(digits)f", x)
    if Double(s) == 0 { s = String(format: "%.\(digits)f", 0.0) }
    return s.hasPrefix("-") ? "−" + s.dropFirst() : s
}

/// Fixed-decimal text for LaTeX (ASCII minus).
func tex(_ x: Double, _ digits: Int) -> String {
    guard x.isFinite else { return x < 0 ? #"-\infty"# : #"\infty"# }
    let s = String(format: "%.\(digits)f", x)
    return Double(s) == 0 ? String(format: "%.\(digits)f", 0.0) : s
}

/// Three significant digits, switching to ×10ⁿ outside 0.001 … 10⁵.
func sig(_ x: Double, _ d: Int = 3) -> String {
    guard x.isFinite else { return x < 0 ? "−∞" : "∞" }
    if x == 0 { return "0" }
    let a = abs(x)
    if a >= 1e5 || a < 1e-3 {
        let e = Int(floor(log10(a)))
        return "\(fmt(x / pow(10, Double(e)), max(d - 1, 0)))×10^\(e)"
    }
    return fmt(x, max(0, d - 1 - Int(floor(log10(a)))))
}

/// Points of f on [a, b], for LineMark series.
struct XY: Identifiable {
    let id: Int
    let x: Double
    let y: Double
}

func sample(_ a: Double, _ b: Double, _ n: Int = 120, _ f: (Double) -> Double) -> [XY] {
    (0...n).map { i in
        let x = a + (b - a) * Double(i) / Double(n)
        return XY(id: i, x: x, y: f(x))
    }
}

enum GuideColors {
    static let accent = Theme.accent
    static let alt = Color.red
    static let amber = Color.orange
    static let muted = Color.secondary
}
