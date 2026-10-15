import SwiftUI

// MARK: - Phone texts (IP-151): what a participant reads during a probe dwell
//
// Two swipe stacks over the deck bank: dwell review (does this text belong on
// a participant's phone?) and eggs (is the instance absurd enough to tag?).
// Decisions leave as a `monad-defense/triage/1` file for `edu deck select`.

struct PhoneTextsSection: View {
    @Environment(StudyStore.self) private var store

    @State private var triage: TriageRun?
    @State private var includeDecided = false
    @State private var confirmClear = false

    struct TriageRun: Identifiable {
        let id = UUID()
        let scope: TriageScope
        let cards: [Card]
        let title: String
    }

    var body: some View {
        let dwellQueue = store.dwellReviewQueue(track: nil, includeDecided: includeDecided)
        let eggQueue = store.eggQueue(track: nil)
        let sel = store.dwellSelection
        let onPhone = store.bank.cards.filter { sel.status(of: $0) == .included }.count
        let stale = store.bank.cards.filter { sel.status(of: $0) == .stale }.count
        Section {
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

            Button {
                triage = TriageRun(scope: .dwell, cards: dwellQueue, title: "Dwell review")
            } label: {
                Label("Dwell review · \(dwellQueue.count)", systemImage: TriageScope.dwell.symbol)
            }
            .disabled(dwellQueue.isEmpty)

            Button {
                triage = TriageRun(scope: .egg, cards: eggQueue, title: "Eggs")
            } label: {
                Label("Eggs · \(eggQueue.count)", systemImage: TriageScope.egg.symbol)
            }
            .disabled(eggQueue.isEmpty)

            if store.triageCount > 0 {
                ShareLink(
                    item: JSONExportFile(text: store.triageExportJSON, filename: "\(store.triageExportFilenameStem).json"),
                    preview: SharePreview("Swipe decisions (JSON)", image: Image(systemName: "hand.draw"))
                ) {
                    Label("Share swipes, for `edu deck select`", systemImage: "square.and.arrow.up")
                }
                ShareLink(
                    item: MarkdownExportFile(
                        text: store.triageExportMarkdown, filename: "\(store.triageExportFilenameStem).md"),
                    preview: SharePreview("Swipe decisions (Markdown)", image: Image(systemName: "doc.text"))
                ) {
                    Label("Share swipes as Markdown", systemImage: "doc.text")
                }
                Button(role: .destructive) { confirmClear = true } label: {
                    Label("Delete all swipe decisions", systemImage: "trash")
                }
            }
        } header: {
            Text("Phone texts")
        } footer: {
            Text("Swipe right to include, left to exclude, up to send the text back with a note. Share the file and run `edu deck select <file>` in the vault.")
        }
        .fullScreenCover(item: $triage) { run in
            switch run.scope {
            case .dwell: DwellReviewView(cards: run.cards, title: run.title)
            case .egg: EggTriageView(cards: run.cards, title: run.title)
            }
        }
        .confirmationDialog("Delete every swipe decision?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all decisions", role: .destructive) { store.clearAllTriage() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Share the file first. This cannot be undone; the vault keeps what it already ingested.")
        }
    }
}
