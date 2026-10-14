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

/// "Week starts on", any of the seven days, kept with the cook's other preferences. The Week
/// page and Settings both show it.
struct WeekStartPicker: View {
  let startsOn: WeekStartDay
  let onChange: @MainActor (WeekStartDay) -> Void

  /// The days in the order the picker lists them: the working week first, then the weekend.
  static let order: [WeekStartDay] = [
    .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
  ]

  var body: some View {
    Picker(
      selection: Binding(get: { startsOn }, set: onChange)
    ) {
      ForEach(Self.order, id: \.self) { day in
        Text(verbatim: Copy.week.dayName(day).text).tag(day)
      }
    } label: {
      Text(verbatim: Copy.week.weekStarts.text).brandText(.control)
    }
    .pickerStyle(.menu)
  }
}
