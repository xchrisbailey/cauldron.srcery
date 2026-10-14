import CauldronKit
import SwiftUI

/// The app's frame: a tab bar on iPhone, and a sidebar next to the section on a Mac or an iPad.
/// The selection lives here, so a window that changes size keeps its place.
struct AppShell: View {
  @State private var destination = AppDestination.recipes
  /// Counts the links that asked for today's diary. The tracker is rebuilt on each, so it comes
  /// back to the diary on today whatever it was showing.
  @State private var trackerVisits = 0
  @Environment(SyncStatusModel.self) private var sync
  @Environment(SharedImportQueue.self) private var sharing: SharedImportQueue?
  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif

  var body: some View {
    Group {
      if usesTabBar {
        tabs
      } else {
        sidebar
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) { SyncBanner(status: sync.status) }
    .background(Brand.Colors.base.ignoresSafeArea())
    // Something shared to Cauldron opens its import in Recipes.
    .onChange(of: sharing?.readyToOpen ?? false, initial: true) { _, ready in
      if ready { destination = .recipes }
    }
    .onOpenURL { url in
      if let link = AppLink(url: url) { open(link) }
    }
    #if os(macOS)
      .focusedSceneValue(\.navigationCommands, NavigationCommands { destination = $0 })
    #endif
  }

  /// Goes where a `cauldron://` link points.
  private func open(_ link: AppLink) {
    destination = link.destination
    trackerVisits += 1
  }

  private var usesTabBar: Bool {
    #if os(iOS)
      horizontalSizeClass == .compact
    #else
      false
    #endif
  }

  private var tabs: some View {
    TabView(selection: $destination) {
      ForEach(AppDestination.allCases) { destination in
        Tab(value: destination) {
          AppDestinationView(destination: destination, visit: visit(of: destination))
        } label: {
          AppDestinationLabel(destination: destination)
        }
      }
    }
  }

  /// On iPad the selected row is `magic` (lavender in Mocha), where the system's white text has
  /// no contrast; `base` reads on it in both appearances. The Mac keeps the system highlight.
  private func sidebarRow(_ row: AppDestination) -> some View {
    let label = AppDestinationLabel(destination: row)
    #if os(iOS)
      return label.foregroundStyle(destination == row ? Brand.Colors.base : Brand.Colors.ink)
        .tag(row)
    #else
      return label.tag(row)
    #endif
  }

  private var sidebar: some View {
    // `List` selection is optional; a deselect keeps the current destination.
    let selection = Binding<AppDestination?>(
      get: { destination },
      set: { if let next = $0 { destination = next } })
    return NavigationSplitView {
      List(selection: selection) {
        Section {
          ForEach(AppDestination.sections) { section in
            sidebarRow(section)
          }
        }
        Section {
          sidebarRow(.settings)
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.mantle)
      .navigationTitle(Copy.ui.appName.text)
    } detail: {
      AppDestinationView(destination: destination, visit: visit(of: destination))
    }
  }

  private func visit(of destination: AppDestination) -> Int {
    destination == .tracker ? trackerVisits : 0
  }
}

/// A destination's icon and name, for a tab or a sidebar row.
struct AppDestinationLabel: View {
  let destination: AppDestination

  var body: some View {
    Label {
      Text(verbatim: destination.title.text)
    } icon: {
      Image(systemName: destination.systemImage)
    }
  }
}

/// The screen a destination opens, with the brand's text colour set once at its root. Each
/// section's root is its own view, in its own folder. The sidebar and tab bar are left to the
/// system, so a selected row keeps its contrast.
struct AppDestinationView: View {
  let destination: AppDestination
  /// A new value rebuilds the section, so it starts again from its first screen.
  var visit = 0

  var body: some View {
    root.foregroundStyle(Brand.Colors.ink).id(visit)
  }

  @ViewBuilder
  private var root: some View {
    switch destination {
    case .recipes: RecipesRoot()
    case .week: WeekRoot()
    case .gather: GatherRoot()
    case .tracker: TrackerRoot()
    case .settings: SettingsView()
    }
  }
}
