import SwiftUI

// MARK: - Curation note editor (sheet)

/// Verdict + free-text note on a single card. Reachable mid-study from the
/// session toolbar and from any row in the Curate tab.
struct CardNoteEditor: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let card: Card

    @State private var verdict: CurationVerdict = .keep
    @State private var text = ""
    @State private var loaded = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(card.prompt.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.callout)
                        .fontDesign(.serif)
                } header: {
                    Text("Card")
                } footer: {
                    Text(card.id)
                        .font(.caption2.monospaced())
                }

                Section("Verdict") {
                    VerdictPicker(verdict: $verdict)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                Section("Note") {
                    TextField(
                        "What is wrong, what is missing, what to do instead…",
                        text: $text, axis: .vertical
                    )
                    .lineLimit(3...8)
                    .focused($noteFocused)
                    QuickNoteChips { phrase in append(phrase) }
                }

                if store.note(for: card.id) != nil {
                    Section {
                        Button(role: .destructive) {
                            store.clearNote(card.id)
                            dismiss()
                        } label: {
                            Label("Remove note", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Curate card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setNote(text, verdict: verdict, for: card.id)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .keyboard) {
                    Spacer()
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { noteFocused = false }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing = store.note(for: card.id) {
                    verdict = existing.verdict
                    text = existing.note
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func append(_ phrase: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = trimmed.isEmpty ? phrase : "\(trimmed). \(phrase)"
    }
}

// MARK: - Shared curation controls

struct VerdictPicker: View {
    @Binding var verdict: CurationVerdict

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CurationVerdict.allCases) { option in
                let selected = option == verdict
                Button {
                    verdict = option
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: option.symbol)
                            .font(.subheadline)
                        Text(option.displayName)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selected ? option.tint.opacity(0.18) : Color(.tertiarySystemFill),
                        in: .rect(cornerRadius: 12)
                    )
                    .foregroundStyle(selected ? option.tint : .secondary)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selected ? option.tint : .clear, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.intent)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

struct QuickNoteChips: View {
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(StudyStore.quickNotes, id: \.self) { phrase in
                    Button(phrase) { onTap(phrase) }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

struct VerdictChip: View {
    let verdict: CurationVerdict

    var body: some View {
        Label(verdict.displayName, systemImage: verdict.symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(verdict.tint.opacity(0.14), in: .capsule)
            .foregroundStyle(verdict.tint)
    }
}
