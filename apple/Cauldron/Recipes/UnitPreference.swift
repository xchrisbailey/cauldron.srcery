import CauldronKit
import SwiftData

/// How quantities are shown (as written, metric or US), kept in `PreferencesRecord`. As on the
/// web, it is one choice for the cook, not one per page: the recipe's page sets it and brew
/// mode reads it, on this device and the others.
enum UnitPreference {
  /// The choice that changed last, else as written.
  static func current(_ preferences: [PreferencesRecord]) -> UnitSystemChoice {
    Deduplication.keeper(of: preferences)?.unitSystem ?? .asWritten
  }

  /// The same, read from the store.
  static func current(in context: ModelContext) -> UnitSystemChoice {
    (try? context.current(PreferencesRecord.self))?.unitSystem ?? .asWritten
  }

  /// Keeps the cook's choice, making the preference if there is none yet.
  @MainActor
  static func set(
    _ choice: UnitSystemChoice, preferences: [PreferencesRecord], in context: ModelContext
  ) {
    let record = Deduplication.keeper(of: preferences) ?? PreferencesRecord()
    if record.modelContext == nil { context.insert(record) }
    guard record.unitSystem != choice else { return }
    record.unitSystem = choice
    try? context.save()
  }
}
