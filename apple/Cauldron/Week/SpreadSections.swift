import CauldronKit
import SwiftUI

/// Choosing the days a recipe's servings feed, and how many go to each: the days with their
/// servings, the shortcuts, the tally of what is planned, and the Stir button. Both stir sheets
/// show it inside their own `List` or `Form`, above which they put what differs (the meal
/// picker, the starting day).
struct SpreadSections: View {
  @Binding var plan: SpreadPlan
  let today: LocalDate
  /// What went wrong the last time the cook pressed Stir.
  let problem: String?
  let onStir: () -> Void

  var body: some View {
    Section {
      HStack {
        Button {
          plan.spreadOneADay()
        } label: {
          Text(verbatim: Copy.week.spread.oneADay.text)
        }
        Button {
          plan.putAllOnAnchor()
        } label: {
          Text(verbatim: Copy.week.spread.allOn(WeekDates.label(plan.anchor, long: false)).text)
        }
      }
      .buttonStyle(.borderless)
      ForEach(plan.days, id: \.self) { day in dayRow(day) }
    } header: {
      Text(verbatim: Copy.week.spread.days.text)
    } footer: {
      Text(verbatim: Copy.week.spread.hint.text)
    }
    Section {
      Text(verbatim: plan.summary)
        .brandText(.quantity)
        .foregroundStyle(plan.isOver ? Brand.Colors.heat : Brand.Colors.subtext)
      if let problem {
        Text(verbatim: problem).foregroundStyle(Brand.Colors.heat)
      }
      Button(action: onStir) {
        Text(verbatim: Copy.week.spread.stir(plan.picked.count).text)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.brandProminent)
      .disabled(!plan.canStir)
    }
  }

  private func dayRow(_ day: LocalDate) -> some View {
    let servings = plan.servings(on: day)
    let label = WeekDates.label(day, long: true)
    return HStack {
      Button {
        plan.toggle(day)
      } label: {
        HStack(spacing: 10) {
          Image(systemName: servings == nil ? "circle" : "checkmark.circle.fill")
            .foregroundStyle(servings == nil ? Brand.Colors.overlay1 : Brand.Colors.magic)
          Text(verbatim: label)
            .brandText(.body)
            .foregroundStyle(day == today ? Brand.Colors.heat : Brand.Colors.ink)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(servings == nil ? [] : .isSelected)
      Spacer(minLength: 8)
      if let servings {
        HStack(spacing: 4) {
          WeekIconButton(
            systemImage: "minus", label: Copy.week.spread.fewer(label).text
          ) { plan.step(day, by: -1) }
          Text(verbatim: Copy.week.spread.servingsOn(servings).text)
            .brandText(.quantity)
            .frame(minWidth: 72)
            .accessibilityLabel(Text(verbatim: Copy.week.spread.servingsOn(servings).text))
          WeekIconButton(
            systemImage: "plus", label: Copy.week.spread.more(label).text
          ) { plan.step(day, by: 1) }
          .disabled(servings >= WeekLimits.servings)
        }
      }
    }
    .opacity(day < today ? 0.65 : 1)
  }
}
