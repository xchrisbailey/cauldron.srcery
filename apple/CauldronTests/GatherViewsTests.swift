import CauldronKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

#if DEBUG
  @MainActor
  @Suite("Gather views")
  struct GatherViewsTests {
    /// A seeded store with the current week's list built, as opening the screen builds it.
    private func seeded() throws -> ModelContainer {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      let today = try DebugSeed.today()
      try DebugSeed.populate(context, today: today)
      try GatherPlan.commit(in: context) {
        try GatherPlan.rebuild(week: today.startOfWeek(startingOn: .monday), in: context)
        try GatherPlan.add("2 lemons", week: today.startOfWeek(startingOn: .monday), in: context)
      }
      return container
    }

    private func renders(_ view: some View, width: CGFloat, height: CGFloat) -> Bool {
      ImageRenderer(content: view.frame(width: width, height: height)).cgImage != nil
    }

    @Test func theListRendersEmptyAndSeededInBothAppearancesAtEverySize() throws {
      let empty = try CauldronStore.container(.inMemory)
      let full = try seeded()
      for container in [empty, full] {
        for scheme in [ColorScheme.light, .dark] {
          for (width, height) in [(1100.0, 800.0), (390.0, 800.0)] {
            let view = GatherRoot().modelContainer(container).environment(\.colorScheme, scheme)
            #expect(renders(view, width: width, height: height), "\(scheme) \(width)")
          }
        }
      }
    }

    @Test func aLineRendersTickedInThePantryAndAddedByHandInBothAppearances() throws {
      let context = ModelContext(try seeded())
      let today = try DebugSeed.today().startOfWeek(startingOn: .monday)
      let records = try context.fetch(FetchDescriptor<GatherItemRecord>())
      let items = GatherSnapshot(start: today, records: records, pantry: []).items
      #expect(items.count > 2)
      for var item in items.prefix(3) + items.filter(\.manual) {
        for state in [false, true] {
          item.checked = state
          item.inPantry = state
          for scheme in [ColorScheme.light, .dark] {
            let row = GatherItemRow(item: item, onCheck: { _ in }, onPantry: { _ in }, onRemove: {})
              .environment(\.colorScheme, scheme)
            #expect(renders(row, width: 390, height: 120))
            #expect(renders(row, width: 760, height: 90))
          }
        }
      }
    }

    @Test func theTickBoxRendersOnAndOff() {
      for on in [true, false] {
        let view = Toggle(isOn: .constant(on)) { Text(verbatim: "Milk") }
          .toggleStyle(GatherCheckStyle())
        #expect(renders(view, width: 300, height: 60))
      }
    }
  }
#endif
