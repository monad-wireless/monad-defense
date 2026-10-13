import SwiftUI

// MARK: - Desk payload editors (IP-161)
//
// An editor collects the payload an action needs, then calls `commit`. The
// store validates with the same rules as the importer; a problem stays on
// screen and nothing is saved. Cancel leaves the card untouched.

/// Record one action. Returns nil when saved, else the reason it was not.
typealias DeskCommit = (_ action: String, _ payload: [String: Any], _ note: String?) -> String?

struct DeskForm<Content: View>: View {
    let title: String
    let saveLabel: String
    var showsCancel = true
    let save: () -> String?
    let finish: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?

    var body: some View {
        Form {
            content()
            if let problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(saveLabel) {
                    if let reason = save() {
                        problem = reason
                    } else {
                        finish()
                    }
                }
                .fontWeight(.semibold)
            }
        }
    }
}

private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

private func label(_ code: String) -> String { code.replacingOccurrences(of: "_", with: " ") }

private struct NoteSection: View {
    @Binding var note: String

    var body: some View {
        Section("Note (optional)") {
            TextField("Anything the import should keep", text: $note, axis: .vertical)
                .lineLimit(2...5)
        }
    }
}

// MARK: Reason picker — set aside, not related

struct DeskReasonEditor: View {
    let title: String
    let action: String
    let reasons: [String]
    /// Payload key for the free-text explanation. Nil puts the text in the note.
    let explanationKey: String?
    let commit: DeskCommit
    let finish: () -> Void

    @State private var reason: String?
    @State private var explanation = ""
    @State var note: String

    var body: some View {
        NavigationStack {
            DeskForm(title: title, saveLabel: "Save", save: save, finish: finish) {
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        Text("Choose…").tag(String?.none)
                        ForEach(reasons, id: \.self) { Text(label($0)).tag(Optional($0)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if let explanationKey {
                    Section {
                        TextField("Explanation", text: $explanation, axis: .vertical)
                            .lineLimit(2...5)
                    } footer: {
                        Text(reason == "other" ? "Required for “other”." : "Optional.")
                    }
                    .id(explanationKey)
                }
                NoteSection(note: $note)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() -> String? {
        guard let reason else { return "Choose a reason." }
        var payload: [String: Any] = ["reason": reason]
        if let explanationKey, !trimmed(explanation).isEmpty { payload[explanationKey] = trimmed(explanation) }
        return commit(action, payload, note)
    }
}

// MARK: One required text field — research question, where cited, cannot assess

struct DeskTextEditor: View {
    let title: String
    let action: String
    let key: String
    let prompt: String
    let footer: String
    var showsCancel = true
    let commit: DeskCommit
    let finish: () -> Void

    @State private var text = ""
    @State var note: String

    var body: some View {
        DeskForm(title: title, saveLabel: "Save", showsCancel: showsCancel, save: save, finish: finish) {
            Section {
                TextField(prompt, text: $text, axis: .vertical)
                    .lineLimit(2...6)
            } footer: {
                Text(footer)
            }
            NoteSection(note: $note)
        }
    }

    private func save() -> String? {
        commit(action, [key: trimmed(text)], note)
    }
}

/// A `DeskTextEditor` presented on its own.
struct DeskTextSheet: View {
    let title: String
    let action: String
    let key: String
    let prompt: String
    let footer: String
    let note: String
    let commit: DeskCommit
    let finish: () -> Void

    var body: some View {
        NavigationStack {
            DeskTextEditor(
                title: title, action: action, key: key, prompt: prompt, footer: footer,
                commit: commit, finish: finish, note: note)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: Fidelity defect — partial, wrong

struct DeskDefectEditor: View {
    let action: String
    let card: DeskCard
    let commit: DeskCommit
    let finish: () -> Void

    @State private var defect: String?
    @State private var explanation = ""
    @State private var sourceRef: String?
    @State var note: String

    private var origins: [(id: String, label: String)] {
        (card.evidence["origins"]?.array ?? []).compactMap { o in
            guard let id = o["paragraph_id"]?.string else { return nil }
            let text = o["text"]?.string ?? ""
            return (id, "\(o["paper"]?.string ?? "") · \(text.prefix(60))…")
        }
    }

    var body: some View {
        NavigationStack {
            DeskForm(title: label(action).capitalized, saveLabel: "Save", save: save, finish: finish) {
                Section("Defect") {
                    Picker("Defect", selection: $defect) {
                        Text("Choose…").tag(String?.none)
                        ForEach(DeskRules.fidelityDefects, id: \.self) { Text(label($0)).tag(Optional($0)) }
                    }
                }
                Section("Source paragraph") {
                    Picker("Paragraph", selection: $sourceRef) {
                        Text("Choose…").tag(String?.none)
                        ForEach(origins, id: \.id) { Text($0.label).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    TextField("What changed between source and claim?", text: $explanation, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Explanation")
                } footer: {
                    Text("This annotates the extraction. It never rewrites it.")
                }
                NoteSection(note: $note)
            }
        }
        .onAppear { if origins.count == 1 { sourceRef = origins[0].id } }
    }

    private func save() -> String? {
        var payload: [String: Any] = ["explanation": trimmed(explanation)]
        if let defect { payload["defect"] = defect }
        if let sourceRef { payload["source_ref"] = sourceRef }
        return commit(action, payload, note)
    }
}

// MARK: Definition — promote

struct DeskDefinitionEditor: View {
    let card: DeskCard
    var showsCancel = true
    let commit: DeskCommit
    let finish: () -> Void

    @State private var name = ""
    @State private var slug = ""
    @State private var aliases = ""
    @State private var definition = ""
    @State private var scope = ""
    @State private var refs: Set<String> = []
    @State var note: String
    @State private var loaded = false

    private var kind: String { card.evidence["kind"]?.string ?? "" }

    private var papers: [(id: String, title: String)] {
        (card.evidence["paper_list"]?.array ?? []).compactMap { p in
            guard let id = p["paper_id"]?.string else { return nil }
            return (id, p["title"]?.string ?? id)
        }
    }

    var body: some View {
        DeskForm(title: "Definition", saveLabel: "Define", showsCancel: showsCancel, save: save, finish: finish) {
            Section {
                TextField("Preferred name", text: $name)
                TextField("slug", text: $slug)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                LabeledContent("Type", value: kind)
                TextField("Aliases, comma separated", text: $aliases)
            } header: {
                Text("Identity")
            }
            Section {
                TextField("Definition of the concept and its scope", text: $definition, axis: .vertical)
                    .lineLimit(4...12)
                TextField("Scope (optional)", text: $scope, axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Definition")
            } footer: {
                Text("Distinguish it from the near matches and keep the qualifications. \(trimmed(definition).count) characters.")
            }
            Section("Source papers") {
                ForEach(papers, id: \.id) { paper in
                    Button {
                        if refs.contains(paper.id) { refs.remove(paper.id) } else { refs.insert(paper.id) }
                    } label: {
                        HStack {
                            Image(systemName: refs.contains(paper.id) ? "checkmark.circle.fill" : "circle")
                            Text(paper.title)
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            NoteSection(note: $note)
        }
        .onAppear(perform: load)
    }

    /// Start from the agent's definition when the bank shows one, else from the candidate.
    private func load() {
        guard !loaded else { return }
        loaded = true
        let p = card.proposal?.action == "promote" ? card.proposal?.payload : nil
        name = p?["name"]?.string ?? card.evidence["name"]?.string ?? ""
        slug = p?["slug"]?.string ?? card.evidence["slug"]?.string ?? ""
        aliases = (p?["aliases"]?.array ?? []).compactMap(\.string).joined(separator: ", ")
        definition = p?["definition"]?.string ?? ""
        scope = p?["scope"]?.string ?? ""
        refs = Set((p?["source_refs"]?.array ?? []).compactMap(\.string))
    }

    private func save() -> String? {
        let aliasList = aliases.split(separator: ",").map { trimmed(String($0)) }.filter { !$0.isEmpty }
        var payload: [String: Any] = [
            "name": trimmed(name),
            "slug": trimmed(slug),
            "entity_type": kind,
            "aliases": aliasList,
            "definition": trimmed(definition),
            "source_refs": papers.map(\.id).filter { refs.contains($0) },
        ]
        payload["scope"] = trimmed(scope).isEmpty ? NSNull() : trimmed(scope)
        return commit("promote", payload, note)
    }
}

// MARK: Alias — target from the compiled catalogue

struct DeskAliasEditor: View {
    let card: DeskCard
    let bank: DeskBank
    var showsCancel = true
    let commit: DeskCommit
    let finish: () -> Void

    @State private var query = ""
    @State private var target: DeskCatalogueItem?
    @State private var intended = ""
    @State private var explanation = ""
    @State var note: String

    private var matches: [DeskCatalogueItem] {
        let items = bank.catalogue?.items ?? []
        let q = trimmed(query).lowercased()
        guard !q.isEmpty else { return Array(items.prefix(30)) }
        return items.filter { item in
            item.name.lowercased().contains(q) || item.slug.contains(q)
                || (item.aliases ?? []).contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        DeskForm(title: "Alias", saveLabel: "Save alias", showsCancel: showsCancel, save: save, finish: finish) {
            Section {
                TextField("Search the catalogue", text: $query)
                    .textInputAutocapitalization(.never)
                ForEach(matches) { item in
                    Button {
                        target = item
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: target?.slug == item.slug ? "largecircle.fill.circle" : "circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .foregroundStyle(.primary)
                                if item.vaultNote == false {
                                    Text("research-only term, no vault note")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                if let def = item.definition, !def.isEmpty {
                                    Text(def)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Target (\(bank.catalogue?.kind ?? "") catalogue)")
            } footer: {
                if bank.catalogue?.complete == false {
                    Text("The catalogue is incomplete. An absent target is a research request, not a guess.")
                }
            }
            if bank.mode == .blind {
                Section {
                    TextField("Intended identity, when not listed", text: $intended)
                } footer: {
                    Text("Blind alias is an annotation. It never changes the vocabulary.")
                }
            }
            Section("Why one concept") {
                TextField("Why do the two surface forms denote one concept?", text: $explanation, axis: .vertical)
                    .lineLimit(2...5)
            }
            NoteSection(note: $note)
        }
    }

    private func save() -> String? {
        var targetPayload: [String: Any] = [:]
        if let target {
            targetPayload["slug"] = target.slug
            targetPayload["entity_type"] = bank.catalogue?.kind ?? card.evidence["kind"]?.string ?? ""
        } else if bank.mode == .blind, !trimmed(intended).isEmpty {
            targetPayload["intended"] = trimmed(intended)
        }
        var payload: [String: Any] = ["target": targetPayload]
        if !trimmed(explanation).isEmpty { payload["explanation"] = trimmed(explanation) }
        return commit("alias", payload, note)
    }
}

// MARK: Resolve — the vocabulary up-swipe

struct DeskResolveSheet: View {
    let card: DeskCard
    let bank: DeskBank
    let note: String
    let commit: DeskCommit
    let finish: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if bank.mode == .assisted {
                    NavigationLink {
                        DeskDefinitionEditor(card: card, showsCancel: false, commit: commit, finish: finish, note: note)
                    } label: {
                        Label("Edit the definition", systemImage: "pencil.and.list.clipboard")
                    }
                }
                NavigationLink {
                    DeskAliasEditor(card: card, bank: bank, showsCancel: false, commit: commit, finish: finish, note: note)
                } label: {
                    Label("Alias of an existing term", systemImage: "link")
                }
                NavigationLink {
                    DeskTextEditor(
                        title: "Needs research", action: "needs_research", key: "question",
                        prompt: "The question, or the evidence that is missing",
                        footer: "Goes to the research queue. It never counts as a resolved term.",
                        showsCancel: false, commit: commit, finish: finish, note: note)
                } label: {
                    Label("Needs research", systemImage: "magnifyingglass")
                }
            }
            .navigationTitle("Resolve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
