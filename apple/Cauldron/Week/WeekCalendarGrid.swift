import CauldronKit
import SwiftUI

/// The week as seven columns of four meals, for a window with room: drag a meal to another
/// meal or day to move it, or press + on a meal to stir one in.
struct WeekCalendarGrid: View {
  let snapshot: WeekSnapshot
  let today: LocalDate
  @Binding var chosenDay: LocalDate?
  let onAdd: (MealTarget) -> Void
  let onOpen: (UUID) -> Void
  let onRemove: (UUID) -> Void
  /// A meal dropped on a meal, before another meal when it landed on one.
  let onDrop: (UUID, MealTarget, UUID?) -> Void

  var body: some View {
    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
      GridRow {
        Color.clear.frame(width: 84, height: 1)
        ForEach(snapshot.days, id: \.self) { day in dayHead(day) }
      }
      ForEach(MealSlot.allCases, id: \.self) { slot in
        GridRow(alignment: .top) {
          Text(verbatim: Copy.week.slots[slot].text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
            .frame(width: 84, alignment: .leading)
            .padding(.top, 8)
          ForEach(snapshot.days, id: \.self) { day in cell(MealTarget(day: day, slot: slot)) }
        }
      }
    }
  }

  private func dayHead(_ day: LocalDate) -> some View {
    let isToday = day == today
    let chosen = chosenDay == day
    let calories = snapshot.tally(of: day).totals.calories
    return Button {
      chosenDay = chosen ? nil : day
    } label: {
      VStack(spacing: 2) {
        Text(verbatim: WeekDates.weekday(day, long: false))
          .brandText(.control)
          .foregroundStyle(isToday ? Brand.Colors.heat : Brand.Colors.subtext)
        Text(verbatim: WeekDates.dayOfMonth(day))
          .brandText(.quantity)
          .foregroundStyle(isToday ? Brand.Colors.heat : Brand.Colors.ink)
        Text(verbatim: calories > 0 ? "\(WeekFigures.whole(calories)) kcal" : " ")
          .brandText(.quantity)
          .foregroundStyle(Brand.Colors.subtext)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
      .background(
        chosen ? Brand.Colors.magic.opacity(0.18) : Color.clear,
        in: RoundedRectangle(cornerRadius: 10)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(isToday ? Brand.Colors.heat.opacity(0.6) : Color.clear, lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 10))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      Text(verbatim: Copy.week.tally.showDay(WeekDates.label(day, long: true)).text)
    )
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }

  private func cell(_ target: MealTarget) -> some View {
    let meals = snapshot.meals(on: target.day, slot: target.slot)
    return VStack(alignment: .leading, spacing: 4) {
      ForEach(meals, id: \.id) { meal in
        MealCardView(
          meal: meal, isToday: target.day == today, isPast: target.day < today,
          onOpen: { onOpen(meal.id) }, onRemove: { onRemove(meal.id) }
        )
        .dropDestination(for: MealDrag.self) { items, _ in
          guard let item = items.first else { return false }
          onDrop(item.id, target, meal.id)
          return true
        }
      }
      WeekIconButton(
        systemImage: "plus",
        label: Copy.week.stirInto(
          WeekDates.label(target.day, long: true), Copy.week.slots[target.slot].text
        ).text
      ) { onAdd(target) }
      .frame(maxWidth: .infinity)
      .opacity(target.day < today ? 0.6 : 1)
    }
    .padding(4)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .frame(minHeight: 56, alignment: .top)
    .background(Brand.Colors.surface0.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    .dropDestination(for: MealDrag.self) { items, _ in
      guard let item = items.first else { return false }
      onDrop(item.id, target, nil)
      return true
    }
  }
}
