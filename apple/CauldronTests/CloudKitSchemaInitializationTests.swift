#if DEBUG && os(macOS)
  import CoreData
  import Foundation
  import Testing

  @testable import Cauldron

  @MainActor
  @Suite("CloudKit schema initialization")
  struct CloudKitSchemaInitializationTests {
    private final class Initializer: CloudKitSchemaInitializing {
      var storeURL: URL?
      var identifier: String?
      var entityNames: Set<String> = []
      var fail = false
      var cleanupFails = false

      func initialize(model: NSManagedObjectModel, storeURL: URL, containerIdentifier: String)
        throws
      {
        self.storeURL = storeURL
        identifier = containerIdentifier
        entityNames = Set(model.entities.compactMap(\.name))
        #expect(FileManager.default.fileExists(atPath: storeURL.deletingLastPathComponent().path))
        if fail { throw CocoaError(.fileWriteUnknown) }
      }

      func removeScratchDirectory(at url: URL) throws {
        if cleanupFails { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.removeItem(at: url)
      }
    }

    @Test func initializationRequiresExplicitLaunchAndNeverSelectsTheRealStore() {
      let flag = CauldronStore.initializeSchemaArgument
      #expect(!CauldronStore.requestsSchemaInitialization(arguments: [], environment: [:]))
      #expect(CauldronStore.requestsSchemaInitialization(arguments: [flag], environment: [:]))
      #expect(
        !CauldronStore.requestsSchemaInitialization(
          arguments: [flag],
          environment: [CauldronStore.uiTestInMemoryEnvironmentKey: "1"]))
      #expect(
        !CauldronStore.requestsSchemaInitialization(
          arguments: [flag], environment: ["XCTestConfigurationFilePath": "test"]))
      #expect(CauldronStore.launchMode(environment: [:], arguments: [flag]) == .inMemory)
    }

    @Test func productionOrMissingSigningCannotCallTheInitializer() {
      for environment in [String?.none, "Production", ""] {
        let initializer = Initializer()
        #expect(throws: CloudKitSchemaInitializationError.self) {
          try CauldronStore.initializeDevelopmentSchema(
            signedEnvironment: environment, initializer: initializer)
        }
        #expect(initializer.storeURL == nil)
      }
    }

    @Test func developmentUsesAllModelsAndCleansOnlyItsOwnScratchDirectory() throws {
      for fail in [false, true] {
        let initializer = Initializer()
        initializer.fail = fail
        do {
          try CauldronStore.initializeDevelopmentSchema(
            signedEnvironment: "Development", initializer: initializer)
          #expect(!fail)
        } catch {
          #expect(fail)
        }
        let url = try #require(initializer.storeURL)
        #expect(url.lastPathComponent == "Schema.store")
        #expect(
          url.deletingLastPathComponent().lastPathComponent.hasPrefix("Cauldron-CloudKitSchema-"))
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        #expect(initializer.identifier == CauldronStore.cloudContainerID)
        #expect(initializer.entityNames.contains("PlannedBatchRecord"))
        #expect(initializer.entityNames.count == CauldronStore.models.count)
      }
    }

    @Test func cleanupFailureReportsTheScratchPathAndPreservesInitializationFailure() throws {
      for fail in [false, true] {
        let initializer = Initializer()
        initializer.fail = fail
        initializer.cleanupFails = true
        do {
          try CauldronStore.initializeDevelopmentSchema(
            signedEnvironment: "Development", initializer: initializer)
          Issue.record("Cleanup failure must not report success")
        } catch CloudKitSchemaInitializationError.cleanupFailed(let original, _, let path) {
          #expect((original != nil) == fail)
          #expect(path == initializer.storeURL?.deletingLastPathComponent().path)
        }
        let scratch = try #require(initializer.storeURL).deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: scratch.path))
        try FileManager.default.removeItem(at: scratch)
      }
    }
  }
#endif
