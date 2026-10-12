import CauldronKit
import SwiftData
import SwiftUI

@main
struct CauldronApp: App {
  private let container: ModelContainer
  private let changeStamps: ChangeStamps
  @Environment(\.scenePhase) private var scenePhase
  @State private var sync = SyncStatusModel(
    account: LiveICloudAccount(mode: CauldronStore.launchMode))

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
    WindowGroup {
      AppShell()
        .environment(sync)
        .task { await sync.run() }
        // Health follows the diary whichever section is open: weights come in and the
        // diary's nutrition is put right each time the app comes forward. It does nothing
        // until Health is connected.
        .task(id: scenePhase) {
          guard scenePhase == .active else { return }
          await HealthSync.shared.appDidBecomeActive(in: container.mainContext)
        }
        .cauldronAppearance()
    }
    .modelContainer(container)
    #if os(macOS)
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
          .frame(minWidth: 420, minHeight: 360)
          .cauldronAppearance()
      }
      .modelContainer(container)
    #endif
  }
}
