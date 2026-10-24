import CauldronKit
import SwiftUI

/// The narrow Week summary: one weekly comparison, without the expanded daily explanation.
struct CompactWeekNutritionView: View {
  let comparison: WeekMacroComparison?
  let tally: MacroTally
  let onOpenTargets: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: Copy.week.tally.compactHeading.text)
        .brandText(.control)
        .foregroundStyle(Brand.Colors.subtext)
      if let comparison {
        VStack(alignment: .leading, spacing: 8) {
          metric(.calories, comparison: comparison, prominent: true)
          if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(WeekFigures.gramKeys, id: \.self) { key in
                metric(key, comparison: comparison, prominent: false)
              }
            }
          } else {
            HStack(alignment: .top, spacing: 12) {
              ForEach(WeekFigures.gramKeys, id: \.self) { key in
                metric(key, comparison: comparison, prominent: false)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 8) {
          VStack(alignment: .leading, spacing: 5) {
            total(.calories, prominent: true)
            HStack(spacing: 12) {
              ForEach(WeekFigures.gramKeys, id: \.self) { key in
                total(key, prominent: false)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
          Text(verbatim: Copy.week.tally.noTargets.text).brandText(.control)
          Button(Copy.week.tally.setTargets.text, action: onOpenTargets)
            .brandText(.control)
            .accessibilityIdentifier("week.setTargets")
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.Colors.surface0, lineWidth: 1))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("week.weeklyComparison")
  }

  private func metric(
    _ key: MacroKey, comparison: WeekMacroComparison, prominent: Bool
  ) -> some View {
    let planned = comparison.planned[key]
    let goal = comparison.target[key]
    let unit = key == .calories ? Copy.week.tally.macros.calories.text : Copy.week.tally.grams.text
    let amount = Copy.week.tally.compactPair(
      planned: WeekFigures.compactAmount(planned), goal: WeekFigures.compactAmount(goal),
      unit: unit
    ).text
    let overGoal = WeekFigures.isOverGoal(comparison, key: key)
    return VStack(alignment: .leading, spacing: 3) {
      Text(verbatim: WeekFigures.metricName(key))
        .brandText(prominent ? .section : .control)
        .foregroundStyle(Brand.Colors.subtext)
      Text(verbatim: amount)
        .brandText(.quantity)
        .fixedSize(horizontal: false, vertical: true)
      if let progress = comparison.progress(for: key) {
        GeometryReader { proxy in
          Capsule()
            .fill(Brand.Colors.surface0)
            .overlay(alignment: .leading) {
              Capsule()
                .fill(overGoal ? Brand.Colors.heat : color(key))
                .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(
        verbatim: Copy.week.tally.compactMetric(
          name: WeekFigures.metricName(key), planned: WeekFigures.compactAmount(planned),
          goal: WeekFigures.compactAmount(goal), unit: unit, isOver: overGoal
        ).text)
    )
    .accessibilityIdentifier("week.weeklyMetric.\(key)")
  }

  private func color(_ key: MacroKey) -> Color {
    switch key {
    case .calories: Brand.Colors.magic
    case .protein: Brand.Colors.trackerBlue
    case .carbs: Brand.Colors.trackerTeal
    case .fat: Brand.Colors.trackerRed
    }
  }

  private func total(_ key: MacroKey, prominent: Bool) -> some View {
    let unit = key == .calories ? Copy.week.tally.macros.calories.text : Copy.week.tally.grams.text
    return Text(
      verbatim: Copy.week.tally.knownTotal(
        name: WeekFigures.metricName(key), planned: WeekFigures.compactAmount(tally.totals[key]),
        unit: unit
      ).text
    )
    .brandText(.quantity)
    .fixedSize(horizontal: false, vertical: true)
  }
}
