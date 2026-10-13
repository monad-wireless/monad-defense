import SwiftData
import SwiftUI

@main
struct MonadDefenseApp: App {
    let container: ModelContainer
    let store: StudyStore
    let desk: DeskStore

    init() {
        do {
            container = try ModelContainer(
                for: CardProgress.self, ReviewLog.self, SessionResult.self, CardNote.self,
                TriageDecision.self, DeskSession.self, DeskDecisionEvent.self)
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
        store = StudyStore(context: container.mainContext)
        // Its own context: autosave off (explicit saves), and a rollback after a
        // failed desk save cannot discard pending study progress.
        desk = DeskStore(context: ModelContext(container))
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(store)
                .environment(desk)
                .modelContainer(container)
        }
    }

    /// Debug builds accept `-desk-open <bank resource name>` to start straight
    /// in that Desk sitting: simulator screenshots and UI checks need no taps.
    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if let bank = UserDefaults.standard.string(forKey: "desk-open") {
            NavigationStack { DeskHomeView(autoOpen: bank) }
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
