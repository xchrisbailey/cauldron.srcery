import CauldronKit
import Foundation
import Observation
import SwiftData

/// Keeps Cauldron and Health in step: weigh-ins come in from Health, and the diary goes out to
/// Health's nutrition data. It does nothing until the cook connects Health in Settings, and the
/// connection is a choice of this device (kept in `UserDefaults`), since only the iPhone has Health.
///
/// The diary is made to match Health by `reconcile` (see `HealthReconcile`), which runs when
/// Health is connected, when the app comes forward and after each diary change; the writes a
/// change makes straight away are a fast path that reconcile then confirms. Writes go out in
/// order, one at a time, and a failure is remembered for Settings to show without ever
/// stopping a diary change.
@MainActor
@Observable
final class HealthSync {
  enum Status: Equatable {
    /// This build lacks what asking for Health needs (see `HealthSetup`).
    case notSetUp
    /// This device has no Health.
    case unavailable
    /// Available, not connected.
    case off
    case on
  }

  static let shared: HealthSync = {
    switch CauldronStore.launchMode {
    case .synced, .local:
      HealthSync(store: liveStore, setup: .thisBuild)
    case .inMemory, .unavailable:
      disabled()
    }
  }()

  static func forLaunch(mode: CauldronStore.Mode) -> HealthSync {
    switch mode {
    case .synced, .local: shared
    case .inMemory, .unavailable: disabled()
    }
  }

  /// A test/preview service that can be instrumented without ever consulting Health or defaults.
  static func disabled(
    store: any HealthStore = UnavailableHealthStore(), defaults: UserDefaults = .standard
  ) -> HealthSync {
    HealthSync(
      store: store, setup: HealthSetup(isConfigured: false), defaults: defaults,
      accessAllowed: false)
  }

  static let enabledKey = "health.enabled"

  /// Health's weights are looked at for this many days back.
  static let importDays = 365

  @ObservationIgnored private let store: any HealthStore
  @ObservationIgnored private let setup: HealthSetup
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let calendar: Calendar
  @ObservationIgnored private let now: @MainActor () -> Date
  @ObservationIgnored private let accessAllowed: Bool
  @ObservationIgnored private var tail: Task<Void, Never>?
  @ObservationIgnored private var reconcileQueued = false
  @ObservationIgnored private var importing: Task<Int, Never>?
  /// The last version sent, so two saves in a millisecond still rise.
  @ObservationIgnored private var lastVersion = 0
  private var enabled: Bool

  /// What Settings says after the last attempt; nil when all went well.
  private(set) var failure: CopyString?
  /// How many weigh-ins the last check changed.
  private(set) var lastImportCount: Int?
  /// Nutrients Health won't take from Cauldron, as the cook set it in Health.
  private(set) var deniedNutrients: [Nutrient] = []

  init(
    store: any HealthStore, setup: HealthSetup, defaults: UserDefaults = .standard,
    calendar: Calendar = DayKeyCalendar.current, now: @escaping @MainActor () -> Date = { .now },
    accessAllowed: Bool = true
  ) {
    self.store = store
    self.setup = setup
    self.defaults = defaults
    self.calendar = calendar
    self.now = now
    self.accessAllowed = accessAllowed
    enabled = accessAllowed && defaults.bool(forKey: Self.enabledKey)
  }

  private static var liveStore: any HealthStore {
    #if os(iOS)
      LiveHealthStore()
    #else
      UnavailableHealthStore()
    #endif
  }

  var status: Status {
    guard accessAllowed else { return .notSetUp }
    guard setup.isConfigured else { return .notSetUp }
    guard store.availability == .supported else { return .unavailable }
    return enabled ? .on : .off
  }

  /// Asks for access, and connects when it is given.
  func connect() async {
    guard status == .off else { return }
    do {
      try await store.requestAuthorization()
      enabled = true
      defaults.set(true, forKey: Self.enabledKey)
      failure = nil
      await refreshPermissions()
    } catch {
      failure = Copy.settings.health.couldntConnect
    }
  }

  /// Stops reading and writing. What is already in Health stays there.
  func disconnect() {
    guard accessAllowed else { return }
    enabled = false
    defaults.set(false, forKey: Self.enabledKey)
    failure = nil
    deniedNutrients = []
  }

  /// Which nutrients Health will take, as it is now.
  func refreshPermissions() async {
    guard status == .on else { return }
    let writable = await store.writableNutrients()
    deniedNutrients = Nutrient.allCases.filter { !writable.contains($0) }
  }

  private var today: LocalDate? { LocalDate(now(), in: calendar) }

  /// The one call for the app coming forward, whichever section is open: weights in, diary out.
  func appDidBecomeActive(in context: ModelContext) async {
    guard status == .on else { return }
    await importWeights(into: context)
    await reconcile(in: context)
  }

  // MARK: Weigh-ins in

  /// Brings Health's weights into the weigh-ins (see `HealthWeightImport`). Returns how many
  /// weigh-ins changed. Calls that overlap share one run, so a weight is never imported twice.
  @discardableResult
  func importWeights(into context: ModelContext) async -> Int {
    guard status == .on else { return 0 }
    if let running = importing { return await running.value }
    let run = Task { await self.runImport(into: context) }
    importing = run
    let count = await run.value
    importing = nil
    return count
  }

  private func runImport(into context: ModelContext) async -> Int {
    guard let today else { return 0 }
    let window = today.adding(days: -Self.importDays)...today
    guard let since = window.lowerBound.date(in: calendar) else { return 0 }
    do {
      let samples = try await store.bodyMass(since: since)
      // Read after the wait, so a change made meanwhile is seen.
      let existing = try HealthWeightImport.existing(in: window, context: context)
      let importedSampleIDs = try HealthWeightImport.importedSampleIDs(in: context)
      let plan = HealthWeightImport.plan(
        samples: samples, existing: existing,
        dismissed: try HealthWeightImport.dismissed(in: context),
        window: window, importedSampleIDs: importedSampleIDs, calendar: calendar)
      try HealthWeightImport.apply(plan, in: context)
      lastImportCount = plan.count
      failure = nil
      return plan.count
    } catch {
      failure = Copy.settings.health.couldntConnect
      return 0
    }
  }

  // MARK: Diary out

  /// A diary change was made: write what it changed straight away, then make sure Health
  /// matches the diary.
  func diaryChanged(saved: [HealthEntry], removed: [UUID], in context: ModelContext) {
    guard status == .on else { return }
    var plans = saved.map { HealthNutrition.plan(for: $0, calendar: calendar) }
    plans += removed.map(HealthNutrition.removal(of:))
    if !plans.isEmpty { send(plans) }
    scheduleReconcile(in: context)
  }

  /// Entries were added or changed: bring their samples up to date.
  func entriesSaved(_ entries: [HealthEntry]) {
    guard status == .on, !entries.isEmpty else { return }
    send(entries.map { HealthNutrition.plan(for: $0, calendar: calendar) })
  }

  /// Entries were deleted: take their samples out.
  func entriesRemoved(_ ids: [UUID]) {
    guard status == .on, !ids.isEmpty else { return }
    send(ids.map(HealthNutrition.removal(of:)))
  }

  /// Makes Health match the last `HealthReconcile.windowDays` days of the diary.
  func reconcile(in context: ModelContext) async {
    guard status == .on else { return }
    scheduleReconcile(in: context)
    await settle()
  }

  private func scheduleReconcile(in context: ModelContext) {
    guard !reconcileQueued else { return }
    reconcileQueued = true
    let previous = tail
    tail = Task {
      await previous?.value
      self.reconcileQueued = false
      await self.runReconcile(in: context)
    }
  }

  private func runReconcile(in context: ModelContext) async {
    guard status == .on, let today else { return }
    let first = today.adding(days: -(HealthReconcile.windowDays - 1))
    guard let since = first.date(in: calendar) else { return }
    let key = first.description
    do {
      // The low-key clause retains Japanese-era keys; Buddhist keys are above the window.
      let legacyBefore = "1900"
      let rows = try context.fetch(
        FetchDescriptor<DiaryEntryRecord>(
          predicate: #Predicate { $0.dayKey >= key || $0.dayKey < legacyBefore }))
      let entries = rows.compactMap(HealthEntry.init).filter { entry in
        entry.day.isLegacyCalendarKey || entry.day >= first
      }
      let writable = await store.writableNutrients()
      deniedNutrients = Nutrient.allCases.filter { !writable.contains($0) }
      let held = try await store.nutritionSamples(since: since)
      let plan = HealthReconcile.plan(
        entries: entries, held: held, writable: writable, calendar: calendar)
      guard !plan.save.isEmpty || !plan.delete.isEmpty else {
        failure = nil
        return
      }
      let floor = (held.map(\.version).max() ?? 0) + 1
      try await write(plan.save, delete: plan.delete, atLeast: floor)
      failure = nil
    } catch {
      failure = Copy.settings.health.couldntUpdate
    }
  }

  private func send(_ plans: [NutritionPlan]) {
    let samples = plans.flatMap(\.save)
    let deletes = plans.flatMap(\.delete)
    let previous = tail
    tail = Task {
      await previous?.value
      do {
        let writable = await self.store.writableNutrients()
        self.deniedNutrients = Nutrient.allCases.filter { !writable.contains($0) }
        try await self.write(
          samples.filter { writable.contains($0.nutrient) },
          delete: deletes.filter { id in
            HealthNutrition.nutrient(of: id).map(writable.contains) ?? false
          },
          atLeast: 0)
        self.failure = nil
      } catch {
        self.failure = Copy.settings.health.couldntUpdate
      }
    }
  }

  /// Deletes, then saves, with a version above every earlier one.
  private func write(_ samples: [NutritionSample], delete: [String], atLeast floor: Int)
    async throws
  {
    let version = max(lastVersion + 1, floor, Int(now().timeIntervalSince1970 * 1000))
    lastVersion = version
    if !delete.isEmpty { try await store.deleteNutrition(syncIDs: delete) }
    if !samples.isEmpty { try await store.save(samples, version: version) }
  }

  /// Waits for the writes made so far to finish.
  func settle() async {
    await tail?.value
  }
}
