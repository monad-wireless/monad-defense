import SwiftUI

// MARK: - Library tab (IP-172): find a paper or a claim, read it in place
//
// A split view: the list beside the reader on an iPad or a Mac, one pushed
// stack on a phone (the split collapses). The reader keeps its own stack, so a
// claim's "From" link can walk on to its paper without losing the list.

struct LibraryView: View {
    @Environment(DeskConnection.self) private var connection

    /// What the reader column shows.
    enum Item: Hashable {
        case paper(String)
        case claim(ClaimHit)
    }

    @State private var selection: Item? = LibraryView.initialSelection
    @State private var query = ""
    @State private var results: SearchResult?
    @State private var browse: [PaperSummary] = []
    @State private var problem: String?
    @State private var loading = false
    @FocusState private var searchFocused: Bool

    private static var initialSelection: Item? {
        #if DEBUG
        if let paper = DebugRouter.demoPaper { return .paper(paper) }
        #endif
        return nil
    }

    var body: some View {
        NavigationSplitView {
            list
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
        } detail: {
            NavigationStack {
                switch selection {
                case .paper(let key):
                    PaperView(key: key).id(key)
                case .claim(let hit):
                    ClaimView(claimID: hit.id).id(hit.id)
                case nil:
                    ContentUnavailableView(
                        "Nothing open", systemImage: "books.vertical",
                        description: Text(
                            Platform.isMac
                                ? "Choose a paper or a claim. ⌘F searches papers and claims."
                                : "Choose a paper or a claim."))
                }
            }
        }
    }

    private var list: some View {
        List(selection: $selection) {
                if !connection.isConfigured {
                    ContentUnavailableView(
                        "Not connected", systemImage: "network.slash",
                        description: Text("The Library reads papers and claims from the Desk server. Connect it in Curate."))
                } else if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                if let results, !query.isEmpty {
                    searchSections(results)
                } else {
                    Section {
                        ForEach(browse) { paper in
                            NavigationLink(value: Item.paper(paper.key)) { PaperRow(paper: paper) }
                        }
                    } header: {
                        Text("Most claims")
                    } footer: {
                        if !browse.isEmpty {
                            Text("A paper reads as the paragraphs its claims came from. Search by title, key or claim words.")
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $query, prompt: "Papers and claims")
            .searchFocused($searchFocused)
            .overlay { if loading { ProgressView() } }
            .refreshable { await loadBrowse() }
            .toolbar {
                if Platform.isMac {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await loadBrowse() } }
                            .keyboardShortcut("r", modifiers: .command)
                            .disabled(!connection.isConfigured)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Search", systemImage: "magnifyingglass") { searchFocused = true }
                            .keyboardShortcut("f", modifiers: .command)
                    }
                }
            }
            .task(id: query) { await search() }
            .task { if browse.isEmpty { await loadBrowse() } }
    }

    @ViewBuilder
    private func searchSections(_ r: SearchResult) -> some View {
        if r.papers.isEmpty && r.claims.isEmpty {
            ContentUnavailableView.search(text: query)
        }
        if !r.papers.isEmpty {
            Section("Papers") {
                ForEach(r.papers) { paper in
                    NavigationLink(value: Item.paper(paper.key)) { PaperRow(paper: paper) }
                }
            }
        }
        if !r.claims.isEmpty {
            Section("Claims") {
                ForEach(r.claims) { hit in
                    NavigationLink(value: Item.claim(hit)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hit.text)
                                .font(.callout)
                                .lineLimit(3)
                            HStack(spacing: 6) {
                                ClaimTags(type: hit.claimType, attribution: hit.attribution, marker: nil)
                                Text(hit.paperTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadBrowse() async {
        guard connection.isConfigured else { return }
        do {
            browse = try await connection.decode(PaperList.self, "/api/papers", query: ["limit": "40"]).papers
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard connection.isConfigured, q.count >= 3 else {
            results = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))  // typing pause
        guard !Task.isCancelled else { return }
        loading = true
        defer { loading = false }
        do {
            results = try await connection.decode(SearchResult.self, "/api/search", query: ["q": q])
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}

struct PaperRow: View {
    let paper: PaperSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(paper.title)
                .font(.callout.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 8) {
                if let year = paper.year { Text(String(year)) }
                Text("\(paper.claims) claims")
                Text(paper.key)
                    .font(.caption2.monospaced())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
