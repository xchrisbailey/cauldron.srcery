import CauldronKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

@MainActor
@Suite("App shell")
struct AppShellTests {
  @Test func theFourSectionsComeInOrderWithTheirCopy() {
    #expect(AppDestination.sections == [.recipes, .week, .gather, .tracker])
    #expect(
      AppDestination.sections.map(\.title.text) == [
        "Recipes", "The week", "Gather list", "Tracker",
      ]
    )
    #expect(AppDestination.settings.title.text == "Settings")
  }

  @Test func everyDestinationHasATitleAndAnIcon() {
    for destination in AppDestination.allCases {
      #expect(!destination.title.text.isEmpty, "\(destination)")
      #expect(!destination.systemImage.isEmpty, "\(destination)")
    }
    #expect(Set(AppDestination.allCases.map(\.systemImage)).count == AppDestination.allCases.count)
  }

  @Test func theSectionsOpenOnTheirEmptyStatesFromTheCopyModule() {
    #expect(Copy.recipes.empty.text.hasPrefix("No recipes yet"))
    #expect(Copy.week.empty.text.hasPrefix("The cauldron's cold"))
    #expect(Copy.gather.empty.text.hasPrefix("Nothing to gather yet"))
    #expect(Copy.tracker.diary.empty.text.hasPrefix("Nothing logged yet"))
  }

  @Test func everyDestinationRendersInBothAppearances() throws {
    let sync = SyncStatusModel(account: FakeICloudAccount(.synced))
    let container = try CauldronStore.container(.inMemory)
    for destination in AppDestination.allCases {
      for scheme in [ColorScheme.light, .dark] {
        let view = AppDestinationView(destination: destination)
          .environment(sync)
          .modelContainer(container)
          .environment(\.colorScheme, scheme)
          .frame(width: 390, height: 800)
        let renderer = ImageRenderer(content: view)
        #expect(renderer.cgImage != nil, "\(destination) in \(scheme)")
      }
    }
  }

  @Test func theShellRenders() throws {
    let sync = SyncStatusModel(account: FakeICloudAccount(.signedOut))
    let container = try CauldronStore.container(.inMemory)
    let renderer = ImageRenderer(
      content: AppShell().environment(sync).modelContainer(container).frame(
        width: 390, height: 800))
    #expect(renderer.cgImage != nil)
  }
}

@MainActor
@Suite("Appearance")
struct AppearanceTests {
  @Test func latteIsLightMochaIsDarkAndSystemFollowsTheDevice() {
    #expect(AppearanceChoice.system.colorScheme == nil)
    #expect(AppearanceChoice.latte.colorScheme == .light)
    #expect(AppearanceChoice.mocha.colorScheme == .dark)
  }

  @Test func theChoicesAreLabelledFromTheCopyModule() {
    #expect(AppearanceChoice.allCases.map(\.label.text) == ["System", "Latte", "Mocha"])
  }

  @Test func theChoiceIsKeptOnTheDeviceNotInPreferences() throws {
    let suite = "AppearanceTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(AppearanceChoice.mocha.rawValue, forKey: AppearanceChoice.storageKey)
    #expect(
      AppearanceChoice(rawValue: defaults.string(forKey: AppearanceChoice.storageKey) ?? "")
        == .mocha)
    // An unknown stored value is not a choice; `@AppStorage` falls back to its default.
    #expect(AppearanceChoice(rawValue: "sepia") == nil)
    let preferences = Mirror(reflecting: PreferencesRecord()).children.compactMap(\.label)
    #expect(!preferences.contains { $0.lowercased().contains("appearance") })
  }
}

@MainActor
@Suite("iCloud status")
struct ICloudStatusTests {
  @Test func eachStateHasItsOwnPlainMessage() {
    let states: [ICloudStatus] = [.checking, .notSetUp, .synced, .signedOut, .full, .unavailable]
    #expect(Set(states.map(\.message.text)).count == states.count)
    #expect(states.allSatisfy { $0.message.tone == .plain })
  }

  @Test func signedOutAndFullSayTheDataIsSafeOnTheDevice() {
    for status in [ICloudStatus.signedOut, .full, .notSetUp, .unavailable] {
      #expect(status.message.text.contains("saved on this device"), "\(status)")
    }
  }

  @Test func onlySignedOutAndFullAreRaisedOutsideSettings() {
    #expect(ICloudStatus.signedOut.needsAttention)
    #expect(ICloudStatus.full.needsAttention)
    for status in [ICloudStatus.checking, .notSetUp, .synced, .unavailable] {
      #expect(!status.needsAttention, "\(status)")
    }
  }

  @Test func aFullQuotaOutranksAnAccountButNoAccountComesFirst() {
    #expect(ICloudStatus.resolve(hasAccount: true, quotaExceeded: false) == .synced)
    #expect(ICloudStatus.resolve(hasAccount: true, quotaExceeded: true) == .full)
    #expect(ICloudStatus.resolve(hasAccount: false, quotaExceeded: false) == .signedOut)
    #expect(ICloudStatus.resolve(hasAccount: false, quotaExceeded: true) == .signedOut)
  }

  @Test func theModelStartsCheckingThenShowsWhatTheAccountReports() async {
    let account = FakeICloudAccount(.signedOut)
    let model = SyncStatusModel(account: account)
    #expect(model.status == .checking)
    let running = Task { await model.run() }
    await settle { model.status == .signedOut }
    #expect(model.status == .signedOut)
    running.cancel()
  }

  @Test func theModelFollowsChangesWhileRunning() async {
    let account = FakeICloudAccount(.synced)
    let model = SyncStatusModel(account: account)
    let running = Task { await model.run() }
    await settle { model.status == .synced }

    account.send(.full)
    await settle { model.status == .full }
    #expect(model.status == .full)

    account.send(.synced)
    await settle { model.status == .synced }
    #expect(model.status == .synced)
    running.cancel()
  }

  @Test func aBuildWithoutTheEntitlementReportsNotSetUpWithoutTouchingCloudKit() async {
    for mode in [CauldronStore.Mode.local, .inMemory] {
      let account = LiveICloudAccount(mode: mode)
      #expect(await account.status() == .notSetUp)
      var updates = 0
      for await _ in account.changes() { updates += 1 }
      #expect(updates == 0)
    }
  }

  /// Waits for `condition`, giving the model's task a chance to run, for up to two seconds.
  private func settle(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 where !condition() {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }
}

@MainActor
@Suite("Launch tidy")
struct LaunchTidyTests {
  private func duplicateTargets(in context: ModelContext, age: TimeInterval) throws {
    for _ in 0..<2 {
      let row = TargetsRecord(calories: 2000, protein: 100, carbs: 200, fat: 70)
      row.updatedAt = Date.now.addingTimeInterval(-age)
      context.insert(row)
    }
    try context.save()
  }

  @Test func leavesTheStoreAloneUnderTest() throws {
    let context = ModelContext(try CauldronStore.container(.inMemory))
    try duplicateTargets(in: context, age: Deduplication.grace * 2)
    #expect(CauldronStore.tidyAtLaunch(context, mode: .inMemory) == 0)
    #expect(try context.fetchCount(FetchDescriptor<TargetsRecord>()) == 2)
  }

  @Test func removesSettledDuplicatesOnARealLaunch() throws {
    let context = ModelContext(try CauldronStore.container(.inMemory))
    try duplicateTargets(in: context, age: Deduplication.grace * 2)
    #expect(CauldronStore.tidyAtLaunch(context, mode: .local) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TargetsRecord>()) == 1)
  }

  @Test func keepsRecentDuplicates() throws {
    let context = ModelContext(try CauldronStore.container(.inMemory))
    try duplicateTargets(in: context, age: 60)
    #expect(CauldronStore.tidyAtLaunch(context, mode: .local) == 0)
    #expect(try context.fetchCount(FetchDescriptor<TargetsRecord>()) == 2)
  }
}

/// A stand-in for iCloud that reports a state and then whatever a test sends it.
final class FakeICloudAccount: ICloudAccount, @unchecked Sendable {
  private let initial: ICloudStatus
  private let stream: AsyncStream<ICloudStatus>
  private let continuation: AsyncStream<ICloudStatus>.Continuation

  init(_ initial: ICloudStatus) {
    self.initial = initial
    (stream, continuation) = AsyncStream.makeStream()
  }

  func status() async -> ICloudStatus { initial }
  func changes() -> AsyncStream<ICloudStatus> { stream }
  func send(_ status: ICloudStatus) { continuation.yield(status) }
}
