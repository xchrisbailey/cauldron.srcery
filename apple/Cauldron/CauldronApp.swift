import CauldronImports
import CauldronKit
import Network
import SwiftData
import SwiftUI

@main
struct CauldronApp: App {
  private let container: ModelContainer
  private let changeStamps: ChangeStamps
  @Environment(\.scenePhase) private var scenePhase
  @State private var sync = SyncStatusModel(
    account: LiveICloudAccount(mode: CauldronStore.launchMode))
  @State private var ai = RecipeAIService.forLaunch(mode: CauldronStore.launchMode)
  /// What the share extension left for the app; never picked up under test.
  @State private var sharedImports = SharedImportQueue(
    enabled: CauldronStore.launchMode != .inMemory)

  init() {
    Brand.Fonts.register()
    do {
      container = try CauldronStore.container(CauldronStore.launchMode)
    } catch {
      // Without its store the app can do nothing useful, and carrying on in memory would
      // quietly lose whatever was entered.
      fatalError("Cauldron couldn't open its data store: \(error)")
    }
    changeStamps = ChangeStamps(on: container.mainContext)
    CauldronStore.tidyAtLaunch(container.mainContext, mode: CauldronStore.launchMode)
    // The share sheet's duplicate check reads this, so it starts from what the store holds.
    SavedLinksIndex.live.rewrite(from: container.mainContext)
    // An export left in the temporary folder is a full copy of the cook's data.
    ExportFiles.sweep()
    // Takes the notification delegate now, so a timer that ends with the app open shows its
    // banner even when no recipe has been brewed since launch.
    _ = LiveBrewAlerts.shared
    #if DEBUG
      // Demo data, only when launched with `-seed`, and only into an empty store.
      do {
        try DebugSeed.populateIfRequested(
          arguments: CommandLine.arguments, mode: CauldronStore.launchMode,
          context: ModelContext(container), today: DebugSeed.today())
      } catch {
        fatalError("Cauldron couldn't seed its data store: \(error)")
      }
    #endif
  }

  var body: some Scene {
    WindowGroup(id: "main") {
      AppShell()
        #if os(macOS)
          // The sidebar, the library and a recipe side by side need this much; below it the
          // recipe page is cramped.
          .frame(minWidth: 960, minHeight: 600)
        #endif
        .environment(sync)
        .environment(ai)
        .sharedImports(sharedImports, ai: ai)
        .task { await sync.run() }
        // The share extension reads the AI choices from the App Group, so they follow Settings
        // there whenever the app comes forward or goes away.
        .onChange(of: scenePhase, initial: true) {
          guard CauldronStore.launchMode != .inMemory else { return }
          RecipeAIService.shareChoices(to: RecipeAIService.sharedDefaults)
        }
        // Estimates that waited for the AI run when the app comes forward and whenever the
        // network comes back.
        .task(id: scenePhase) {
          guard scenePhase == .active else { return }
          RecipeAIService.moveKeys(mode: CauldronStore.launchMode)
          ai.refreshKey()
          await AIQueueRunner.drain(in: container.mainContext, using: ai.estimator)
        }
        .task {
          for await path in NWPathMonitor() where path.status == .satisfied {
            await AIQueueRunner.drain(in: container.mainContext, using: ai.estimator)
          }
        }
        // Health follows the diary whichever section is open: weights come in and the
        // diary's nutrition is put right each time the app comes forward. It does nothing
        // until Health is connected.
        .task(id: scenePhase) {
          guard scenePhase == .active else { return }
          await HealthSync.shared.appDidBecomeActive(in: container.mainContext)
        }
        // The macros widget follows the diary: its numbers are left for it when the app starts,
        // comes forward or goes away, and when midnight passes.
        .publishesTodayMacros(from: container.mainContext)
        .cauldronAppearance()
    }
    .modelContainer(container)
    .macWindowSize(width: 1280, height: 820)
    .macReusesWindowForLinks()
    .macMenuBar()
    #if os(macOS)
      // A recipe in a window of its own, one for each recipe.
      WindowGroup(
        Copy.pageTitles.recipe.text, id: WindowID.recipe, for: RecipeWindowRequest.self
      ) { $request in
        if let request {
          RecipeWindow(request: request)
            .environment(sharedImports)
            .environment(sync)
            .environment(ai)
            .cauldronAppearance()
        }
      }
      .modelContainer(container)
      .defaultSize(width: 920, height: 800)
      // Brew mode, one window for each recipe being cooked.
      WindowGroup(Copy.pageTitles.brew.text, id: "brew", for: BrewRequest.self) { $request in
        if let request {
          BrewWindow(request: request)
            .environment(sync)
            .cauldronAppearance()
        }
      }
      .modelContainer(container)
      .defaultSize(width: 760, height: 820)
      Settings {
        SettingsView()
          .environment(sync)
          .environment(ai)
          .frame(minWidth: 480, idealWidth: 540, minHeight: 420, idealHeight: 680)
          .cauldronAppearance()
      }
      .modelContainer(container)
    #endif
  }
}

extension Scene {
  /// The size a Mac window opens at. Other platforms size their own windows.
  fileprivate func macWindowSize(width: CGFloat, height: CGFloat) -> some Scene {
    #if os(macOS)
      defaultSize(width: width, height: height)
    #else
      self
    #endif
  }

  /// A `cauldron://` link from the widget goes to the window that is open, not a new one.
  fileprivate func macReusesWindowForLinks() -> some Scene {
    #if os(macOS)
      handlesExternalEvents(matching: ["*"])
    #else
      self
    #endif
  }

  /// The Mac's menu bar.
  fileprivate func macMenuBar() -> some Scene {
    #if os(macOS)
      commands { CauldronCommands() }
    #else
      self
    #endif
  }
}
