import Foundation
import SwiftData
import SwiftUI

// MARK: - Desk store (IP-161) — the only writer of desk sessions and events
//
// Bundled banks are read-only `DeskBank-*.json` resources. Every decision is
// saved explicitly before the card advances; a failed save rolls back and
// throws, and the deck keeps the card on screen. Nothing here touches the
// study progress models, and no desk row is pruned when its bank disappears.

@MainActor
@Observable
final class DeskStore {
    let banks: [DeskBank]
    /// Bundled files that failed to load, with the reason. Shown, never hidden.
    let bankProblems: [String]
    let actorID = "researcher"
    let deviceID: String
    private let context: ModelContext
    /// Bumped after every write so views that read through this store refresh.
    private(set) var revision = 0

    static let resourcePrefix = "DeskBank-"
    private static let deviceKey = "desk.deviceID"

    init(context: ModelContext, bundle: Bundle = .main) {
        self.context = context
        var loaded: [DeskBank] = []
        var problems: [String] = []
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(Self.resourcePrefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            do {
                loaded.append(try DeskBank.load(try Data(contentsOf: url), resourceName: name))
            } catch {
                problems.append("\(name): \(error.localizedDescription)")
            }
        }
        self.banks = loaded
        self.bankProblems = problems
        if let stored = UserDefaults.standard.string(forKey: Self.deviceKey) {
            self.deviceID = stored
        } else {
            let fresh = DeskLedger.newID()
            UserDefaults.standard.set(fresh, forKey: Self.deviceKey)
            self.deviceID = fresh
        }
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
            throw DeskError.receiptMismatch("The bank of this session is no longer bundled; its events are kept.")
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
