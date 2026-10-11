#if os(iOS)
  import CauldronKit
  import Foundation
  import HealthKit

  /// Health on the iPhone. Reads body mass and writes dietary energy, protein, carbohydrates and
  /// total fat, and asks for nothing else: active energy and every other type stay unread.
  ///
  /// Each written sample carries a sync identifier and version, which Health uses to replace an
  /// earlier sample of the same name; that is how an entry's sample is updated in place and found
  /// again to delete. This type asks for access only when told to, and only builds with the
  /// usage descriptions and the HealthKit entitlement should be asked to (see `HealthSetup`).
  struct LiveHealthStore: HealthStore, @unchecked Sendable {
    private let store = HKHealthStore()

    var availability: HealthAvailability {
      HKHealthStore.isHealthDataAvailable() ? .supported : .unsupported
    }

    private static let bodyMass = HKQuantityType(.bodyMass)

    private static func type(for nutrient: Nutrient) -> HKQuantityType {
      switch nutrient {
      case .energy: HKQuantityType(.dietaryEnergyConsumed)
      case .protein: HKQuantityType(.dietaryProtein)
      case .carbs: HKQuantityType(.dietaryCarbohydrates)
      case .fat: HKQuantityType(.dietaryFatTotal)
      }
    }

    private static func unit(for nutrient: Nutrient) -> HKUnit {
      nutrient == .energy ? .kilocalorie() : .gram()
    }

    func requestAuthorization() async throws {
      guard HKHealthStore.isHealthDataAvailable() else { throw HealthFailure() }
      let share = Set(Nutrient.allCases.map(Self.type(for:)))
      try await store.requestAuthorization(toShare: share, read: [Self.bodyMass])
    }

    /// The nutrients the cook has allowed Cauldron to write, one by one: each can be refused in
    /// Health on its own.
    func writableNutrients() async -> Set<Nutrient> {
      Set(
        Nutrient.allCases.filter {
          store.authorizationStatus(for: Self.type(for: $0)) == .sharingAuthorized
        })
    }

    /// Cauldron's own dietary samples: the ones this app wrote (its source) that carry a sync
    /// identifier. Not yet checked against real Health.
    func nutritionSamples(since date: Date) async throws -> [HeldNutrition] {
      let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        HKQuery.predicateForSamples(withStart: date, end: nil),
        HKQuery.predicateForObjects(from: [HKSource.default()]),
        HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier),
      ])
      var held: [HeldNutrition] = []
      for nutrient in Nutrient.allCases {
        let descriptor = HKSampleQueryDescriptor(
          predicates: [.quantitySample(type: Self.type(for: nutrient), predicate: predicate)],
          sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
        for sample in try await descriptor.result(for: store) {
          guard let id = sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
            HealthNutrition.nutrient(of: id) == nutrient
          else { continue }
          held.append(
            HeldNutrition(
              syncID: id, value: sample.quantity.doubleValue(for: Self.unit(for: nutrient)),
              date: sample.startDate,
              name: sample.metadata?[HKMetadataKeyFoodType] as? String ?? "",
              version: (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue ?? 0))
        }
      }
      return held
    }

    func bodyMass(since date: Date) async throws -> [HealthWeightSample] {
      let predicate = HKQuery.predicateForSamples(withStart: date, end: nil)
      let descriptor = HKSampleQueryDescriptor(
        predicates: [.quantitySample(type: Self.bodyMass, predicate: predicate)],
        sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
      return try await descriptor.result(for: store).map {
        HealthWeightSample(
          id: $0.uuid.uuidString, date: $0.startDate,
          kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
      }
    }

    func save(_ samples: [NutritionSample], version: Int) async throws {
      // A save that includes a type the cook refused fails as a whole, so only the allowed
      // ones go.
      let allowed = await writableNutrients()
      let objects = samples.filter { allowed.contains($0.nutrient) }.map { sample in
        HKQuantitySample(
          type: Self.type(for: sample.nutrient),
          quantity: HKQuantity(unit: Self.unit(for: sample.nutrient), doubleValue: sample.value),
          start: sample.date, end: sample.date,
          metadata: [
            HKMetadataKeySyncIdentifier: sample.syncID,
            HKMetadataKeySyncVersion: version,
            HKMetadataKeyFoodType: sample.name,
          ])
      }
      if !objects.isEmpty { try await store.save(objects) }
    }

    func deleteNutrition(syncIDs: [String]) async throws {
      let predicate = HKQuery.predicateForObjects(
        withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: syncIDs)
      for nutrient in await writableNutrients() {
        _ = try await store.deleteObjects(of: Self.type(for: nutrient), predicate: predicate)
      }
    }
  }
#endif
