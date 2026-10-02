import SwiftUI

struct RootView: View {
    @State private var selection = RootView.initialTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: "today") {
                TodayView()
            }
            Tab("Tracks", systemImage: "books.vertical", value: "tracks") {
                TracksView()
            }
            Tab("Thesis", systemImage: "function", value: "thesis") {
                GuideView()
            }
            Tab("Curate", systemImage: "square.and.pencil", value: "curate") {
                CurateView()
            }
            Tab("Stats", systemImage: "chart.xyaxis.line", value: "stats") {
                StatsView()
            }
        }
        .tint(Theme.accent)
    }

    private static var initialTab: String {
        #if DEBUG
        if DebugRouter.demoGuideStepID != nil { return "thesis" }
        #endif
        return "today"
    }
}

#Preview {
    RootView()
}
