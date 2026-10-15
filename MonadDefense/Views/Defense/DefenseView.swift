import SwiftUI

// MARK: - Defense tab (IP-172): review, tracks, the thesis guide, progress
//
// Four screens that were tabs. Each keeps its own navigation stack: the thesis
// guide drives its path programmatically for deep links, so nesting it under
// another stack would break that. A segmented control above them switches.

struct DefenseView: View {
    enum Part: String, CaseIterable, Identifiable {
        case today = "Today"
        case tracks = "Tracks"
        case thesis = "Thesis"
        case progress = "Progress"

        var id: String { rawValue }
    }

    @State private var part: Part = DefenseView.initialPart

    var body: some View {
        Group {
            switch part {
            case .today: TodayView()
            case .tracks: TracksView()
            case .thesis: GuideView()
            case .progress: StatsView()
            }
        }
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

    private static var initialPart: Part {
        #if DEBUG
        if DebugRouter.demoGuideStepID != nil { return .thesis }
        #endif
        return .today
    }
}
