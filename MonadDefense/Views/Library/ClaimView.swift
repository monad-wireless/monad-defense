import SwiftUI

// MARK: - One claim: the JCDL reveal, then everything the graph knows about it

struct ClaimView: View {
    @Environment(DeskConnection.self) private var connection
    let claimID: String

    @State private var detail: ClaimDetail?
    @State private var problem: String?

    var body: some View {
        Group {
            if let detail {
                content(detail)
            } else if let problem {
                ContentUnavailableView("Could not open the claim", systemImage: "text.badge.xmark", description: Text(problem))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Claim")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func content(_ d: ClaimDetail) -> some View {
        let span: EvidenceSpan? = {
            guard let s = d.claim.evidenceStart, let e = d.claim.evidenceEnd else { return nil }
            return EvidenceSpan(start: s, end: e, id: d.claim.id)
        }()
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ClaimTags(type: d.claim.claimType, attribution: d.claim.attribution, marker: d.claim.citationMarker)
                SourceReveal(claim: d.claim.text ?? "", paragraph: d.paragraph.text ?? "", span: span)

                if let slots = d.claim.slots?.line {
                    fact("Quantity", slots, symbol: "number")
                }
                if let title = d.paper.title {
                    NavigationLink(value: d.paper.key ?? "") {
                        fact("From", "\(title)\(d.paper.year.map { " (\($0))" } ?? "")", symbol: "doc.text")
                    }
                    .buttonStyle(.plain)
                    .disabled(d.paper.key == nil)
                }
                if !d.cites.isEmpty {
                    section("Cites") {
                        ForEach(Array(d.cites.enumerated()), id: \.offset) { _, c in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.title ?? c.key ?? "")
                                    .font(.callout)
                                if let verdict = c.fidelity {
                                    Label(fidelityText(verdict), systemImage: fidelitySymbol(verdict))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(fidelityTint(verdict))
                                }
                                if let reason = c.fidelityReason, !reason.isEmpty {
                                    Text(reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !d.propositions.isEmpty {
                    section("Same statement elsewhere") {
                        ForEach(d.propositions, id: \.id) { p in
                            Text("\(p.id) · supported by \(p.support ?? 0) paper(s)")
                                .font(.caption.monospaced())
                        }
                    }
                }
                if !d.mentions.isEmpty {
                    section("Vocabulary") {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(d.mentions.enumerated()), id: \.offset) { _, m in
                                Text("\(m.name ?? "") · \(m.kind ?? "")")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.quaternary, in: .capsule)
                            }
                        }
                    }
                }
                Text(d.claim.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationDestination(for: String.self) { key in PaperView(key: key) }
    }

    private func fact(_ title: String, _ value: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.callout)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func fidelityText(_ v: String) -> String {
        switch v {
        case "SUPPORTS": "The cited paper supports it"
        case "REFUTES": "The cited paper does not say this"
        case "NOINFO": "The cited paper is silent on it"
        default: v
        }
    }

    private func fidelitySymbol(_ v: String) -> String {
        v == "SUPPORTS" ? "checkmark.seal" : v == "REFUTES" ? "xmark.seal" : "questionmark.circle"
    }

    private func fidelityTint(_ v: String) -> Color {
        v == "SUPPORTS" ? .green : v == "REFUTES" ? .red : .secondary
    }

    private func load() async {
        do {
            detail = try await connection.decode(ClaimDetail.self, "/api/claims/\(claimID)")
        } catch {
            problem = error.localizedDescription
        }
    }
}
