import Foundation
import Observation
import UIKit

// MARK: - Device sync through the Desk API (`/api/sync`)
//
// One pass: push what this device wrote since its last push, then pull every
// batch the server stored after the cursor and hand the records to the two
// stores that own them. The stores merge by record identity (see
// `SyncModels.swift`), so a pass can be repeated, interrupted or run on a
// stale cursor without harm. That is the whole correctness argument, and it is
// why both windows below overlap on purpose:
//
// - push: from `lastPush − 5 s`. A Desk event's `decidedAt` has whole
//   seconds, so an event decided in the cutoff's second would otherwise fall
//   out of both windows. Wider costs a re-sent batch on every pass (seen
//   2026-10-17 at ten minutes: one review posted three times in a minute).
// - pull: from `cursor − 10 min`. A slow write on the server can land under
//   an id that sorts before one this device already read.
//
// The price of the overlap is that a record is sometimes sent or read twice.
// Applying it twice changes nothing.

@MainActor
@Observable
final class SyncStore {
    private(set) var syncing = false
    private(set) var lastSync: Date?
    private(set) var lastProblem: String?
    /// What the last pass moved, for the status row.
    private(set) var lastPushed = 0
    private(set) var lastMerged = 0

    private let desk: DeskStore
    private let study: StudyStore
    private let connection: DeskConnection

    private static let lastPushKey = "sync.lastPushMs"
    private static let cursorKey = "sync.cursor"
    private static let lastSyncKey = "sync.lastSyncMs"
    private static let pushOverlap: TimeInterval = 5
    private static let pullOverlap: TimeInterval = 10 * 60
    /// Records per POST. A first push carries every review the device ever
    /// logged; this keeps one request well under the server's byte limit.
    private static let chunk = 2_000

    init(desk: DeskStore, study: StudyStore, connection: DeskConnection) {
        self.desk = desk
        self.study = study
        self.connection = connection
        let ms = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? NSNumber
        lastSync = ms.map { Date(syncMs: $0.int64Value) }
    }

    /// A short name other devices show next to this device's sessions.
    static var deviceLabel: String {
        switch UIDevice.current.userInterfaceIdiom {
        case .mac: "Mac"
        case .pad: "iPad"
        default: "iPhone"
        }
    }

    var isAvailable: Bool { connection.isConfigured }

    /// Run one pass unless one is running. Errors land in `lastProblem`.
    func sync() async {
        guard connection.isConfigured, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            lastPushed = try await push()
            lastMerged = try await pull()
            lastProblem = nil
            let now = Date.now
            lastSync = now
            UserDefaults.standard.set(NSNumber(value: now.syncMs), forKey: Self.lastSyncKey)
        } catch {
            lastProblem = error.localizedDescription
        }
    }

    // MARK: Push

    private func push() async throws -> Int {
        let started = Date.now
        let lastMs = (UserDefaults.standard.object(forKey: Self.lastPushKey) as? NSNumber)?.int64Value
        let since = lastMs.map { Date(syncMs: $0).addingTimeInterval(-Self.pushOverlap) } ?? .distantPast
        let records = desk.syncRecords(since: since) + study.syncRecords(since: since)
        var sent = 0
        var start = 0
        while start < records.count {
            let slice = Array(records[start..<min(start + Self.chunk, records.count)])
            let batch = SyncBatch(deviceID: desk.deviceID, deviceLabel: Self.deviceLabel, records: slice)
            _ = try await connection.post("/api/sync", body: try JSONEncoder().encode(batch))
            sent += slice.count
            start += Self.chunk
        }
        // Only after every chunk landed: a failed pass sends the whole window again.
        UserDefaults.standard.set(NSNumber(value: started.syncMs), forKey: Self.lastPushKey)
        return sent
    }

    // MARK: Pull

    private func pull() async throws -> Int {
        let cursor = UserDefaults.standard.string(forKey: Self.cursorKey) ?? ""
        var after = Self.rewind(cursor, by: Self.pullOverlap)
        var merged = 0
        var last = cursor
        while true {
            let data = try await connection.get("/api/sync", query: ["after": after, "limit": "200"])
            let page = try JSONDecoder().decode(SyncPage.self, from: data)
            var records: [SyncRecord] = []
            for batch in page.batches {
                if let id = batch.deviceID, let label = batch.deviceLabel { desk.learn(device: id, label: label) }
                if batch.id > last { last = batch.id }
                // This device's own batches carry nothing it does not hold.
                guard batch.deviceID != desk.deviceID else { continue }
                records += batch.records
            }
            if !records.isEmpty {
                merged += try desk.apply(records)
                merged += study.apply(records)
            }
            guard page.more, let next = page.batches.last?.id else { break }
            after = next
        }
        UserDefaults.standard.set(last, forKey: Self.cursorKey)
        return merged
    }

    /// A batch id starts with its arrival time (`yyyyMMdd'T'HHmmss…`). The
    /// rewound cursor is that time minus `seconds`, as a prefix that sorts
    /// before every id stored in or after that second.
    static func rewind(_ cursor: String, by seconds: TimeInterval) -> String {
        guard cursor.count >= 15 else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        guard let at = f.date(from: String(cursor.prefix(15))) else { return "" }
        return f.string(from: at.addingTimeInterval(-seconds))
    }
}
