import CauldronKit
import SwiftUI

/// The week's running total of calories and macros, and the chosen day's beside it.
struct WeekTallyView: View {
  let snapshot: WeekSnapshot
  /// The day whose tally shows beside the week's.
  let day: LocalDate?
  let onClearDay: () -> Void
  let onOpenTargets: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 16) { groups }
        VStack(alignment: .leading, spacing: 12) { groups }
      }
      if let note = WeekFigures.note(week: snapshot.weekTally, day: day.map(snapshot.tally)) {
        Text(verbatim: note)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
      }
      if let comparison = snapshot.weeklyComparison {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: Copy.week.tally.plannedAgainstTarget.text).brandText(.control)
          Text(verbatim: Copy.week.tally.eatenClarification.text).brandText(.control)
          ForEach([MacroKey.calories, .protein, .carbs, .fat], id: \.self) { key in
            Text(verbatim: WeekFigures.comparisonRow(comparison, key: key))
              .brandText(.quantity)
          }
          if comparison.isIncomplete {
            Text(verbatim: Copy.week.tally.incomplete.text).brandText(.control)
              .foregroundStyle(Brand.Colors.heat)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("week.weeklyComparison")
      } else {
        VStack(alignment: .leading, spacing: 6) {
          Text(verbatim: Copy.week.tally.noTargets.text).brandText(.control)
          Button(Copy.week.tally.setTargets.text, action: onOpenTargets)
            .brandText(.control)
            .accessibilityIdentifier("week.setTargets")
        }
      }
      if let day, let comparison = snapshot.dailyComparison(for: day) {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: Copy.week.tally.dailyPlannedAgainstTarget.text).brandText(.control)
          Text(verbatim: Copy.week.tally.eatenClarification.text).brandText(.control)
          ForEach([MacroKey.calories, .protein, .carbs, .fat], id: \.self) { key in
            Text(verbatim: WeekFigures.comparisonRow(comparison, key: key)).brandText(.quantity)
          }
          if comparison.isIncomplete {
            Text(verbatim: Copy.week.tally.incomplete.text).brandText(.control)
              .foregroundStyle(Brand.Colors.heat)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("week.dailyComparison")
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.Colors.surface0, lineWidth: 1))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(verbatim: Copy.week.tally.label.text))
  }

  @ViewBuilder
  private var groups: some View {
    TallyGroup(
      label: Copy.week.tally.week.text, tally: snapshot.weekTally,
      sub: WeekFigures.average(of: snapshot.weekTally, daysPlanned: snapshot.daysPlanned)
    )
    .accessibilityIdentifier("week.tally.week")
    if let day {
      HStack(alignment: .top, spacing: 8) {
        TallyGroup(
          label: WeekDates.label(day, long: true), tally: snapshot.tally(of: day), sub: nil,
          emphasised: true)
        WeekIconButton(
          systemImage: "xmark", label: Copy.week.tally.clearDay.text, action: onClearDay)
      }
    }
  }
}

private struct TallyGroup: View {
  let label: String
  let tally: MacroTally
  let sub: String?
  var emphasised = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: label)
        .brandText(.control)
        .foregroundStyle(emphasised ? Brand.Colors.heat : Brand.Colors.subtext)
      FlowLayout(spacing: 12) {
        QuantityText(
          WeekFigures.whole(tally.totals.calories), unit: Copy.week.tally.macros.calories.text)
        ForEach(WeekFigures.gramKeys, id: \.self) { key in
          HStack(spacing: 5) {
            Circle().fill(color(key)).frame(width: 8, height: 8).accessibilityHidden(true)
            QuantityText(
              "\(WeekFigures.whole(tally.totals[key])) g", unit: name(key))
          }
        }
      }
      let split = WeekFigures.split(tally.totals)
      if !split.isEmpty {
        GeometryReader { proxy in
          HStack(spacing: 0) {
            ForEach(split, id: \.key) { part in
              Rectangle().fill(color(part.key)).frame(width: proxy.size.width * part.share)
            }
          }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
      }
      if let sub {
        Text(verbatim: sub).brandText(.quantity).foregroundStyle(Brand.Colors.subtext)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func color(_ key: MacroKey) -> Color {
    switch key {
    case .protein: Brand.Colors.trackerBlue
    case .carbs: Brand.Colors.trackerTeal
    case .fat: Brand.Colors.trackerRed
    case .calories: Brand.Colors.magic
    }
  }

  private func name(_ key: MacroKey) -> String {
    switch key {
    case .protein: Copy.week.tally.macros.protein.text
    case .carbs: Copy.week.tally.macros.carbs.text
    case .fat: Copy.week.tally.macros.fat.text
    case .calories: Copy.week.tally.macros.calories.text
    }
  }
}
