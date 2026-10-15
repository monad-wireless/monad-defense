import SwiftUI
import UniformTypeIdentifiers

// MARK: - Curate tab (IP-161, IP-172): the server, banks, sessions, phone texts
//
// "Sent" and "applied" stay distinct until a receipt comes back. A session
// without a receipt has an unknown application status.

struct DeskHomeView: View {
    @Environment(DeskStore.self) private var desk
    @Environment(DeskConnection.self) private var connection

    /// A bundled bank resource to open on appear (debug launch argument only).
    var autoOpen: String? = nil

    @State private var sitting: Sitting?
    @State private var importing = false
    @State private var message: String?
    @State private var connecting = false
    @State private var refreshing = false
    @State private var refreshProblem: String?

    struct Sitting: Identifiable {
        let id = UUID()
        let bank: DeskBank
        let session: DeskSession
        let cards: [DeskCard]
    }

    var body: some View {
        List {
            serverSection
            banksSection
            if !desk.bankProblems.isEmpty {
                Section("Banks that did not load") {
                    ForEach(desk.bankProblems, id: \.self) { problem in
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            sessionsSection
            PhoneTextsSection()
        }
        .navigationTitle("Curate")
        .refreshable { await refresh() }
        .task { if desk.lastRefresh == nil { await refresh() } }
        .sheet(isPresented: $connecting, onDismiss: { Task { await refresh() } }) { ConnectionSheet() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Desk server", systemImage: "server.rack") { connecting = true }
                    Button("Import a receipt file", systemImage: "doc.badge.arrow.up") { importing = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importReceipt(result)
        }
        .alert("Receipt", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .fullScreenCover(item: $sitting) { s in
            DeskDeckView(bank: s.bank, session: s.session, cards: s.cards)
        }
        .task {
            if let autoOpen, let bank = desk.banks.first(where: { $0.resourceName.contains(autoOpen) }) {
                open(bank)
            }
        }
    }

    @ViewBuilder
    private var serverSection: some View {
        Section {
            if connection.isConfigured {
                HStack(spacing: 10) {
                    Image(systemName: refreshProblem == nil ? "checkmark.icloud" : "exclamationmark.icloud")
                        .foregroundStyle(refreshProblem == nil ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(string: connection.address)?.host() ?? connection.address)
                            .font(.subheadline.weight(.medium))
                        Text(refreshProblem ?? lastRefreshText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if refreshing { ProgressView() }
                }
            } else {
                Button {
                    connecting = true
                } label: {
                    Label("Connect the Desk server", systemImage: "server.rack")
                }
            }
        } footer: {
            if !connection.isConfigured {
                Text("New banks arrive from the server without a rebuild, and locked sessions go back to the vault from here.")
            }
        }
    }

    private var lastRefreshText: String {
        guard let at = desk.lastRefresh else { return "Pull down to fetch new banks" }
        return "Banks checked \(at.formatted(.relative(presentation: .named)))"
    }

    private func refresh() async {
        guard connection.isConfigured else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            try await desk.refresh(from: connection)
            refreshProblem = nil
        } catch {
            refreshProblem = error.localizedDescription
        }
    }

    @ViewBuilder
    private var banksSection: some View {
        Section {
            if desk.banks.isEmpty {
                ContentUnavailableView(
                    "No bank on this phone", systemImage: "tray",
                    description: Text("Publish one with `kb desk publish <bank.json>` and pull down here."))
            }
            ForEach(desk.banks) { bank in
                Button {
                    open(bank)
                } label: {
                    bankRow(bank)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Banks")
        } footer: {
            Text("A sitting resumes the open session of its bank. Blind banks carry no proposal.")
        }
    }

    private func bankRow(_ bank: DeskBank) -> some View {
        let guide = BankGuide(bank)
        let open = desk.sessions(for: bank).first { !$0.isLocked }
        let decided = open.map { bank.cards.count - desk.pending($0, bank: bank).count } ?? 0
        let finished = desk.sessions(for: bank).contains { $0.isLocked }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: bank.stack.symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(guide.title)
                        .font(.headline)
                    DeskBadge(text: bank.mode == .blind ? "blind" : "with proposal", tint: bank.mode == .blind ? .purple : .teal)
                    if guide.exploratory { DeskBadge(text: "practice", tint: .gray) }
                }
                Text(guide.question)
                    .font(.subheadline)
                Text(guide.effect)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(decided), total: Double(max(bank.cards.count, 1)))
                    .tint(decided == bank.cards.count ? .green : Theme.accent)
                Text(
                    finished && open == nil
                        ? "Done: session locked · \(bank.cards.count) cards"
                        : "\(decided) of \(bank.cards.count) decided · compiled \(bank.compiledAt?.prefix(10) ?? "?")"
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var sessionsSection: some View {
        let sessions = desk.sessions
        if !sessions.isEmpty {
            Section("Sessions") {
                ForEach(sessions) { session in
                    NavigationLink {
                        DeskSessionView(session: session)
                    } label: {
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: DeskSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.bankTitle)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                Text(session.created, format: .dateTime.day().month().hour().minute())
                Text(DeskSessionView.state(session))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func open(_ bank: DeskBank) {
        do {
            let session = try desk.openSession(for: bank)
            let cards = desk.pending(session, bank: bank)
            guard !cards.isEmpty else {
                message = "Every task in the open session has a disposition. Lock and export it from Sessions."
                return
            }
            sitting = Sitting(bank: bank, session: session, cards: cards)
        } catch {
            message = error.localizedDescription
        }
    }

    private func importReceipt(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let session = try desk.importReceipt(try Data(contentsOf: url))
            message = "Attached to the session of \(session.bankTitle)."
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - One session

struct DeskSessionView: View {
    @Environment(DeskStore.self) private var desk
    @Environment(DeskConnection.self) private var connection

    let session: DeskSession

    @State private var confirmLock = false
    @State private var sitting: DeskHomeView.Sitting?
    @State private var problem: String?
    @State private var notice: String?
    @State private var busy = false

    static func state(_ session: DeskSession) -> String {
        if session.receiptJSON != nil { return "receipt back" }
        if session.sentAt != nil { return "sent, waiting for the vault" }
        if session.isLocked { return "locked, not sent" }
        return "open"
    }

    private var bank: DeskBank? { desk.bank(session.bankID) }

    var body: some View {
        let rows = desk.eventRows(session)
        List {
            summary(rows)
            actions
            if let receipt = session.receipt { receiptSection(receipt, rows: rows) }
            eventsSection(rows)
        }
        .navigationTitle(session.bankTitle)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Lock this session?", isPresented: $confirmLock, titleVisibility: .visible) {
            Button("Lock session", role: .destructive) { lock() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Locking is final. A locked session takes no more decisions, and only a locked session can be exported.")
        }
        .alert("Not done", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) { problem = nil }
        } message: {
            Text(problem ?? "")
        }
        .alert("Desk", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
        .overlay { if busy { ProgressView() } }
        .fullScreenCover(item: $sitting) { s in
            DeskDeckView(bank: s.bank, session: s.session, cards: s.cards)
        }
    }

    private func summary(_ rows: [DeskDecisionEvent]) -> some View {
        Section {
            LabeledContent("State", value: Self.state(session))
            LabeledContent("Mode", value: session.modeRaw)
            if let bank {
                let decided = bank.cards.count - desk.pending(session, bank: bank).count
                LabeledContent("Decided", value: "\(decided) of \(bank.cards.count)")
                ForEach(desk.dispositions(session, bank: bank), id: \.action) { row in
                    LabeledContent(row.action.replacingOccurrences(of: "_", with: " "), value: "\(row.count)")
                        .font(.callout)
                }
            } else {
                Text("This bank is no longer bundled. Its events are kept on the phone.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            LabeledContent("Events", value: "\(rows.count)")
        }
    }

    @ViewBuilder
    private var actions: some View {
        Section {
            if !session.isLocked, let bank {
                Button("Resume sitting", systemImage: "play.fill") {
                    let cards = desk.pending(session, bank: bank)
                    if cards.isEmpty {
                        problem = "Every task has a disposition. Lock the session to export it."
                    } else {
                        sitting = DeskHomeView.Sitting(bank: bank, session: session, cards: cards)
                    }
                }
                Button("Lock session", systemImage: "lock") { confirmLock = true }
                    .disabled(desk.eventRows(session).isEmpty)
            }
            if session.isLocked, bank != nil, session.receiptJSON == nil {
                Button(session.sentAt == nil ? "Send to the vault" : "Send again", systemImage: "paperplane") {
                    Task { await send() }
                }
                .disabled(busy || !connection.isConfigured)
                if session.sentAt != nil {
                    Button("Check for the receipt", systemImage: "arrow.down.doc") {
                        Task { await checkReceipt() }
                    }
                    .disabled(busy || !connection.isConfigured)
                }
                ShareLink(
                    item: JSONExportFile(text: desk.exportText(session), filename: desk.exportFilename(session)),
                    preview: SharePreview("Desk decisions (JSON)", image: Image(systemName: "tray.and.arrow.up"))
                ) {
                    Label("Share the file instead", systemImage: "square.and.arrow.up")
                }
            }
        } footer: {
            if session.isLocked {
                Text("A sent session waits in the server inbox until `kb desk pull` imports it on the Mac; its receipt then comes back here.")
            } else {
                Text("Every decision is already saved on the phone. Undo appends a retraction; the original stays in the record.")
            }
        }
    }

    private func send() async {
        busy = true
        defer { busy = false }
        do {
            try await desk.send(session, via: connection)
            notice = "Sent. Run `kb desk pull` on the Mac to import it."
        } catch {
            problem = error.localizedDescription
        }
    }

    private func checkReceipt() async {
        busy = true
        defer { busy = false }
        do {
            switch try await desk.checkReceipt(session, via: connection) {
            case .receipt: notice = "The receipt is attached."
            case .pending: notice = "Still waiting in the inbox: run `kb desk pull` on the Mac."
            case .rejected(let why): problem = "The vault importer refused this session:\n\(why)"
            case .unknown: problem = "The server has no record of this session. Send it again."
            }
        } catch {
            problem = error.localizedDescription
        }
    }

    private func receiptSection(_ receipt: DeskReceipt, rows: [DeskDecisionEvent]) -> some View {
        let subjects = Dictionary(rows.map { ($0.decisionID, $0.subjectID) }, uniquingKeysWith: { a, _ in a })
        return Section {
            ForEach(receipt.summary.states.sorted { $0.key < $1.key }, id: \.key) { state, count in
                LabeledContent(DeskReceipt.label(state), value: "\(count)")
            }
            if !receipt.summary.complete {
                Label(
                    "Incomplete: \(receipt.summary.recoveryOperations.count) operation(s) need `kb desk recover`.",
                    systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            ForEach(receipt.rows, id: \.decisionID) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(subjects[row.decisionID] ?? row.decisionID)
                        .font(.caption.monospaced())
                    Text(DeskReceipt.label(row.state))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.state == "blocked" ? .red : .secondary)
                    ForEach(Array((row.blockers ?? []).enumerated()), id: \.offset) { _, b in
                        Text(b.string ?? String(describing: b.any))
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Text("Receipt · \(receipt.issuedAt.prefix(16))")
        } footer: {
            Text("A retraction after an applied change only marks the record. Reversing a vault edit needs a new reviewed action.")
        }
    }

    private func eventsSection(_ rows: [DeskDecisionEvent]) -> some View {
        let effective = Set(
            (bank?.cards ?? []).compactMap { DeskLedger.effective(rows.map(\.record), task: $0.taskID)?.decisionID })
        return Section("Events") {
            ForEach(rows.reversed(), id: \.decisionID) { e in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("#\(e.sequence)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(e.kind == "retract" ? "undo \(e.action)" : e.action)
                            .font(.subheadline.weight(.medium))
                            .strikethrough(e.kind == "decision" && !effective.contains(e.decisionID))
                    }
                    Text(e.subjectID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if let note = e.note {
                        Text(note)
                            .font(.caption)
                    }
                }
                .swipeActions {
                    if !session.isLocked, effective.contains(e.decisionID),
                        let card = bank?.cards.first(where: { $0.taskID == e.taskID })
                    {
                        Button("Undo", systemImage: "arrow.uturn.backward") {
                            do { try desk.undo(session, card: card) } catch { problem = error.localizedDescription }
                        }
                        .tint(.orange)
                    }
                }
            }
        }
    }

    private func lock() {
        do { try desk.lock(session) } catch { problem = error.localizedDescription }
    }
}
