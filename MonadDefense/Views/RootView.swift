import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                TodayView()
            }
            Tab("Tracks", systemImage: "books.vertical") {
                TracksView()
            }
            Tab("Curate", systemImage: "square.and.pencil") {
                CurateView()
            }
            Tab("Stats", systemImage: "chart.xyaxis.line") {
                StatsView()
            }
        }
        .tint(Theme.accent)
    }
}

#Preview {
    RootView()
}
