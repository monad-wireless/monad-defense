import SwiftData
import SwiftUI

@main
struct MonadDefenseApp: App {
    let container: ModelContainer
    let store: StudyStore
    let desk: DeskStore
    let connection: DeskConnection
    let sync: SyncStore
    let spans = ClaimSpanCache()
    @Environment(\.scenePhase) private var scenePhase

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
        sync = SyncStore(desk: desk, study: store, connection: connection)
        #if DEBUG
        DebugRouter.configureServer(connection)
        DebugRouter.recordDemoReview(store)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(store)
                .environment(desk)
                .environment(connection)
                .environment(sync)
                .environment(spans)
                .modelContainer(container)
                // Sync runs while the app is in front: on launch, on return,
                // and every five minutes, so a sitting on the phone shows on
                // the Mac without anyone pressing anything.
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await sync.sync()
                        try? await Task.sleep(for: .seconds(300))
                    }
                }
        }
        .commands {
            RootCommands()
            DeskCommands()
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
