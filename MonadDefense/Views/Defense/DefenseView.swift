import SwiftUI

// MARK: - Defense tab (IP-172): review, tracks, the thesis guide, progress
//
// Four screens that were tabs. Each keeps its own navigation stack: the thesis
// guide drives its path programmatically for deep links, so nesting it under
// another stack would break that.
//
// On a phone a segmented control above them switches. On an iPad or a Mac the
// four are a sidebar list beside the screen, like the Library: the floating tab
// bar of a wide window covers the top edge, and a control pinned there sat
// under it (2026-10-17, iPad Air simulator).

struct DefenseView: View {
    enum Part: String, CaseIterable, Identifiable {
        case today = "Today"
        case tracks = "Tracks"
        case thesis = "Thesis"
        case progress = "Progress"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .tracks: "square.stack.3d.up"
            case .thesis: "function"
            case .progress: "chart.bar.xaxis"
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var part: Part = DefenseView.initialPart

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List(Part.allCases, selection: Binding(get: { part }, set: { if let p = $0 { part = p } })) { p in
                    Label(p.rawValue, systemImage: p.symbol).tag(p)
                }
                .navigationTitle("Defense")
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            } detail: {
                screen
            }
        } else {
            screen
                .safeAreaInset(edge: .top, spacing: 0) {
                    Picker("Part", selection: $part) {
                        ForEach(Part.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch part {
        case .today: TodayView()
        case .tracks: TracksView()
        case .thesis: GuideView()
        case .progress: StatsView()
        }
    }

    private static var initialPart: Part {
        #if DEBUG
        if DebugRouter.demoGuideStepID != nil { return .thesis }
        #endif
        return .today
    }
}
