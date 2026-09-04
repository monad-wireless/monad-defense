import SwiftUI

// MARK: - The monad-app dwell panel, mocked at phone width (IP-151)
//
// The judgement in the Dwell review stack is about the phone, so the phone is
// what is shown: the same three panels a participant sees during a 30 s
// probe dwell, each on screen for 11 s, with the 11 s bar animating. Nothing
// here is decorative — the width, the panel time and the character budget
// are the constraints the text was written against.

struct DwellPanelMock: View {
    let card: Card
    let block: DwellBlock
    /// `stale` is shown when the vault accepted different words.
    var status: DwellSelection.Status = .undecided

    static let panelSeconds: Double = 11
    static let textCap = 200
    static let quipCap = 90

    @State private var panel = 0
    @State private var progress: Double = 0

    private var panels: [(flavour: String, body: String, quip: String?)] {
        var out: [(String, String, String?)] = [("Foundation", block.definition, nil)]
        if let fact = block.fact {
            out.append(("Wild", fact, block.quip))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            TabView(selection: $panel) {
                ForEach(Array(panels.enumerated()), id: \.offset) { i, p in
                    panelView(p.flavour, p.body, p.quip, egg: p.flavour == "Wild" && card.tags.contains("wtf"))
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 300)
            .frame(maxWidth: 390)
            .frame(maxWidth: .infinity)

            budget
        }
        .task(id: panel) {
            progress = 0
            withAnimation(.linear(duration: Self.panelSeconds)) { progress = 1 }
            try? await Task.sleep(for: .seconds(Self.panelSeconds))
            if !Task.isCancelled, panel + 1 < panels.count {
                withAnimation { panel += 1 }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(card.track.displayName, systemImage: card.track.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(card.track.tint)
            Spacer()
            switch status {
            case .stale:
                Label("changed since accepted", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            case .included:
                Label("on the phone", systemImage: "checkmark.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            case .excluded:
                Label("excluded", systemImage: "minus.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            case .undecided:
                EmptyView()
            }
        }
    }

    private func panelView(_ flavour: String, _ body: String, _ quip: String?, egg: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(egg ? "✦ \(flavour)" : flavour.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(egg ? .orange : Theme.accent)
                Spacer()
                Text(card.title ?? card.prompt.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Text(cardMarkdown(body))
                .font(.system(size: 17, weight: .regular, design: .default))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if let quip {
                Text(quip)
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            ProgressView(value: progress)
                .tint(egg ? .orange : Theme.accent)
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(egg ? Color.orange.opacity(0.08) : Theme.accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(egg ? Color.orange.opacity(0.35) : Theme.accent.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 2)
        .padding(.bottom, 26)  // room for the page dots
    }

    /// Where each text sits against its cap — the number the author wrote to.
    private var budget: some View {
        VStack(alignment: .leading, spacing: 4) {
            budgetRow("definition", block.definition.count, Self.textCap)
            if let fact = block.fact { budgetRow("fact", fact.count, Self.textCap) }
            if let quip = block.quip { budgetRow("quip", quip.count, Self.quipCap) }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func budgetRow(_ name: String, _ n: Int, _ cap: Int) -> some View {
        HStack(spacing: 8) {
            Text(name).frame(width: 64, alignment: .leading)
            ProgressView(value: Double(n), total: Double(cap))
                .tint(n > cap ? .red : (Double(n) / Double(cap) > 0.9 ? .orange : .secondary))
            Text("\(n)/\(cap)").frame(width: 60, alignment: .trailing)
        }
    }
}
