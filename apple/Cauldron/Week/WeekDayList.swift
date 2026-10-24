import CauldronKit
import SwiftUI

/// One day of the week at a time, for a narrow window: tabs for the days and the day's meals
/// beneath. Swipe a meal to change or remove it.
struct WeekDayList<Top: View, Bottom: View>: View {
  let snapshot: WeekSnapshot
  let today: LocalDate
  /// The day whose meals and on-demand nutrition are shown.
  let day: LocalDate
  let onChoose: (LocalDate) -> Void
  let onAdd: (MealTarget) -> Void
  let onOpen: (UUID) -> Void
  let onRemove: (UUID) -> Void
  let onNutrition: (LocalDate) -> Void
  let showNutritionAction: Bool
  /// A recipe dropped on a meal's heading. It opens the days step. A day's tab takes no drop, as
  /// on the web.
  let onPlanRecipe: (UUID, MealTarget, UUID?) -> Void
  @ViewBuilder let top: () -> Top
  @ViewBuilder let bottom: () -> Bottom

  var body: some View {
    List {
      Section {
        top()
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        dayTabs
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        if showNutritionAction {
          selectedDayHeader
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
      }
      ForEach(MealSlot.allCases, id: \.self) { slot in
        let target = MealTarget(day: day, slot: slot)
        Section {
          HStack {
            Text(verbatim: Copy.week.slots[slot].text)
              .brandText(.section)
              .foregroundStyle(Brand.Colors.ink)
            Spacer()
            WeekIconButton(
              systemImage: "plus",
              label: Copy.week.stirInto(
                WeekDates.label(day, long: true), Copy.week.slots[slot].text
              ).text
            ) { onAdd(target) }
          }
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 8))
          .accessibilityAddTraits(.isHeader)
          .dropDestination(for: RecipeDrag.self) { items, _ in
            guard let item = items.first else { return false }
            onPlanRecipe(item.id, target, nil)
            return true
          }
          ForEach(snapshot.meals(on: day, slot: slot), id: \.id) { meal in
            MealCardView(
              meal: meal, isToday: day == today, isPast: day < today,
              onOpen: { onOpen(meal.id) }, onRemove: { onRemove(meal.id) }
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) {
                onRemove(meal.id)
              } label: {
                Text(verbatim: Copy.week.remove.text)
              }
            }
            .swipeActions(edge: .leading) {
              Button {
                onOpen(meal.id)
              } label: {
                Text(verbatim: Copy.week.edit(MealCard(meal).title).text)
              }
              .tint(Brand.Colors.magic)
            }
          }
        }
      }
      Section {
        bottom()
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    #if os(iOS)
      .listSectionSpacing(.compact)
    #endif
  }

  private var dayTabs: some View {
    Group {
      if showNutritionAction {
        // Keep day labels and touch targets readable instead of squeezing seven cells to fit.
        ViewThatFits(in: .horizontal) {
          tabRow(adaptive: true)
          ScrollViewReader { scroll in
            ScrollView(.horizontal) {
              tabRow(adaptive: true)
            }
            .scrollIndicators(.hidden)
            .onChange(of: day, initial: true) {
              scroll.scrollTo(day, anchor: .center)
            }
          }
        }
      } else {
        tabRow(adaptive: false)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(verbatim: Copy.week.days.text))
  }

  private var selectedDayHeader: some View {
    ViewThatFits(in: .horizontal) {
      HStack {
        selectedDayLabel.fixedSize()
        Spacer(minLength: 8)
        nutritionButton.fixedSize()
      }
      VStack(alignment: .leading, spacing: 4) {
        selectedDayLabel.fixedSize(horizontal: false, vertical: true)
        nutritionButton
      }
    }
  }

  private var selectedDayLabel: some View {
    Text(verbatim: WeekDates.label(day, long: true))
      .brandText(.quantity)
      .accessibilityAddTraits(.isHeader)
  }

  private var nutritionButton: some View {
    Button(Copy.week.tally.nutritionAction.text) { onNutrition(day) }
      .brandText(.control)
      .frame(minHeight: 44)
      .accessibilityIdentifier("week.openDailyNutrition")
  }

  private func tabRow(adaptive: Bool) -> some View {
    HStack(spacing: 4) {
      ForEach(snapshot.days, id: \.self) { tabDay in
        let isToday = tabDay == today
        let isShown = tabDay == day
        let calories = snapshot.tally(of: tabDay).totals.calories
        Button {
          onChoose(tabDay)
        } label: {
          VStack(spacing: 2) {
            Text(verbatim: WeekDates.weekday(tabDay, long: false))
              .brandText(.control)
              .lineLimit(1)
              .minimumScaleFactor(adaptive ? 1 : 0.7)
              .fixedSize(horizontal: adaptive, vertical: true)
            Text(verbatim: WeekDates.dayOfMonth(tabDay)).brandText(.quantity)
            Text(
              verbatim: Copy.display.weekCellCalories(
                WeekFigures.whole(calories), show: calories > 0
              ).text
            )
            .brandText(.quantity)
            .lineLimit(1)
            .minimumScaleFactor(adaptive ? 1 : 0.6)
            .fixedSize(horizontal: adaptive, vertical: true)
            .opacity(0.8)
            .accessibilityHidden(true)
          }
          .foregroundStyle(
            isShown ? Brand.Colors.base : (isToday ? Brand.Colors.heat : Brand.Colors.ink)
          )
          .frame(minWidth: adaptive ? 44 : 0, maxWidth: .infinity)
          .padding(.vertical, 6)
          .background(
            isShown ? Brand.Colors.magic : Brand.Colors.surface0.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 10)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(isToday ? Brand.Colors.heat : Color.clear, lineWidth: 1)
          )
          .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: WeekDates.label(tabDay, long: true)))
        .accessibilityIdentifier("week.day.\(tabDay.description)")
        .accessibilityAddTraits(isShown ? .isSelected : [])
        .id(tabDay)
      }
    }
  }
}
