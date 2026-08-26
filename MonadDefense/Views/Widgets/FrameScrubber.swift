import SwiftUI

// MARK: - FrameScrubber
//
// A reusable control for stepping through a sequence of pre-computed frames:
// a slider to scrub, a play button to run through them, and one line naming
// the state on screen.
//
// It knows nothing about what a frame contains. Any figure that can be
// expressed as an ordered set of states — a swept plot parameter today, a
// staged diagram or an animated sequence tomorrow — drives it by binding an
// index and supplying a caption for each one.

struct FrameScrubber: View {
    let count: Int
    /// What to print for a given index: a scenario name, a value, a step.
    let caption: (Int) -> String
    @Binding var index: Int

    var tint: Color = Theme.accent
    /// Seconds each frame is held while playing.
    var interval: TimeInterval = 0.9

    @State private var isPlaying = false

    private var bounds: ClosedRange<Double> { 0...Double(max(count - 1, 1)) }

    var body: some View {
        if count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    playButton
                    Slider(
                        value: Binding(
                            get: { Double(index) },
                            // Scrubbing by hand is a deliberate act; it stops
                            // the animation rather than fighting it.
                            set: { newValue in
                                let clamped = Int(newValue.rounded())
                                if clamped != index { isPlaying = false }
                                index = min(max(clamped, 0), count - 1)
                            }
                        ),
                        in: bounds,
                        step: 1
                    )
                    .tint(tint)
                }
                Text(caption(index))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: index)
            }
            // A timeline drives playback rather than a stored Timer: the view
            // owns no lifecycle, so leaving the card cannot leave a tick
            // running, and pausing costs nothing.
            .overlay {
                if isPlaying {
                    TimelineView(.periodic(from: .now, by: interval)) { context in
                        Color.clear.onChange(of: context.date) { _, _ in advance() }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var playButton: some View {
        Button {
            isPlaying.toggle()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.footnote.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: .circle)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play through the values")
    }

    /// Wrap rather than stop: the sweep is a loop, and stopping at the end
    /// means the reader sees the last state and has to drag back to compare.
    private func advance() {
        withAnimation(.snappy) { index = (index + 1) % count }
    }
}

#Preview {
    @Previewable @State var index = 0
    return FrameScrubber(count: 4, caption: { "K₀ = \($0 * 3 + 2)" }, index: $index)
        .padding()
}
