import CauldronKit
import SwiftData
import SwiftUI

/// What each way of adding is handed.
struct AddContext {
  let day: LocalDate
  let slot: MealSlot
  /// Logs the entries at the end of the meal and closes the sheet. When it can't, nothing is
  /// logged and the answer is the message to show.
  let log: ([NewEntry]) -> CopyString?
}

/// The ways into the add sheet. The sheet shows the ones that are ready: each way is a view in
/// a file of its own (`AddRecentsTab`, `AddDescribeTab`, `AddRecipeTab`), turned on there.
enum AddWay: CaseIterable, Identifiable, Hashable {
  case recents
  case describe
  case recipe
  case quick

  var id: Self { self }

  var label: CopyString {
    switch self {
    case .recents: Copy.tracker.addTabs.recents
    case .describe: Copy.tracker.addTabs.describe
    case .recipe: Copy.tracker.addTabs.recipe
    case .quick: Copy.tracker.addTabs.quick
    }
  }

  var isAvailable: Bool {
    switch self {
    case .recents: AddRecentsTab.isAvailable
    case .describe: AddDescribeTab.isAvailable
    case .recipe: AddRecipeTab.isAvailable
    case .quick: true
    }
  }

  static var available: [AddWay] { allCases.filter(\.isAvailable) }
}

/// What the add button on a meal opens: the ways to log something into that meal.
struct DiaryAddSheet: View {
  let day: LocalDate
  let slot: MealSlot
  let onClose: () -> Void

  @Environment(\.modelContext) private var context
  @State private var way = AddWay.available.first ?? .quick

  private var slotName: String { Copy.week.slots[slot].text }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if AddWay.available.count > 1 {
          Picker(selection: $way) {
            ForEach(AddWay.available) { way in
              Text(verbatim: way.label.text).tag(way)
            }
          } label: {
            Text(verbatim: Copy.tracker.addTabs.label.text)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .padding([.horizontal, .top], 16)
        }
        content
      }
      .background(Brand.Colors.base)
      .navigationTitle(Copy.tracker.entry.addTitle(slotName).text)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(Copy.tracker.entry.cancel.text, action: onClose)
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 540)
    #endif
  }

  private var addContext: AddContext {
    AddContext(day: day, slot: slot) { entries in
      do {
        try DiaryWrites.add(entries, on: day, slot: slot, in: context)
        onClose()
        return nil
      } catch DiaryWrites.Failure.dayFull {
        return Copy.tracker.dayFull
      } catch DiaryWrites.Failure.invalid {
        return Copy.tracker.targets.fixThese
      } catch {
        return Copy.tracker.diary.couldntSave
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch way {
    case .recents: AddRecentsTab(context: addContext)
    case .describe: AddDescribeTab(context: addContext)
    case .recipe: AddRecipeTab(context: addContext)
    case .quick: DiaryQuickAdd(context: addContext)
    }
  }
}

/// Quick add: a name, an amount and the numbers, typed in. The plain way in that always works.
struct DiaryQuickAdd: View {
  let context: AddContext

  @State private var draft: EntryDraft
  @State private var attempted = false
  @State private var failure: CopyString?

  init(context: AddContext) {
    self.context = context
    _draft = State(initialValue: EntryDraft(slot: context.slot))
  }

  var body: some View {
    Form {
      Section {
        Text(verbatim: Copy.tracker.entry.quickAddHint.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
          .listRowBackground(Color.clear)
      }
      DiaryEntryFields(
        draft: $draft, errors: attempted ? draft.errors(requireCalories: true) : [:])
      if let failure {
        Section {
          Text(verbatim: failure.text)
            .brandText(.body)
            .foregroundStyle(Brand.Colors.heat)
            .listRowBackground(Brand.Colors.mantle)
        }
      }
      Section {
        HStack {
          Spacer()
          Button(action: log) {
            // `base` reads on the brand colour in both appearances.
            Text(verbatim: Copy.tracker.entry.log.text).foregroundStyle(Brand.Colors.base)
          }
          .buttonStyle(.borderedProminent)
          .tint(Brand.Colors.magic)
          .brandText(.control)
        }
        .listRowBackground(Color.clear)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }

  private func log() {
    attempted = true
    guard let valid = draft.valid(requireCalories: true) else { return }
    failure = context.log([NewEntry(valid, source: .manual)])
  }
}
