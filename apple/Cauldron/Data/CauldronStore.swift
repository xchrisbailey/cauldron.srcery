import Foundation
import SwiftData

/// Where Cauldron's data lives: one SwiftData store, synced through the iCloud private database.
enum CauldronStore {
  static let cloudContainerID = "iCloud.computer.srcery.cauldron"

  static let models: [any PersistentModel.Type] = [
    RecipeRecord.self, PhotoRecord.self, TagRecord.self, CookRecord.self,
    PlanEntryRecord.self, PlannedBatchRecord.self, GatherItemRecord.self, GatherSourceRecord.self,
    PantryItemRecord.self,
    DiaryEntryRecord.self, FavouriteRecord.self, WeighInRecord.self, BodyProfileRecord.self,
    TargetsRecord.self, PreferencesRecord.self, AIJobRecord.self,
    HealthDismissalRecord.self,
  ]

  static var schema: Schema { Schema(models) }

  enum Mode: Sendable {
    /// On disk, mirrored to the iCloud private database.
    case synced
    /// On disk on this device only.
    case local
    /// Nothing is written to disk. For tests and previews; each container is separate.
    case inMemory
  }

  /// The App Group the app and its extensions share. The store lives in its container, so the
  /// widget and the share extension read the same data as the app.
  static let appGroupID = AppGroupName.id

  /// In debug builds, `-localStore` opens a store kept on this device only, in a file of its
  /// own, so demo data (`-seed`) never reaches iCloud.
  static let localStoreArgument = "-localStore"

  /// What the app opens at launch: the synced store, or under test an in-memory one so a test
  /// run never touches the real store.
  static var launchMode: Mode {
    launchMode(
      environment: ProcessInfo.processInfo.environment, arguments: CommandLine.arguments)
  }

  static func launchMode(environment: [String: String], arguments: [String]) -> Mode {
    if environment["XCTestConfigurationFilePath"] != nil { return .inMemory }
    #if DEBUG
      if arguments.contains(localStoreArgument) { return .local }
    #endif
    return .synced
  }

  /// The store file for `mode`, in a folder of Cauldron's own inside the App Group container.
  /// A build without the App Group (no signing team) falls back to Application Support.
  /// SwiftData's default is `Application Support/default.store`, which an unsandboxed Mac app
  /// shares with every other unsandboxed app that left the default alone, so it is never used.
  static func storeURL(_ mode: Mode = .synced, fileManager: FileManager = .default) throws -> URL {
    let root =
      try fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
      ?? fileManager.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let folder = root.appending(path: "computer.srcery.cauldron", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    // The synced store and a debug local one are separate files, so they never mix.
    return folder.appending(path: mode == .local ? "Cauldron-local.store" : "Cauldron.store")
  }

  static func container(_ mode: Mode) throws -> ModelContainer {
    let schema = schema
    let configuration =
      switch mode {
      case .synced:
        ModelConfiguration(
          schema: schema, url: try storeURL(.synced),
          cloudKitDatabase: .private(cloudContainerID))
      case .local:
        ModelConfiguration(schema: schema, url: try storeURL(.local), cloudKitDatabase: .none)
      case .inMemory:
        ModelConfiguration(
          UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      }
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}
