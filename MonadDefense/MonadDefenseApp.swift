import SwiftData
import SwiftUI

@main
struct MonadDefenseApp: App {
    let container: ModelContainer
    let store: StudyStore

    init() {
        do {
            container = try ModelContainer(
                for: CardProgress.self, ReviewLog.self, SessionResult.self, CardNote.self,
                TriageDecision.self)
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
        store = StudyStore(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .modelContainer(container)
        }
    }
}
