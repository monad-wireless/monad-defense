import SwiftUI

// IP-172: three jobs, three tabs. Curate decides, Library reads, Defense prepares.
struct RootView: View {
    @State private var selection = RootView.initialTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Curate", systemImage: "tray.full", value: "curate") {
                NavigationStack { DeskHomeView() }
            }
            Tab("Library", systemImage: "books.vertical", value: "library") {
                LibraryView()
            }
            Tab("Defense", systemImage: "graduationcap", value: "defense") {
                DefenseView()
            }
        }
        .tint(Theme.accent)
    }

    private static var initialTab: String {
        #if DEBUG
        if let tab = DebugRouter.demoTab { return tab }
        if DebugRouter.demoPaper != nil { return "library" }
        // The screenshot launch arguments open screens that live under Defense.
        if DebugRouter.demoGuideStepID != nil || !DebugRouter.demoCardIDs.isEmpty
            || DebugRouter.demoReaderID != nil || DebugRouter.demoFiguresID != nil
        {
            return "defense"
        }
        #endif
        return "curate"
    }
}

#Preview {
    RootView()
}
