import SwiftUI

// MARK: - CodeFigureView
//
// Commands and their output — the term as the machine reports it.
//
// A phone is narrow and a command must not be folded silently: a wrapped
// command still reads as a command, and the reader copies it wrong. So a
// command scrolls horizontally inside its own row, and only the command does.
// Output and notes wrap like prose, because nobody retypes output.
//
// Monospaced throughout, at a fixed size rather than a scaled one, because the
// only thing worse than small code is code whose columns no longer line up.

struct CodeFigureView: View {
    let figure: CodeFigure
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(figure.steps.enumerated()), id: \.offset) { _, step in
                VStack(alignment: .leading, spacing: 4) {
                    command(step.run)
                    if let output = step.output, !output.isEmpty {
                        output_(output)
                    }
                    if let note = step.note, !note.isEmpty {
                        Text(cardMarkdown(note))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func command(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !figure.prompt.isEmpty {
                    Text(figure.prompt)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Text(text)
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(tint)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
        }
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
    }

    private func output_(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.quaternary)
                .frame(width: 2)
        }
    }
}
