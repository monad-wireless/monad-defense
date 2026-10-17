import SwiftUI

// IP-172: three jobs, three tabs. Curate decides, Library reads, Defense prepares.
//
// `.sidebarAdaptable` keeps the tab bar on a phone and becomes a sidebar on an
// iPad and a Mac, where a window is wide enough to show the section list
// beside the work. The Go menu (⌘1–⌘3) reaches the same selection through a
// focused scene value, so each window switches its own tabs.
struct RootView: View {
    @State private var selection = RootView.initialTab
    /// The Desk server sheet, from ⌘, (Settings). Curate keeps its own button.
    @State private var serverSheet = false

    enum TabID: String, CaseIterable {
        case curate, library, defense

        var title: String {
            switch self {
            case .curate: "Curate"
            case .library: "Library"
            case .defense: "Defense"
            }
        }

        var symbol: String {
            switch self {
            case .curate: "tray.full"
            case .library: "books.vertical"
            case .defense: "graduationcap"
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(TabID.curate.title, systemImage: TabID.curate.symbol, value: TabID.curate) {
                NavigationStack { DeskHomeView() }
            }
            Tab(TabID.library.title, systemImage: TabID.library.symbol, value: TabID.library) {
                LibraryView()
            }
            Tab(TabID.defense.title, systemImage: TabID.defense.symbol, value: TabID.defense) {
                DefenseView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.accent)
        .focusedSceneValue(\.rootTab, $selection)
        .focusedSceneValue(\.deskServerSheet, $serverSheet)
        .sheet(isPresented: $serverSheet) { ConnectionSheet() }
        .onAppear { MacWindow.configure() }
    }

    private static var initialTab: TabID {
        #if DEBUG
        if let tab = DebugRouter.demoTab, let id = TabID(rawValue: tab) { return id }
        if DebugRouter.demoPaper != nil { return .library }
        // The screenshot launch arguments open screens that live under Defense.
        if DebugRouter.demoGuideStepID != nil || !DebugRouter.demoCardIDs.isEmpty
            || DebugRouter.demoReaderID != nil || DebugRouter.demoFiguresID != nil
        {
            return .defense
        }
        #endif
        return .curate
    }
}

extension FocusedValues {
    /// The focused window's tab, for the Go menu.
    @Entry var rootTab: Binding<RootView.TabID>?
    /// The focused window's Desk server sheet, for Settings (⌘,).
    @Entry var deskServerSheet: Binding<Bool>?
}

/// Settings is the Desk server: the one thing this app is configured with.
struct DeskCommands: Commands {
    @FocusedBinding(\.deskServerSheet) private var serverSheet

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Desk Server…") { serverSheet = true }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(serverSheet == nil)
        }
    }
}

/// The Go menu. On iPad it lists the same commands in the ⌘-hold overlay.
struct RootCommands: Commands {
    @FocusedBinding(\.rootTab) private var tab

    var body: some Commands {
        CommandMenu("Go") {
            ForEach(Array(RootView.TabID.allCases.enumerated()), id: \.element) { i, id in
                Button(id.title) { tab = id }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .disabled(tab == nil)
            }
        }
    }
}

#Preview {
    RootView()
}
