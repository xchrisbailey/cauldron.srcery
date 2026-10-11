import Foundation
import SwiftData

/// Where Cauldron's data lives: one SwiftData store, synced through the iCloud private database.
enum CauldronStore {
  static let cloudContainerID = "iCloud.computer.srcery.cauldron"

  static let models: [any PersistentModel.Type] = [
    RecipeRecord.self, PhotoRecord.self, TagRecord.self, CookRecord.self,
    PlanEntryRecord.self, GatherItemRecord.self, GatherSourceRecord.self, PantryItemRecord.self,
    DiaryEntryRecord.self, FavouriteRecord.self, WeighInRecord.self, BodyProfileRecord.self,
    TargetsRecord.self, PreferencesRecord.self, AIJobRecord.self,
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

  /// What the app opens at launch. It stays `.local` until the iCloud entitlement exists
  /// (#162); a synced store can't open without it. Under test the host app keeps everything
  /// in memory, so a test run never touches the real store.
  static var launchMode: Mode {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCTestConfigurationFilePath"] == nil ? .local : .inMemory
  }

  /// The store file, in a folder of Cauldron's own. SwiftData's default is
  /// `Application Support/default.store`, which an unsandboxed Mac app shares with every
  /// other unsandboxed app that left the default alone, so it is never used.
  static func storeURL(fileManager: FileManager = .default) throws -> URL {
    let support = try fileManager.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let folder = support.appending(path: "computer.srcery.cauldron", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appending(path: "Cauldron.store")
  }

  static func container(_ mode: Mode) throws -> ModelContainer {
    let schema = schema
    let configuration =
      switch mode {
      case .synced:
        ModelConfiguration(
          schema: schema, url: try storeURL(), cloudKitDatabase: .private(cloudContainerID))
      case .local:
        ModelConfiguration(schema: schema, url: try storeURL(), cloudKitDatabase: .none)
      case .inMemory:
        ModelConfiguration(
          UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      }
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}
