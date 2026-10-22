import Foundation
import SwiftData
#if DEBUG && os(macOS)
  import CoreData
  import Security
#endif

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

  #if DEBUG && os(macOS)
    static let initializeSchemaArgument = "-initializeCloudKitSchema"
  #endif

  /// What the app opens at launch: the synced store, or under test an in-memory one so a test
  /// run never touches the real store.
  static var launchMode: Mode {
    launchMode(
      environment: ProcessInfo.processInfo.environment, arguments: CommandLine.arguments)
  }

  static func launchMode(environment: [String: String], arguments: [String]) -> Mode {
    if environment["XCTestConfigurationFilePath"] != nil { return .inMemory }
    #if DEBUG
      #if os(macOS)
        if arguments.contains(initializeSchemaArgument) { return .inMemory }
      #endif
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

  #if DEBUG && os(macOS)
    static func requestsSchemaInitialization(
      arguments: [String], environment: [String: String]
    ) -> Bool {
      arguments.contains(initializeSchemaArgument)
        && environment["XCTestConfigurationFilePath"] == nil
    }

    static var signedCloudEnvironment: String? {
      guard let task = SecTaskCreateFromSelf(nil) else { return nil }
      return SecTaskCopyValueForEntitlement(
        task, "com.apple.developer.icloud-container-environment" as CFString, nil) as? String
    }

    /// This is an explicit developer operation, never part of opening a normal store. Core Data
    /// initializes every entity using temporary records; it must only target Development.
    @MainActor
    static func initializeDevelopmentSchema(
      signedEnvironment: String? = signedCloudEnvironment,
      scratchRoot: URL = FileManager.default.temporaryDirectory,
      initializer: any CloudKitSchemaInitializing = LiveCloudKitSchemaInitializer()
    ) throws {
      guard signedEnvironment == "Development" else {
        throw CloudKitSchemaInitializationError.developmentSigningRequired
      }
      guard let model = NSManagedObjectModel.makeManagedObjectModel(for: models) else {
        throw CloudKitSchemaInitializationError.modelUnavailable
      }
      let scratch = scratchRoot.appending(
        path: "Cauldron-CloudKitSchema-\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
      // Only this invocation's newly created scratch directory is removed, after the persistent
      // container has released its store. The app's App Group store is never opened here.
      defer { try? FileManager.default.removeItem(at: scratch) }
      try autoreleasepool {
        try initializer.initialize(
          model: model, storeURL: scratch.appending(path: "Schema.store"),
          containerIdentifier: cloudContainerID)
      }
    }
  #endif
}

#if DEBUG && os(macOS)
  enum CloudKitSchemaInitializationError: LocalizedError {
    case developmentSigningRequired
    case modelUnavailable

    var errorDescription: String? {
      switch self {
      case .developmentSigningRequired:
        "Schema initialization requires a development-signed Debug app with the CloudKit Development entitlement."
      case .modelUnavailable:
        "Couldn't generate the Core Data model for Cauldron's schema."
      }
    }
  }

  @MainActor
  protocol CloudKitSchemaInitializing {
    func initialize(model: NSManagedObjectModel, storeURL: URL, containerIdentifier: String) throws
  }

  struct LiveCloudKitSchemaInitializer: CloudKitSchemaInitializing {
    func initialize(model: NSManagedObjectModel, storeURL: URL, containerIdentifier: String) throws
    {
      let description = NSPersistentStoreDescription(url: storeURL)
      description.shouldAddStoreAsynchronously = false
      description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
        containerIdentifier: containerIdentifier)
      let container = NSPersistentCloudKitContainer(
        name: "CauldronSchemaInitialization", managedObjectModel: model)
      container.persistentStoreDescriptions = [description]
      var loadingError: (any Error)?
      container.loadPersistentStores { _, error in loadingError = error }
      defer {
        for store in container.persistentStoreCoordinator.persistentStores {
          try? container.persistentStoreCoordinator.remove(store)
        }
      }
      if let loadingError { throw loadingError }
      try container.initializeCloudKitSchema(options: [])
    }
  }
#endif
