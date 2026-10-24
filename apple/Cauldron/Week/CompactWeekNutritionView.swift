import CauldronKit
import SwiftUI

/// The narrow Week summary: one weekly comparison, without the expanded daily explanation.
struct CompactWeekNutritionView: View {
  let comparison: WeekMacroComparison?
  let tally: MacroTally
  let onOpenTargets: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .title3) private var caloriePairSize = 24

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: Copy.week.tally.compactHeading.text)
        .brandText(.control)
        .foregroundStyle(Brand.Colors.subtext)
      if let comparison {
        VStack(alignment: .leading, spacing: 8) {
          metric(.calories, comparison: comparison, prominent: true)
          VStack(alignment: .leading, spacing: 8) {
            ForEach(WeekFigures.gramKeys, id: \.self) { key in
              metric(key, comparison: comparison, prominent: false)
            }
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 8) {
          total(.calories, prominent: true)
          VStack(alignment: .leading, spacing: 8) {
            ForEach(WeekFigures.gramKeys, id: \.self) { key in
              total(key, prominent: false)
            }
          }
          Text(verbatim: Copy.week.tally.noTargets.text).brandText(.control)
          Button(Copy.week.tally.setTargets.text, action: onOpenTargets)
            .brandText(.control)
            .frame(minHeight: 44)
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
    return VStack(alignment: .leading, spacing: 4) {
      if prominent {
        Text(verbatim: WeekFigures.metricName(key))
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
        calorieValue(amount, isOver: overGoal)
      } else {
        let label = WeekFigures.metricName(key)
        if dynamicTypeSize.isAccessibilitySize {
          macroRow(label: label, value: amount, isOver: overGoal, stacked: true)
        } else {
          ViewThatFits(in: .horizontal) {
            macroRow(label: label, value: amount, isOver: overGoal, stacked: false)
            macroRow(label: label, value: amount, isOver: overGoal, stacked: true)
          }
        }
      }
      if let progress = comparison.progress(for: key) {
        GeometryReader { proxy in
          Capsule()
            .fill(Brand.Colors.surface0)
            .overlay(alignment: .leading) {
              Capsule()
                .fill(overGoal ? Brand.Colors.heat : Brand.Colors.magic)
                .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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

  private func total(_ key: MacroKey, prominent: Bool) -> some View {
    let unit = key == .calories ? Copy.week.tally.macros.calories.text : Copy.week.tally.grams.text
    let value = Copy.week.tally.compactValue(
      WeekFigures.compactAmount(tally.totals[key]), unit: unit
    ).text
    let label = WeekFigures.metricName(key)
    return Group {
      if prominent {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: label).brandText(.control).foregroundStyle(Brand.Colors.subtext)
          Text(verbatim: value).font(.brand(.quantity, size: caloriePairSize))
        }
      } else if dynamicTypeSize.isAccessibilitySize {
        macroRow(label: label, value: value, isOver: false, stacked: true)
      } else {
        ViewThatFits(in: .horizontal) {
          macroRow(label: label, value: value, isOver: false, stacked: false)
          macroRow(label: label, value: value, isOver: false, stacked: true)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(
        verbatim: Copy.week.tally.knownTotal(
          name: label, planned: WeekFigures.compactAmount(tally.totals[key]), unit: unit
        ).text)
    )
  }

  @ViewBuilder
  private func calorieValue(_ value: String, isOver: Bool) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: value).font(.brand(.quantity, size: caloriePairSize))
        overGoalMarker(isOver)
      }
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(verbatim: value).font(.brand(.quantity, size: caloriePairSize))
        Spacer(minLength: 0)
        overGoalMarker(isOver)
      }
    }
  }

  @ViewBuilder
  private func macroRow(label: String, value: String, isOver: Bool, stacked: Bool) -> some View {
    if stacked {
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: label).brandText(.control).foregroundStyle(Brand.Colors.subtext)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(verbatim: value).brandText(.quantity)
          Spacer(minLength: 0)
          overGoalMarker(isOver)
        }
      }
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(verbatim: label).brandText(.control).foregroundStyle(Brand.Colors.subtext)
        Spacer(minLength: 8)
        Text(verbatim: value).brandText(.quantity).fixedSize()
        overGoalMarker(isOver)
      }
    }
  }

  @ViewBuilder
  private func overGoalMarker(_ isOver: Bool) -> some View {
    if isOver {
      Text(verbatim: Copy.week.tally.overGoal.text)
        .brandText(.control)
        .foregroundStyle(Brand.Colors.heat)
        .fixedSize()
    }
  }
}
