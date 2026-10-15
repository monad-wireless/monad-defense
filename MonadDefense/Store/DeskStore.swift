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

    /// Resume the newest unlocked session on this bank, or start one.
    func openSession(for bank: DeskBank) throws -> DeskSession {
        if let open = sessions(for: bank).first(where: { !$0.isLocked }) { return open }
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
    /// starts here.
    func pending(_ session: DeskSession, bank: DeskBank) -> [DeskCard] {
        let events = events(session)
        return bank.cards.filter { DeskLedger.effective(events, task: $0.taskID) == nil }
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
        guard !session.isLocked else { throw DeskError.sessionLocked }
        let event = try DeskLedger.decision(
            on: card, bank: bank, action: action, payload: payload, note: note, after: events(session))
        context.insert(DeskDecisionEvent(sessionID: session.sessionID, record: event))
        try save()
    }

    /// Undo appends a retraction; the original decision stays in the record.
    func undo(_ session: DeskSession, card: DeskCard) throws {
        guard !session.isLocked else { throw DeskError.sessionLocked }
        let event = try DeskLedger.retraction(of: card, after: events(session))
        context.insert(DeskDecisionEvent(sessionID: session.sessionID, record: event))
        try save()
    }

    /// Locking is final: the importer accepts only a locked session, and a
    /// locked session takes no further events.
    func lock(_ session: DeskSession) throws {
        guard !session.isLocked else { return }
        session.lockedAt = .now
        try save()
    }

    // MARK: Export and receipt

    func exportData(_ session: DeskSession) throws -> Data {
        guard session.isLocked else { throw DeskError.receiptMismatch("Lock the session before exporting it.") }
        guard let bank = bank(session.bankID) else {
            throw DeskError.receiptMismatch("The bank of this session is no longer on the phone; its events are kept.")
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
            throw DeskError.receiptMismatch("No session \(receipt.sessionID.prefix(8)) on this phone.")
        }
        guard session.bankID == receipt.bankID else {
            throw DeskError.receiptMismatch("The receipt names another bank than its session.")
        }
        session.receiptJSON = String(decoding: data, as: UTF8.self)
        session.receiptImportedAt = .now
        try save()
        return session
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
