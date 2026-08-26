import SwiftUI

// MARK: - The MonadCount house theme
//
// Shared with `repos/monad-app`, which carries the same mark: a bold M in
// ink navy beside three arcs in periwinkle. The two apps are siblings — the
// field instrument and the study companion — so they use one palette and
// differ only in what their icon's arcs point at.
//
// Values are sampled from the monad-app icon rather than re-invented, so a
// screenshot of either app sits beside the other without a colour argument.
// `Color.accentColor` resolves to the same value through the asset catalogue;
// these constants exist for the places a literal is needed (chart series,
// diagram strokes) where the catalogue cannot reach.

enum Theme {
    /// Ink — the M, primary rules, emphasis strokes on light ground.
    static let ink = Color(red: 0.059, green: 0.078, blue: 0.184)  // #0F142F

    /// Accent — the arcs, the study tint, every interactive affordance.
    static let accent = Color(red: 0.357, green: 0.431, blue: 0.800)  // #5B6ECC

    /// Accent lifted for dark ground, where #5B6ECC sits too close to black.
    static let accentDark = Color(red: 0.475, green: 0.545, blue: 0.867)

    /// The series palette for charts and multi-curve figures. Accent first,
    /// then hues far enough apart to survive both themes and colour-vision
    /// deficiency — never a rainbow ramp, which encodes an order that the
    /// curves do not have.
    static let series: [Color] = [accent, .orange, .teal, .brown]
}
