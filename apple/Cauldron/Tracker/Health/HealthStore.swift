import CauldronKit
import Foundation

/// What is dietary in Health: the four numbers a diary entry carries.
enum Nutrient: String, CaseIterable, Sendable {
  case energy
  case protein
  case carbs
  case fat

  init(_ key: MacroKey) {
    switch key {
    case .calories: self = .energy
    case .protein: self = .protein
    case .carbs: self = .carbs
    case .fat: self = .fat
    }
  }

  var macroKey: MacroKey {
    switch self {
    case .energy: .calories
    case .protein: .protein
    case .carbs: .carbs
    case .fat: .fat
    }
  }
}

/// A body mass reading in Health.
struct HealthWeightSample: Equatable, Sendable {
  /// Health's own id for the sample.
  var id: String
  var date: Date
  var kg: Double
}

/// A dietary sample Cauldron writes. `syncID` is the stable name of the sample in Health: saving
/// one with a later `version` replaces the earlier, so a change to an entry never duplicates it,
/// and the sample can be found again to delete without Cauldron keeping any Health ids.
struct NutritionSample: Equatable, Sendable {
  var syncID: String
  var nutrient: Nutrient
  /// Kilocalories for energy, grams for the rest.
  var value: Double
  var date: Date
  /// What was eaten, kept with the sample.
  var name: String
}

/// One of Cauldron's own dietary samples as Health holds it.
struct HeldNutrition: Equatable, Sendable {
  var syncID: String
  var value: Double
  var date: Date
  var name: String
  var version: Int
}

/// How far Health is usable here.
enum HealthAvailability: Equatable, Sendable {
  /// This device has no Health (a Mac, an iPad without it).
  case unsupported
  case supported
}

struct HealthFailure: Error, Equatable {
  var message: String

  init(_ message: String = "") {
    self.message = message
  }
}

/// What Cauldron needs of Health. The live one is `LiveHealthStore` (iPhone); tests use a double.
/// Cauldron reads body mass and writes dietary energy, protein, carbs and fat, and nothing else.
protocol HealthStore: Sendable {
  var availability: HealthAvailability { get }
  /// Asks for access: to read body mass and to write the four dietary types. Throws when it
  /// can't be asked.
  func requestAuthorization() async throws
  /// Body mass readings from `date` on, newest first.
  func bodyMass(since date: Date) async throws -> [HealthWeightSample]
  /// The nutrients Cauldron may write to. The cook can allow some and refuse others in Health,
  /// and a save that includes a refused type fails as a whole.
  func writableNutrients() async -> Set<Nutrient>
  /// Cauldron's own dietary samples (written by this app, with a sync identifier) dated from
  /// `date` on.
  func nutritionSamples(since date: Date) async throws -> [HeldNutrition]
  /// Saves the samples, each replacing the one that has its `syncID`. `version` rises with
  /// every save.
  func save(_ samples: [NutritionSample], version: Int) async throws
  /// Deletes the samples with these ids, wherever they are.
  func deleteNutrition(syncIDs: [String]) async throws
}

/// For a device with no Health.
struct UnavailableHealthStore: HealthStore {
  var availability: HealthAvailability { .unsupported }
  func requestAuthorization() async throws { throw HealthFailure() }
  func bodyMass(since date: Date) async throws -> [HealthWeightSample] { [] }
  func writableNutrients() async -> Set<Nutrient> { [] }
  func nutritionSamples(since date: Date) async throws -> [HeldNutrition] { [] }
  func save(_ samples: [NutritionSample], version: Int) async throws {}
  func deleteNutrition(syncIDs: [String]) async throws {}
}

/// Whether this build can ask for Health at all. Asking without the usage descriptions in the
/// Info.plist, or without the HealthKit entitlement, stops the app, so the section only offers
/// it when both usage descriptions are present (they are added together with the entitlement).
struct HealthSetup: Equatable, Sendable {
  static let shareKey = "NSHealthShareUsageDescription"
  static let updateKey = "NSHealthUpdateUsageDescription"

  var isConfigured: Bool

  init(isConfigured: Bool) {
    self.isConfigured = isConfigured
  }

  init(info: [String: Any]?) {
    func text(_ key: String) -> Bool {
      guard let value = info?[key] as? String else { return false }
      return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    isConfigured = text(Self.shareKey) && text(Self.updateKey)
  }

  static var thisBuild: HealthSetup { HealthSetup(info: Bundle.main.infoDictionary) }
}
