import CauldronKit
import SwiftUI

/// The week's running total of calories and macros, and the chosen day's beside it.
struct WeekTallyView: View {
  let snapshot: WeekSnapshot
  /// The day whose tally shows beside the week's.
  let day: LocalDate?
  let onClearDay: () -> Void
  let onOpenTargets: () -> Void
  var compact = false

  var body: some View {
    if compact {
      VStack(alignment: .leading, spacing: 8) {
        // A comparison carries its own not-counted line; the note would say it twice.
        if snapshot.weeklyComparison == nil,
          let note = WeekFigures.note(week: snapshot.weekTally, day: nil)
        {
          Text(verbatim: note)
            .brandText(.control)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(
              snapshot.weekTally.missing + snapshot.weekTally.freeText > 0
                ? Brand.Colors.heat : Brand.Colors.subtext)
        }
        CompactWeekNutritionView(
          comparison: snapshot.weeklyComparison, tally: snapshot.weekTally,
          onOpenTargets: onOpenTargets)
      }
    } else {
      VStack(alignment: .leading, spacing: 10) {
        // The week and the chosen day sit side by side. A side with a comparison shows its
        // rows alone, as the narrow Week does; a side without one keeps its totals.
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 24) {
            weekSide.frame(minWidth: 320, maxWidth: 560, alignment: .topLeading)
            if day != nil {
              daySide.frame(minWidth: 320, maxWidth: 560, alignment: .topLeading)
            }
            Spacer(minLength: 0)
          }
          VStack(alignment: .leading, spacing: 16) {
            weekSide
            if day != nil { daySide }
          }
        }
        if snapshot.weeklyComparison == nil {
          VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: Copy.week.tally.noTargets.text).brandText(.control)
            Button(Copy.week.tally.setTargets.text, action: onOpenTargets)
              .brandText(.control)
              .accessibilityIdentifier("week.setTargets")
          }
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
  }

  @ViewBuilder
  private var weekSide: some View {
    if let comparison = snapshot.weeklyComparison {
      VStack(alignment: .leading, spacing: 8) {
        CompactWeekNutritionView(
          comparison: comparison, tally: snapshot.weekTally, onOpenTargets: onOpenTargets,
          framed: false)
        if let average = WeekFigures.average(
          of: snapshot.weekTally, daysPlanned: snapshot.daysPlanned)
        {
          Text(verbatim: average).brandText(.quantity).foregroundStyle(Brand.Colors.subtext)
        }
      }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        TallyGroup(
          label: Copy.week.tally.week.text, tally: snapshot.weekTally,
          sub: WeekFigures.average(of: snapshot.weekTally, daysPlanned: snapshot.daysPlanned)
        )
        .accessibilityIdentifier("week.tally.week")
        if let note = WeekFigures.note(week: snapshot.weekTally, day: nil) {
          Text(verbatim: note)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
        }
      }
    }
  }

  @ViewBuilder
  private var daySide: some View {
    if let day {
      if let comparison = snapshot.dailyComparison(for: day) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center, spacing: 8) {
            Text(verbatim: WeekDates.label(day, long: true))
              .brandText(.control)
              .foregroundStyle(Brand.Colors.heat)
            Spacer(minLength: 0)
            clearButton
          }
          CompactWeekNutritionView(
            comparison: comparison, tally: snapshot.tally(of: day),
            onOpenTargets: onOpenTargets, heading: nil,
            identifier: "week.dailyComparison", framed: false, showsIncomplete: false)
        }
      } else {
        HStack(alignment: .top, spacing: 8) {
          TallyGroup(
            label: WeekDates.label(day, long: true), tally: snapshot.tally(of: day), sub: nil,
            emphasised: true)
          clearButton
        }
      }
    }
  }

  private var clearButton: some View {
    WeekIconButton(systemImage: "xmark", label: Copy.week.tally.clearDay.text, action: onClearDay)
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
