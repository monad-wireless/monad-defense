import SwiftUI

// MARK: - One paper, read paragraph by paragraph with its claims marked
//
// Every claim's evidence span is marked in its paragraph; tapping a marked
// passage opens that claim. The claims under a paragraph list what was taken
// from it, in reading order.

struct PaperView: View {
    @Environment(DeskConnection.self) private var connection
    let key: String

    @State private var paper: PaperDetail?
    @State private var problem: String?
    @State private var openClaim: ClaimLink?
    @State private var showClaims = true

    struct ClaimLink: Identifiable, Hashable {
        let id: String
    }

    var body: some View {
        Group {
            if let paper {
                content(paper)
            } else if let problem {
                ContentUnavailableView("Could not open the paper", systemImage: "doc.questionmark", description: Text(problem))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(paper?.title ?? key)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $showClaims) { Image(systemName: "list.bullet.indent") }
                    .accessibilityLabel("Show claims under each paragraph")
            }
        }
        .sheet(item: $openClaim) { link in
            NavigationStack { ClaimView(claimID: link.id) }
                .presentationDetents([.medium, .large])
        }
        .task { await load() }
    }

    private func content(_ paper: PaperDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header(paper)
                if paper.paragraphs.isEmpty {
                    Text(paper.skipReason.map { "No claims: \($0)." } ?? "No paragraph of this paper carries a claim yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(paper.paragraphs) { p in
                    paragraph(p)
                }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "claim" else { return .systemAction }
            openClaim = ClaimLink(id: String(url.absoluteString.dropFirst("claim:".count)))
            return .handled
        })
    }

    private func header(_ paper: PaperDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(paper.title)
                .font(.system(.title2, design: .serif, weight: .semibold))
            HStack(spacing: 10) {
                if let year = paper.year { Text(String(year)) }
                Text("\(paper.claims) claims in \(paper.paragraphs.count) paragraphs")
                Text(paper.key).font(.caption.monospaced())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Rectangle().fill(EvidenceStyle.mark).frame(width: 18, height: 10).clipShape(.rect(cornerRadius: 2))
                Text("evidence of a claim · tap to open it")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func paragraph(_ p: ParagraphRow) -> some View {
        let text = p.text ?? ""
        let spans = p.claims.compactMap { c -> EvidenceSpan? in
            guard let s = c.evidenceStart, let e = c.evidenceEnd else { return nil }
            return EvidenceSpan(start: s, end: e, id: c.id)
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let section = p.section, !section.isEmpty {
                    Text(section).lineLimit(1)
                }
                Spacer()
                if let page = p.page, page > 0 { Text("p. \(page)") }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)

            Text(Evidence.marked(text, spans: spans, linked: true))
                .font(EvidenceStyle.serif)
                .lineSpacing(5)
                .tint(.primary)

            if showClaims && !p.claims.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(p.claims) { c in
                        Button {
                            openClaim = ClaimLink(id: c.id)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: c.isCited ? "quote.bubble" : "smallcircle.filled.circle")
                                    .font(.caption2)
                                    .foregroundStyle(c.isCited ? .orange : Theme.accent)
                                Text(c.text ?? "")
                                    .font(.footnote)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(.background.secondary, in: .rect(cornerRadius: 10))
            }
        }
    }

    private func load() async {
        do {
            paper = try await connection.decode(PaperDetail.self, "/api/papers/\(key)")
        } catch {
            problem = error.localizedDescription
        }
    }
}
