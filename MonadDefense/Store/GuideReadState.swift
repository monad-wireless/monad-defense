import Foundation
import Observation

/// Which guide steps the reader has opened. Kept in `UserDefaults`, not
/// SwiftData: it is a reading position, not study progress, and it must never
/// touch the FSRS queue or the review logs that the Stats tab reports.
@MainActor
@Observable
final class GuideReadState {
    private static let key = "guide.read.v1"
    private(set) var read: Set<String>

    init() {
        read = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func markRead(_ stepID: String) {
        guard !read.contains(stepID) else { return }
        read.insert(stepID)
        UserDefaults.standard.set(Array(read).sorted(), forKey: Self.key)
    }

    func readCount(_ steps: [GuideStep]) -> Int {
        steps.filter { read.contains($0.id) }.count
    }

    func reset() {
        read = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
