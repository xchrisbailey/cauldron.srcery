import CauldronKit
import SwiftData
import SwiftUI

/// Changing a logged entry: servings, name, amount, numbers or meal, or removing it. The numbers
/// are the entry's own snapshot, so changing them leaves the recipe it came from alone.
struct DiaryEntrySheet: View {
  let record: DiaryEntryRecord
  let onClose: () -> Void
  /// Called with what the entry was when it is removed, so the diary can offer to undo it.
  let onRemoved: (DiaryWrites.Removed) -> Void
  /// Called with the message to show when a change could not be saved.
  let onFailure: (CopyString) -> Void

  @Environment(\.modelContext) private var context
  @State private var draft: EntryDraft
  @State private var attempted = false
  @Query private var favourites: [FavouriteRecord]

  private let entry = Copy.tracker.entry

  init(
    record: DiaryEntryRecord, onClose: @escaping () -> Void,
    onRemoved: @escaping (DiaryWrites.Removed) -> Void = { _ in },
    onFailure: @escaping (CopyString) -> Void
  ) {
    self.record = record
    self.onClose = onClose
    self.onRemoved = onRemoved
    self.onFailure = onFailure
    _draft = State(initialValue: EntryDraft(record))
  }

  var body: some View {
    NavigationStack {
      Form {
        servingsSection
        DiaryEntryFields(
          draft: $draft, errors: attempted ? draft.errors(requireCalories: false) : [:])
        Section {
          Picker(selection: $draft.slot) {
            ForEach(MealSlot.allCases, id: \.self) { slot in
              Text(verbatim: Copy.week.slots[slot].text).tag(slot)
            }
          } label: {
            Text(verbatim: entry.meal.text)
          }
          .brandText(.body)
          .listRowBackground(Brand.Colors.mantle)
          DatePicker(
            selection: day, in: dayRange, displayedComponents: .date
          ) {
            Text(verbatim: entry.day.text)
          }
          .brandText(.quantity)
          .listRowBackground(Brand.Colors.mantle)
        }
        if !record.macrosPending {
          Section {
            Button(action: toggleFavourite) {
              Label {
                Text(
                  verbatim: (starred
                    ? Copy.tracker.quick.unfavourite : Copy.tracker.quick.favourite).text
                )
                .brandText(.body)
              } icon: {
                Image(systemName: starred ? "star.fill" : "star")
                  .foregroundStyle(starred ? Brand.Colors.tips : Brand.Colors.overlay1)
              }
            }
            .listRowBackground(Brand.Colors.mantle)
          }
        }
        Section {
          Button(role: .destructive, action: remove) {
            Text(verbatim: entry.remove.text).brandText(.body)
          }
          .listRowBackground(Brand.Colors.mantle)
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
      .navigationTitle(record.name)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(entry.cancel.text, action: onClose)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(entry.save.text, action: save)
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 600)
    #endif
  }

  private var servingsSection: some View {
    Section {
      HStack {
        Button {
          draft.nudgeServings(by: -EntryDraft.servingStep)
        } label: {
          Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(entry.fewer.text)
        TextField(entry.servings.text, text: $draft.servings)
          .labelsHidden()
          .multilineTextAlignment(.center)
          .brandText(.quantity)
          #if os(iOS)
            .keyboardType(.decimalPad)
          #endif
        Button {
          draft.nudgeServings(by: EntryDraft.servingStep)
        } label: {
          Image(systemName: "plus.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(entry.more.text)
      }
      .listRowBackground(Brand.Colors.mantle)
      FieldError(attempted ? draft.errors(requireCalories: false)[.servings] : nil)
      if let total {
        Text(monoNumbers("\(entry.total.text): \(total)", size: 13))
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
          .listRowBackground(Color.clear)
      }
    } header: {
      Text(verbatim: entry.servings.text)
    }
  }

  /// "320 kcal · 12g protein · …" for the servings and numbers as typed, when they are usable.
  private var total: String? {
    guard let valid = draft.valid(requireCalories: false) else { return nil }
    let totals = entryTotals(macros: valid.macros, servings: valid.servings)
    let macros = Copy.tracker.macros
    let grams = macros.grams.text
    return [
      "\(MacroMeter.whole(totals.calories)) \(macros.calories.text)",
      "\(MacroMeter.whole(totals.protein))\(grams) \(macros.protein.text)",
      "\(MacroMeter.whole(totals.carbs))\(grams) \(macros.carbs.text)",
      "\(MacroMeter.whole(totals.fat))\(grams) \(macros.fat.text)",
    ].joined(separator: " · ")
  }

  /// A year back from the entry's day or today, and a year ahead of it.
  private var dayRange: ClosedRange<Date> {
    let calendar = Calendar.current
    let anchor = record.day ?? TargetsForm.today() ?? LocalDate(Date.now, in: calendar)
    let earliest = anchor?.adding(days: -365).date(in: calendar) ?? .distantPast
    let latest = anchor?.adding(days: 365).date(in: calendar) ?? .distantFuture
    return earliest...latest
  }

  private var day: Binding<Date> {
    Binding(
      get: { (draft.day ?? record.day)?.date(in: .current) ?? .now },
      set: { draft.day = LocalDate($0, in: .current) })
  }

  /// Whether this entry's food is a favourite.
  private var starred: Bool {
    let key = FavouriteWrites.key(of: record)
    return favourites.contains { $0.key == key }
  }

  private func toggleFavourite() {
    do {
      if starred {
        try FavouriteWrites.unstar(key: FavouriteWrites.key(of: record), in: context)
      } else {
        try FavouriteWrites.star(record, in: context)
      }
    } catch {
      onFailure(Copy.tracker.diary.couldntSave)
    }
  }

  private func save() {
    attempted = true
    guard let valid = draft.valid(requireCalories: false) else { return }
    do {
      try DiaryEditor(context: context).update(record, with: valid)
      onClose()
    } catch DiaryWrites.Failure.dayFull {
      onFailure(Copy.tracker.dayFull)
    } catch {
      onFailure(Copy.tracker.diary.couldntSave)
    }
  }

  private func remove() {
    do {
      let removed = try DiaryEditor(context: context).remove(record)
      onClose()
      onRemoved(removed)
    } catch {
      onFailure(Copy.tracker.diary.couldntSave)
    }
  }
}
