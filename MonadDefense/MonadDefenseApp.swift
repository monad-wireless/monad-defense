import SwiftData
import SwiftUI

@main
struct MonadDefenseApp: App {
    let container: ModelContainer
    let store: StudyStore
    let desk: DeskStore
    let connection: DeskConnection
    let spans = ClaimSpanCache()

    init() {
        do {
            // `CardNote` stays registered although nothing writes it since
            // IP-172 removed the card-note pass: dropping a model from an
            // existing store is a migration this app does not need to risk.
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
        connection = DeskConnection()
        #if DEBUG
        DebugRouter.configureServer(connection)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(store)
                .environment(desk)
                .environment(connection)
                .environment(spans)
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
