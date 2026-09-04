import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Curate tab — sweep the bank, note every card, export the verdicts

struct CurateView: View {
    @Environment(StudyStore.self) private var store

    @State private var scope: Track?
    @State private var onlyUncurated = true
    @State private var pass: CurationPass?
    @State private var triage: TriageRun?
    @State private var includeDecided = false
    @State private var editing: Card?
    @State private var confirmClear = false
    @State private var confirmClearTriage = false

    /// IP-151 — a swipe stack presented with a frozen queue.
    struct TriageRun: Identifiable {
        let id = UUID()
        let scope: TriageScope
        let cards: [Card]
        let title: String
    }

    /// Identifiable wrapper so the pass is presented with a frozen queue.
    struct CurationPass: Identifiable {
        let id = UUID()
        let cards: [Card]
        let title: String
    }

    var body: some View {
        NavigationStack {
            List {
                Section { header } footer: {
                    Text("A curation pass shows each card with its answer open — nothing is graded, no review schedule moves. Swipe right to keep, left to cut, up to fix with a note, hold for more. Export when you are done and run `edu deck curation <file>` in the vault.")
                }
                phoneSection
                notesSections
            }
            .navigationTitle("Curate")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { exportMenu }
            }
            .fullScreenCover(item: $pass) { pass in
                CurationPassView(cards: pass.cards, title: pass.title)
            }
            .fullScreenCover(item: $triage) { run in
                switch run.scope {
                case .dwell: DwellReviewView(cards: run.cards, title: run.title)
                case .egg: EggTriageView(cards: run.cards, title: run.title)
                }
            }
            .confirmationDialog(
                "Delete every triage decision?", isPresented: $confirmClearTriage, titleVisibility: .visible
            ) {
                Button("Delete all decisions", role: .destructive) { store.clearAllTriage() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Export first — this cannot be undone. The vault keeps what was already ingested.")
            }
            .sheet(item: $editing) { card in
                CardNoteEditor(card: card)
            }
            .confirmationDialog(
                "Delete every curation note?", isPresented: $confirmClear, titleVisibility: .visible
            ) {
                Button("Delete all notes", role: .destructive) { store.clearAllNotes() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Export first — this cannot be undone. Review progress is not affected.")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        let progress = store.curationProgress(track: scope)
        let fraction = progress.total > 0 ? Double(progress.curated) / Double(progress.total) : 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    ProgressRing(progress: fraction, tint: Theme.accent, lineWidth: 6)
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(progress.curated) of \(progress.total) cards noted")
                        .font(.headline)
                    Text(scope?.displayName ?? "Whole bank")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(CurationVerdict.allCases) { verdict in
                    let count = store.curationCount(verdict)
                    Label("\(count)", systemImage: verdict.symbol)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(verdict.tint.opacity(count > 0 ? 0.16 : 0.06), in: .capsule)
                        .foregroundStyle(count > 0 ? verdict.tint : .secondary)
                        .accessibilityLabel("\(count) \(verdict.intent)")
                }
                Spacer()
            }

            Picker("Scope", selection: $scope) {
                Text("Whole bank").tag(Track?.none)
                ForEach(Track.allCases) { track in
                    Text("\(track.code) · \(track.displayName)").tag(Track?.some(track))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Skip cards I already noted", isOn: $onlyUncurated)
                .font(.subheadline)

            Button {
                let cards = store.curationQueue(track: scope, onlyUncurated: onlyUncurated)
                pass = CurationPass(cards: cards, title: scope?.code ?? "Curation pass")
            } label: {
                Label(
                    onlyUncurated && store.curationProgress(track: scope).curated > 0
                        ? "Continue pass" : "Start pass",
                    systemImage: "square.stack.3d.down.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)
            .disabled(store.curationQueue(track: scope, onlyUncurated: onlyUncurated).isEmpty)
        }
        .padding(.vertical, 6)
    }

    // MARK: Phone (IP-151)

    private var phoneSection: some View {
        let dwellQueue = store.dwellReviewQueue(track: scope, includeDecided: includeDecided)
        let eggQueue = store.eggQueue(track: scope)
        let sel = store.dwellSelection
        let onPhone = store.bank.cards.filter { sel.status(of: $0) == .included }.count
        let stale = store.bank.cards.filter { sel.status(of: $0) == .stale }.count
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Label("\(onPhone) on the phone", systemImage: "iphone")
                    if stale > 0 {
                        Label("\(stale) changed", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text("\(store.triageCount) swiped")
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))

                Toggle("Revisit cards the vault already decided", isOn: $includeDecided)
                    .font(.subheadline)

                HStack(spacing: 10) {
                    Button {
                        triage = TriageRun(scope: .dwell, cards: dwellQueue, title: "Dwell review")
                    } label: {
                        Label("Dwell review · \(dwellQueue.count)", systemImage: TriageScope.dwell.symbol)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(dwellQueue.isEmpty)

                    Button {
                        triage = TriageRun(scope: .egg, cards: eggQueue, title: "Eggs")
                    } label: {
                        Label("Eggs · \(eggQueue.count)", systemImage: TriageScope.egg.symbol)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(eggQueue.isEmpty)
                }
                .controlSize(.regular)

                if store.triageCount > 0 {
                    Button(role: .destructive) { confirmClearTriage = true } label: {
                        Label("Delete all swipe decisions", systemImage: "trash")
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Phone")
        } footer: {
            Text("What a participant reads during a probe dwell. Right includes, left excludes, up sends the text back with a note. Export and run `edu deck select <file>` in the vault.")
        }
    }

    // MARK: Notes

    @ViewBuilder
    private var notesSections: some View {
        let notes = store.notes
        if notes.isEmpty {
            Section {
                ContentUnavailableView(
                    "No notes yet", systemImage: "square.and.pencil",
                    description: Text("Start a pass, or tap the note button inside any study session."))
            }
        } else {
            ForEach(CurationVerdict.allCases) { verdict in
                let group = notes.filter { $0.verdict == verdict }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { row in
                            noteRow(row)
                        }
                        .onDelete { offsets in
                            for index in offsets { store.clearNote(group[index].cardID) }
                        }
                    } header: {
                        Label("\(verdict.intent) · \(group.count)", systemImage: verdict.symbol)
                            .foregroundStyle(verdict.tint)
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("Delete all notes", systemImage: "trash")
                }
            }
        }
    }

    private func noteRow(_ row: CardNote) -> some View {
        let card = store.cardsByID[row.cardID]
        return Button {
            if let card { editing = card }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    card?.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? "(card no longer in the bank)"
                )
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                if !row.note.isEmpty {
                    Text(row.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Text(row.cardID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Export

    private var exportMenu: some View {
        let stem = store.exportFilenameStem
        return Menu {
            ShareLink(
                item: CurationJSONFile(text: store.curationExportJSON, filename: "\(stem).json"),
                preview: SharePreview(
                    "Card curation (JSON)", image: Image(systemName: "curlybraces"))
            ) {
                Label("Share JSON — for `edu deck curation`", systemImage: "curlybraces")
            }
            ShareLink(
                item: CurationMarkdownFile(
                    text: store.curationExportMarkdown, filename: "\(stem).md"),
                preview: SharePreview("Card curation (Markdown)", image: Image(systemName: "doc.text"))
            ) {
                Label("Share Markdown report", systemImage: "doc.text")
            }
            Button("Copy Markdown", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = store.curationExportMarkdown
            }
            Button("Copy JSON", systemImage: "doc.on.clipboard") {
                UIPasteboard.general.string = store.curationExportJSON
            }
            Divider()
            ShareLink(
                item: CurationJSONFile(text: store.triageExportJSON, filename: "\(store.triageExportFilenameStem).json"),
                preview: SharePreview("Swipe decisions (JSON)", image: Image(systemName: "hand.draw"))
            ) {
                Label("Share swipes JSON — for `edu deck select`", systemImage: "hand.draw")
            }
            .disabled(store.triageCount == 0)
            ShareLink(
                item: CurationMarkdownFile(text: store.triageExportMarkdown, filename: "\(store.triageExportFilenameStem).md"),
                preview: SharePreview("Swipe decisions (Markdown)", image: Image(systemName: "doc.text"))
            ) {
                Label("Share swipes Markdown", systemImage: "doc.text")
            }
            .disabled(store.triageCount == 0)
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(store.curatedCount == 0 && store.triageCount == 0)
    }
}

// MARK: - Exported files
//
// Written to the temp dir only when the share sheet actually resolves the item,
// so the payload is always the current state of the notes.

struct CurationJSONFile: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            SentTransferredFile(try file.write())
        }
        .suggestedFileName { $0.filename }
    }

    fileprivate func write() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: filename)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

struct CurationMarkdownFile: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            SentTransferredFile(try file.write())
        }
        .suggestedFileName { $0.filename }
    }

    fileprivate func write() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: filename)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
