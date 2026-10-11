import SwiftData
import SwiftUI

@main
struct CauldronApp: App {
  private let container: ModelContainer
  private let changeStamps: ChangeStamps
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
        .cauldronAppearance()
    }
    .modelContainer(container)
    #if os(macOS)
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
