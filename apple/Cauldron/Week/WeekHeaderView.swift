import CauldronKit
import SwiftUI

/// The week's range with the way to the weeks either side, and back to this one.
struct WeekHeaderView: View {
  let start: LocalDate
  let isCurrent: Bool
  let onPrevious: () -> Void
  let onNext: () -> Void
  let onThisWeek: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    #if os(iOS)
      ViewThatFits(in: .horizontal) {
        row(adaptive: true)
        VStack(alignment: .leading, spacing: 4) {
          range.fixedSize(horizontal: false, vertical: true)
          HStack {
            previous
            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize { thisWeek }
            Spacer(minLength: 8)
            next
          }
          if dynamicTypeSize.isAccessibilitySize { thisWeek }
        }
      }
    #else
      row(adaptive: false)
    #endif
  }

  private func row(adaptive: Bool) -> some View {
    HStack(spacing: 4) {
      previous
      range
        .lineLimit(1)
        .minimumScaleFactor(adaptive ? 1 : 0.8)
        .fixedSize(horizontal: adaptive, vertical: true)
      next
      Spacer(minLength: 8)
      thisWeek
    }
  }

  private var range: some View {
    Text(verbatim: WeekDates.rangeLabel(start: start)).brandText(.section)
  }

  private var previous: some View {
    WeekIconButton(
      systemImage: "chevron.left", label: Copy.week.previousWeek.text, action: onPrevious)
  }

  private var next: some View {
    WeekIconButton(
      systemImage: "chevron.right", label: Copy.week.nextWeek.text, action: onNext)
  }

  @ViewBuilder
  private var thisWeek: some View {
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
