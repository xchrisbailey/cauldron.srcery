import CauldronKit
import SwiftUI

struct WeekNutritionSheet: View {
  let snapshot: WeekSnapshot
  let day: LocalDate
  let onOpenTargets: () -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Text(verbatim: WeekDates.label(day, long: true))
            .brandText(.section)
            .accessibilityAddTraits(.isHeader)
          if let comparison = snapshot.dailyComparison(for: day) {
            VStack(alignment: .leading, spacing: 8) {
              Text(verbatim: Copy.week.tally.dailyPlannedAgainstTarget.text)
                .brandText(.section)
              Text(verbatim: Copy.week.tally.eatenClarification.text)
                .brandText(.control)
                .foregroundStyle(Brand.Colors.subtext)
              ForEach([MacroKey.calories, .protein, .carbs, .fat], id: \.self) { key in
                Text(verbatim: WeekFigures.comparisonRow(comparison, key: key))
                  .brandText(.quantity)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              if comparison.isIncomplete {
                Text(verbatim: Copy.week.tally.incomplete.text)
                  .brandText(.control)
                  .foregroundStyle(Brand.Colors.heat)
              }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("week.dailyComparison")
          } else {
            VStack(alignment: .leading, spacing: 8) {
              Text(verbatim: Copy.week.tally.noDailyTargets.text).brandText(.body)
              ForEach([MacroKey.calories, .protein, .carbs, .fat], id: \.self) { key in
                Text(verbatim: totalLine(key, tally: snapshot.tally(of: day)))
                  .brandText(.quantity)
              }
              Button(Copy.week.tally.setTargets.text, action: onOpenTargets)
                .brandText(.control)
                .frame(minHeight: 44)
                .accessibilityIdentifier("week.dailySetTargets")
            }
          }
          if let note = WeekFigures.note(week: snapshot.tally(of: day), day: nil) {
            Text(verbatim: note)
              .brandText(.control)
              .foregroundStyle(Brand.Colors.heat)
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityIdentifier("week.dailyNutritionContent")
      .background(Brand.Colors.base)
      .navigationTitle(Copy.week.tally.dailyNutritionTitle.text)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(Copy.ui.close.text) { dismiss() }
        }
      }
    }
  }

  @Environment(\.dismiss) private var dismiss

  private func totalLine(_ key: MacroKey, tally: MacroTally) -> String {
    let unit = key == .calories ? Copy.week.tally.macros.calories.text : Copy.week.tally.grams.text
    return Copy.week.tally.knownTotal(
      name: WeekFigures.metricName(key), planned: WeekFigures.compactAmount(tally.totals[key]),
      unit: unit
    ).text
  }
}
