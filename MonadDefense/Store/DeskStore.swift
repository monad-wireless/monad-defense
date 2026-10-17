import Foundation
import SwiftData
import SwiftUI

// MARK: - Desk store (IP-161, IP-172) — the only writer of desk sessions and events
//
// Banks come from two places: read-only `DeskBank-*.json` resources in the
// bundle, and banks downloaded from the Desk API into Application Support
// (`DeskBanks/`), which survive without a network. A downloaded bank wins over
// a bundled one with the same id. Every decision is saved explicitly before
// the card advances; a failed save rolls back and throws, and the deck keeps
// the card on screen. Nothing here touches the study progress models, and no
// desk row is pruned when its bank disappears.
//
// Sync: sessions and events from other devices arrive through `apply` and are
// read-only here. A session is written (events, lock, send) only by the device
// that opened it, because a session is one linear event chain and two devices
// appending offline would fork it. What another device decided still counts:
// `pending` leaves out every task with an effective decision in ANY session of
// the bank, so the Mac picks up where the phone stopped.

@MainActor
@Observable
final class DeskStore {
    private(set) var banks: [DeskBank] = []
    /// Files that failed to load, with the reason. Shown, never hidden.
    private(set) var bankProblems: [String] = []
    /// When the server's bank list was last read, for the status row.
    private(set) var lastRefresh: Date?
    let actorID = "researcher"
    let deviceID: String
    private let context: ModelContext
    private let bundle: Bundle
    /// Bumped after every write so views that read through this store refresh.
    private(set) var revision = 0

    static let resourcePrefix = "DeskBank-"
    private static let deviceKey = "desk.deviceID"

    init(context: ModelContext, bundle: Bundle = .main) {
        self.context = context
        self.bundle = bundle
        if let stored = UserDefaults.standard.string(forKey: Self.deviceKey) {
            self.deviceID = stored
        } else {
            let fresh = DeskLedger.newID()
            UserDefaults.standard.set(fresh, forKey: Self.deviceKey)
            self.deviceID = fresh
        }
        reloadBanks()
    }

    // MARK: Banks

    /// Where downloaded banks live: one file per bank, named by a digest of its id.
    static var cacheDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "DeskBanks", directoryHint: .isDirectory)
    }

    private func reloadBanks() {
        var byID: [String: DeskBank] = [:]
        var problems: [String] = []
        func load(_ url: URL, name: String) {
            do {
                let bank = try DeskBank.load(try Data(contentsOf: url), resourceName: name)
                byID[bank.bankID] = bank
            } catch {
                problems.append("\(name): \(error.localizedDescription)")
            }
        }
        let bundled = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(Self.resourcePrefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in bundled { load(url, name: url.deletingPathExtension().lastPathComponent) }
        let cached = (try? FileManager.default.contentsOfDirectory(at: Self.cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in cached where url.pathExtension == "json" { load(url, name: "server") }
        banks = byID.values.sorted { ($0.compiledAt ?? "") > ($1.compiledAt ?? "") }
        bankProblems = problems
    }

    /// Download every bank the server lists that is not cached at its current version.
    /// Returns how many banks changed. Throws when the server cannot be read.
    @discardableResult
    func refresh(from connection: DeskConnection) async throws -> Int {
        let list = try await connection.decode(BankList.self, "/api/banks")
        try FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        var changed = 0
        for summary in list.banks {
            let file = Self.cacheDirectory.appending(path: "\(Self.fileStem(summary.bankID)).json")
            let tagFile = file.appendingPathExtension("etag")
            if (try? String(contentsOf: tagFile, encoding: .utf8)) == summary.etag,
                FileManager.default.fileExists(atPath: file.path())
            {
                continue
            }
            let data = try await connection.get("/api/banks/\(summary.bankID)")
            _ = try DeskBank.load(data, resourceName: "server")  // refuse what the phone cannot use
            try data.write(to: file, options: .atomic)
            try summary.etag.write(to: tagFile, atomically: true, encoding: .utf8)
            changed += 1
        }
        // A bank the server no longer lists was unpublished (`kb desk unpublish`).
        // Its cached copy goes, unless a session on this phone still needs it to
        // show or export its decisions.
        let listed = Set(list.banks.map { "\(Self.fileStem($0.bankID)).json" })
        let inUse = Set(sessions.map { "\(Self.fileStem($0.bankID)).json" })
        let cached = (try? FileManager.default.contentsOfDirectory(at: Self.cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in cached where url.pathExtension == "json" {
            let name = url.lastPathComponent
            guard !listed.contains(name), !inUse.contains(name) else { continue }
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("etag"))
            changed += 1
        }
        lastRefresh = .now
        reloadBanks()
        return changed
    }

    private static func fileStem(_ bankID: String) -> String {
        String(bankID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" })
    }

    // MARK: Sending to the vault (IP-172)

    /// Send a locked session to the Desk API inbox; `kb desk pull` imports it.
    func send(_ session: DeskSession, via connection: DeskConnection) async throws {
        // An export carries `exported_at`, so another device's copy would be
        // other bytes for the same session id, and the inbox refuses those (409).
        try requireOwn(session)
        try await connection.sendExport(try exportData(session))
        session.sentAt = .now
        try save()
    }

    /// Ask the server for the session's receipt and attach it when it has come back.
    func checkReceipt(_ session: DeskSession, via connection: DeskConnection) async throws -> ReceiptState {
        let state = try await connection.receipt(sessionID: session.sessionID)
        if case .receipt(let data) = state { try importReceipt(data) }
        return state
    }

    func bank(_ id: String) -> DeskBank? { banks.first { $0.bankID == id } }

    // MARK: Sessions

    var sessions: [DeskSession] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<DeskSession>(sortBy: [SortDescriptor(\.created, order: .reverse)]))) ?? []
    }

    func sessions(for bank: DeskBank) -> [DeskSession] {
        sessions.filter { $0.bankID == bank.bankID }
    }

    func isOwn(_ session: DeskSession) -> Bool { session.deviceID == deviceID }

    /// "this device", or the name another device sent with its sync batches.
    func deviceName(_ session: DeskSession) -> String {
        isOwn(session) ? "this device" : (deviceLabels[session.deviceID] ?? "another device")
    }

    private static let labelsKey = "desk.deviceLabels"

    /// Names other devices sent with their sync batches, by device id.
    private(set) var deviceLabels: [String: String] =
        (UserDefaults.standard.dictionary(forKey: DeskStore.labelsKey) as? [String: String]) ?? [:]

    func learn(device id: String, label: String) {
        guard id != deviceID, deviceLabels[id] != label else { return }
        deviceLabels[id] = label
        UserDefaults.standard.set(deviceLabels, forKey: Self.labelsKey)
    }

    private func requireOwn(_ session: DeskSession) throws {
        guard isOwn(session) else { throw DeskError.foreignSession(deviceName(session)) }
    }

    /// Resume this device's newest unlocked session on this bank, or start one.
    func openSession(for bank: DeskBank) throws -> DeskSession {
        if let open = sessions(for: bank).first(where: { !$0.isLocked && isOwn($0) }) { return open }
        let session = DeskSession(bank: bank, actorID: actorID, deviceID: deviceID)
        context.insert(session)
        try save()
        return session
    }

    // MARK: Events

    func eventRows(_ session: DeskSession) -> [DeskDecisionEvent] {
        _ = revision
        let id = session.sessionID
        let predicate = #Predicate<DeskDecisionEvent> { $0.sessionID == id }
        return (try? context.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.sequence)]))) ?? []
    }

    func events(_ session: DeskSession) -> [DeskEventRecord] {
        eventRows(session).map(\.record)
    }

    func effective(_ session: DeskSession, _ card: DeskCard) -> DeskEventRecord? {
        DeskLedger.effective(events(session), task: card.taskID)
    }

    /// Cards with no effective decision, in bank order. Resuming a session
    /// starts here. A card decided in any other session of the same bank (an
    /// earlier locked one, or one on another device) is not shown again: a
    /// bank can be worked through in batches and on several devices.
    func pending(_ session: DeskSession, bank: DeskBank) -> [DeskCard] {
        let events = events(session)
        let elsewhere = decidedTasks(bank, excluding: session.sessionID)
        return bank.cards.filter { !elsewhere.contains($0.taskID) && DeskLedger.effective(events, task: $0.taskID) == nil }
    }

    /// Tasks with an effective decision in some session of the bank.
    private func decidedTasks(_ bank: DeskBank, excluding sessionID: String? = nil) -> Set<String> {
        Set(
            sessions(for: bank)
                .filter { $0.sessionID != sessionID }
                .flatMap { s in
                    let past = self.events(s)
                    return bank.cards.compactMap { DeskLedger.effective(past, task: $0.taskID) != nil ? $0.taskID : nil }
                })
    }

    /// Tasks of the bank decided anywhere, on any device: the bank row's progress.
    func decidedAnywhere(_ bank: DeskBank) -> Int { decidedTasks(bank).count }

    /// Decisions in force in this session (retractions excluded).
    func decidedCount(_ session: DeskSession, bank: DeskBank) -> Int {
        let events = events(session)
        return bank.cards.filter { DeskLedger.effective(events, task: $0.taskID) != nil }.count
    }

    /// Lock, then send: the one-step way a batch of decisions leaves the phone.
    func lockAndSend(_ session: DeskSession, via connection: DeskConnection) async throws {
        try lock(session)
        try await send(session, via: connection)
    }

    /// Effective decisions per action, for the session summary.
    func dispositions(_ session: DeskSession, bank: DeskBank) -> [(action: String, count: Int)] {
        let events = events(session)
        var counts: [String: Int] = [:]
        for card in bank.cards {
            if let e = DeskLedger.effective(events, task: card.taskID) { counts[e.action, default: 0] += 1 }
        }
        return counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    func record(
        _ session: DeskSession, bank: DeskBank, card: DeskCard,
        action: String, payload: [String: Any], note: String?
    ) throws {
        try requireOwn(session)
        guard !session.isLocked else { throw DeskError.sessionLocked }
        let event = try DeskLedger.decision(
            on: card, bank: bank, action: action, payload: payload, note: note, after: events(session))
        context.insert(DeskDecisionEvent(sessionID: session.sessionID, record: event))
        try save()
    }

    /// Undo appends a retraction; the original decision stays in the record.
    func undo(_ session: DeskSession, card: DeskCard) throws {
        try requireOwn(session)
        guard !session.isLocked else { throw DeskError.sessionLocked }
        let event = try DeskLedger.retraction(of: card, after: events(session))
        context.insert(DeskDecisionEvent(sessionID: session.sessionID, record: event))
        try save()
    }

    /// Locking is final: the importer accepts only a locked session, and a
    /// locked session takes no further events.
    func lock(_ session: DeskSession) throws {
        try requireOwn(session)
        guard !session.isLocked else { return }
        session.lockedAt = .now
        try save()
    }

    // MARK: Export and receipt

    func exportData(_ session: DeskSession) throws -> Data {
        guard session.isLocked else { throw DeskError.receiptMismatch("Lock the session before exporting it.") }
        guard let bank = bank(session.bankID) else {
            throw DeskError.receiptMismatch("The bank of this session is no longer on this device; its events are kept.")
        }
        return try DeskLedger.export(
            bank: bank, sessionID: session.sessionID, actorID: session.actorID, deviceID: session.deviceID,
            events: events(session), exportedAt: DeskLedger.timestamp())
    }

    func exportText(_ session: DeskSession) -> String {
        guard let data = try? exportData(session) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func exportFilename(_ session: DeskSession) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return "desk-\(session.stackRaw)-\(f.string(from: session.lockedAt ?? session.created))-\(session.sessionID.prefix(8)).json"
    }

    /// Attach a receipt to the session it answers. A receipt for another
    /// bank or for a session this phone does not hold is refused.
    @discardableResult
    func importReceipt(_ data: Data) throws -> DeskSession {
        let receipt = try DeskReceipt.load(data)
        guard let session = sessions.first(where: { $0.sessionID == receipt.sessionID }) else {
            throw DeskError.receiptMismatch("No session \(receipt.sessionID.prefix(8)) on this device.")
        }
        guard session.bankID == receipt.bankID else {
            throw DeskError.receiptMismatch("The receipt names another bank than its session.")
        }
        session.receiptJSON = String(decoding: data, as: UTF8.self)
        session.receiptImportedAt = .now
        try save()
        return session
    }

    // MARK: Sync

    /// This device's sessions and events that changed at or after `since`.
    /// Records from other devices are not sent back: they are theirs to send.
    func syncRecords(since: Date) -> [SyncRecord] {
        let own = sessions.filter(isOwn)
        var out = own.filter { $0.lastChanged >= since }.map(\.syncRecord)
        let parser = ISO8601DateFormatter()
        for session in own {
            for e in eventRows(session) {
                // `decidedAt` has whole seconds; the caller's window overlaps for that.
                guard let at = parser.date(from: e.decidedAt), at >= since else { continue }
                out.append(e.syncRecord)
            }
        }
        return out
    }

    /// Merge another device's sessions and events. Returns how many rows changed.
    @discardableResult
    func apply(_ records: [SyncRecord]) throws -> Int {
        var byID = Dictionary(sessions.map { ($0.sessionID, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = 0
        for r in records where r.type == SyncRecord.Kind.deskSession {
            guard let id = r.sessionID, r.deviceID != deviceID else { continue }
            if let existing = byID[id] {
                if existing.absorb(r) { changed += 1 }
            } else {
                let session = DeskSession(synced: r)
                context.insert(session)
                byID[id] = session
                changed += 1
            }
        }
        let known = Set(((try? context.fetch(FetchDescriptor<DeskDecisionEvent>())) ?? []).map(\.decisionID))
        var inserted = Set<String>()
        for r in records where r.type == SyncRecord.Kind.deskEvent {
            // An event may arrive before its session (the cursor never re-reads
            // it), so it is kept either way; only this device's own are skipped.
            let ownSession = r.sessionID.flatMap { byID[$0] }.map(isOwn) ?? false
            guard let id = r.decisionID, !known.contains(id), !inserted.contains(id), !ownSession,
                let event = DeskDecisionEvent.synced(r)
            else { continue }
            context.insert(event)
            inserted.insert(id)
            changed += 1
        }
        if changed > 0 { try save() }
        return changed
    }

    // MARK: Save

    private func save() throws {
        do {
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            revision += 1
            throw DeskError.saveFailed(error.localizedDescription)
        }
    }
}
