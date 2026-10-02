import SwiftUI

/// The Thesis tab: the thesis's mathematics, figure by figure and equation by
/// equation, in reading order from school level. Modules are the six decks of
/// `publications/thesis-math/`; a lesson opens a pager of its steps.
struct GuideView: View {
    @State private var guide = ThesisGuide.loadBundled()
    @State private var readState = GuideReadState()
    @State private var path: [LessonRoute] = []

    /// A lesson and the step to open it at. The start travels in the route
    /// itself: state set beside the path is read by the destination too late.
    struct LessonRoute: Hashable {
        let lesson: GuideLesson
        var start = 0
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let guide {
                    content(guide)
                } else {
                    ContentUnavailableView(
                        "No thesis guide bundled",
                        systemImage: "function",
                        description: Text("Run `monad-knowledge edu guide compile` in the research repo and rebuild."))
                }
            }
            .navigationTitle("Thesis")
            .navigationDestination(for: LessonRoute.self) { route in
                LessonView(
                    lesson: route.lesson, module: guide?.modules.first { $0.lessons.contains(route.lesson) },
                    startIndex: route.start)
            }
        }
        .environment(readState)
        .onAppear(perform: openDemoStep)
    }

    /// DEBUG: `-DemoGuideStep <id>` opens the lesson that holds that step, at it.
    private func openDemoStep() {
        #if DEBUG
        guard path.isEmpty, let id = DebugRouter.demoGuideStepID, let guide else { return }
        for lesson in guide.modules.flatMap(\.lessons) {
            if let i = lesson.steps.firstIndex(where: { $0.id == id }) {
                path = [LessonRoute(lesson: lesson, start: i)]
                return
            }
        }
        #endif
    }

    private func content(_ guide: ThesisGuide) -> some View {
        List {
            Section {
                header(guide)
            }
            ForEach(guide.modules) { module in
                Section {
                    ForEach(module.lessons) { lesson in
                        NavigationLink(value: LessonRoute(lesson: lesson)) {
                            lessonRow(lesson)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(module.code) · \(module.title)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                        Text(module.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
        }
    }

    private func header(_ guide: ThesisGuide) -> some View {
        let done = guide.modules.reduce(0) { $0 + readState.readCount($1.lessons.flatMap(\.steps)) }
        let total = guide.stepCount
        return HStack(spacing: 14) {
            ZStack {
                ProgressRing(progress: total == 0 ? 0 : Double(done) / Double(total), tint: Theme.accent, lineWidth: 5)
                Image(systemName: "function")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(guide.title)
                    .font(.headline)
                Text("\(done)/\(total) steps read · thesis revision \(guide.thesisRevision)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func lessonRow(_ lesson: GuideLesson) -> some View {
        let done = readState.readCount(lesson.steps)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(lesson.title)
                    .font(.subheadline)
                Spacer()
                Text("\(done)/\(lesson.steps.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(done == lesson.steps.count ? Theme.accent : .secondary)
            }
            if !lesson.thesis.isEmpty {
                InlineMathText(lesson.thesis, font: .caption1)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One lesson as a pager of steps. Opening a step marks it read.
struct LessonView: View {
    let lesson: GuideLesson
    let module: GuideModule?
    @Environment(GuideReadState.self) private var readState
    let startIndex: Int
    @State private var index: Int

    init(lesson: GuideLesson, module: GuideModule?, startIndex: Int = 0) {
        self.lesson = lesson
        self.module = module
        self.startIndex = startIndex
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(lesson.steps.enumerated()), id: \.element.id) { i, step in
                ScrollView {
                    StepView(step: step, lessonTitle: lesson.title)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                }
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { pagerBar }
        .onAppear { mark() }
        .task {
            // A paged TabView can reset to its first page while it lays out, so
            // a start other than the first step is applied again once it is on screen.
            guard startIndex > 0 else { return }
            try? await Task.sleep(for: .milliseconds(350))
            index = startIndex
        }
        .onChange(of: index) { mark() }
    }

    private func mark() {
        guard lesson.steps.indices.contains(index) else { return }
        readState.markRead(lesson.steps[index].id)
    }

    private var pagerBar: some View {
        HStack {
            Button {
                withAnimation { index = max(0, index - 1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(index == 0)
            Spacer()
            VStack(spacing: 2) {
                Text("Step \(index + 1) of \(lesson.steps.count)")
                    .font(.caption.weight(.semibold))
                if let module {
                    Text("\(module.code) · \(lesson.thesis)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                withAnimation { index = min(lesson.steps.count - 1, index + 1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(index >= lesson.steps.count - 1)
        }
        .font(.title3)
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
