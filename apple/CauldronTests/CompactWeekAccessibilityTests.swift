import CauldronKit
import SwiftUI
import Testing

@testable import Cauldron

@MainActor
struct CompactWeekAccessibilityTests {
  @Test func narrowScheduleRendersAtAccessibilitySizesWithMissingAndZeroGoals() throws {
    let start = try #require(LocalDate("2026-10-19"))
    let targets: [TargetsRecord?] = [
      nil, TargetsRecord(calories: 0, protein: 0, carbs: 0, fat: 0),
    ]
    for target in targets {
      let snapshot = WeekSnapshot(start: start, records: [], targets: target)
      for size in [DynamicTypeSize.large, .accessibility3] {
        for scheme in [ColorScheme.light, .dark] {
          let view = WeekDayList(
            snapshot: snapshot, today: start, day: start, onChoose: { _ in }, onAdd: { _ in },
            onOpen: { _ in }, onRemove: { _ in }, onNutrition: { _ in },
            showNutritionAction: true, onPlanRecipe: { _, _, _ in }
          ) {
            VStack {
              WeekHeaderView(
                start: start, isCurrent: false, onPrevious: {}, onNext: {}, onThisWeek: {})
              WeekTallyView(
                snapshot: snapshot, day: nil, onClearDay: {}, onOpenTargets: {}, compact: true)
            }
          } bottom: {
            EmptyView()
          }
          .environment(\.dynamicTypeSize, size)
          .environment(\.colorScheme, scheme)
          for width in [320.0, 390.0] {
            let renderer = ImageRenderer(content: view.frame(width: width, height: 1_200))
            #expect(renderer.cgImage != nil, "\(width)pt \(size) \(scheme)")
          }
        }
      }
    }
  }
}
