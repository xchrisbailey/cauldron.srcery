import CauldronKit
import SwiftData
import SwiftUI

/// The add sheet's "Recent" way in (#180): favourites first, then what was logged lately, most
/// often first. One tap logs it again as it was last logged; the star keeps it as a favourite.
struct AddRecentsTab: View {
  nonisolated static let isAvailable = true

  let context: AddContext

  @Query private var entries: [DiaryEntryRecord]
  @Query private var favourites: [FavouriteRecord]
  @Environment(\.modelContext) private var modelContext
  @State private var failure: CopyString?

  init(context: AddContext) {
    self.context = context
    let from = (TargetsForm.today() ?? context.day).adding(days: -QuickFoodList.recentDays)
      .description
    _entries = Query(filter: #Predicate<DiaryEntryRecord> { $0.dayKey >= from })
  }

  var body: some View {
    let foods = QuickFoodList.foods(
      favourites: favourites, entries: entries, today: TargetsForm.today() ?? context.day)
    List {
      if let failure {
        Section {
          Text(verbatim: failure.text)
            .brandText(.body)
            .foregroundStyle(Brand.Colors.heat)
            .listRowBackground(Brand.Colors.mantle)
        }
      }
      if foods.favourites.isEmpty && foods.recents.isEmpty {
        Section {
          Text(verbatim: Copy.tracker.quick.empty.text)
            .brandText(.body)
            .foregroundStyle(Brand.Colors.subtext)
        }
        .listRowBackground(Color.clear)
      }
      if !foods.favourites.isEmpty {
        Section {
          ForEach(foods.favourites, id: \.id) { favourite in
            row(favourite.food, count: nil, starred: true) {
              toggle(key: quickFoodKey(favourite.food), entry: nil)
            }
          }
        } header: {
          Text(verbatim: Copy.tracker.quick.favourites.text)
        }
      }
      if !foods.recents.isEmpty {
        Section {
          ForEach(foods.recents, id: \.lastEntryId) { recent in
            row(recent.food, count: recent.count, starred: false) {
              toggle(
                key: quickFoodKey(recent.food),
                entry: entries.first { $0.id == recent.lastEntryId })
            }
          }
        } header: {
          Text(verbatim: Copy.tracker.quick.recents.text)
        }
      }
    }
    .scrollContentBackground(.hidden)
  }

  private func row(
    _ food: QuickFood, count: Int?, starred: Bool, onStar: @escaping () -> Void
  ) -> some View {
    let totals = entryTotals(food)
    let detail = [
      food.amount, food.servings == 1 ? nil : "× \(showNumber(food.servings, digits: 2))",
    ].compactMap { $0 }.joined(separator: " ")
    return HStack(spacing: 8) {
      Button {
        failure = context.log([QuickFoodList.entry(for: food, in: modelContext)])
      } label: {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: food.name).brandText(.body).lineLimit(1)
            if !detail.isEmpty {
              Text(verbatim: detail).brandText(.quantity).foregroundStyle(Brand.Colors.subtext)
            }
          }
          Spacer(minLength: 8)
          VStack(alignment: .trailing, spacing: 2) {
            Text(
              verbatim: Copy.display.calories(
                MacroMeter.whole(totals.calories), unit: Copy.tracker.macros.calories.text
              ).text
            )
            .brandText(.quantity)
            if let count, count > 1 {
              Text(verbatim: Copy.tracker.quick.times(count).text)
                .brandText(.unit)
            }
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Copy.tracker.quick.logAgain(food.name).text)
      Button(action: onStar) {
        Image(systemName: starred ? "star.fill" : "star")
          .foregroundStyle(starred ? Brand.Colors.tips : Brand.Colors.overlay1)
          .frame(width: 36, height: 36)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(
        (starred ? Copy.tracker.quick.unstar(food.name) : Copy.tracker.quick.star(food.name)).text
      )
      .accessibilityAddTraits(starred ? .isSelected : [])
    }
    .listRowBackground(Brand.Colors.mantle)
  }

  /// Stars a food from the entry it was last logged as, or takes a favourite off.
  private func toggle(key: String, entry: DiaryEntryRecord?) {
    do {
      if let entry {
        try FavouriteWrites.star(entry, in: modelContext)
      } else {
        try FavouriteWrites.unstar(key: key, in: modelContext)
      }
      failure = nil
    } catch {
      failure = Copy.tracker.diary.couldntSave
    }
  }
}
