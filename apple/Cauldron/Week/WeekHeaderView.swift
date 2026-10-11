import CauldronKit
import SwiftUI

/// The week's range with the way to the weeks either side, and back to this one.
struct WeekHeaderView: View {
  let start: LocalDate
  let isCurrent: Bool
  let onPrevious: () -> Void
  let onNext: () -> Void
  let onThisWeek: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      WeekIconButton(
        systemImage: "chevron.left", label: Copy.week.previousWeek.text, action: onPrevious)
      Text(verbatim: WeekDates.rangeLabel(start: start))
        .brandText(.section)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      WeekIconButton(
        systemImage: "chevron.right", label: Copy.week.nextWeek.text, action: onNext)
      Spacer(minLength: 8)
      if !isCurrent {
        Button(action: onThisWeek) {
          Text(verbatim: Copy.week.thisWeek.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.magic)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// "Week starts on", kept with the cook's other preferences.
struct WeekStartPicker: View {
  let startsOn: WeekStartDay
  let onChange: @MainActor (WeekStartDay) -> Void

  var body: some View {
    Picker(
      selection: Binding(get: { startsOn }, set: onChange)
    ) {
      Text(verbatim: Copy.week.monday.text).tag(WeekStartDay.monday)
      Text(verbatim: Copy.week.sunday.text).tag(WeekStartDay.sunday)
    } label: {
      Text(verbatim: Copy.week.weekStarts.text).brandText(.control)
    }
    .pickerStyle(.menu)
    .fixedSize()
  }
}
