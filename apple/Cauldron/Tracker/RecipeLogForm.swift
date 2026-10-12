import CauldronKit
import SwiftData
import SwiftUI

/// Servings (and, outside the diary's add sheet, the meal and day) for one recipe, then log it.
/// The add sheet's Recipe tab and `RecipeLogSheet` both use it. `onLog` logs the draft and
/// answers with the message to show when it couldn't.
struct RecipeLogForm: View {
  let recipe: RecipeRecord
  let chooseSlot: Bool
  let chooseDay: Bool
  /// Shown as "Change recipe" in the add sheet, to go back to the list.
  let onBack: (() -> Void)?
  let onLog: (RecipeLogDraft) -> CopyString?

  @State private var draft: RecipeLogDraft
  @State private var attempted = false
  @State private var failure: CopyString?

  private let entry = Copy.tracker.entry

  init(
    recipe: RecipeRecord, draft: RecipeLogDraft, chooseSlot: Bool = false, chooseDay: Bool = false,
    onBack: (() -> Void)? = nil, onLog: @escaping (RecipeLogDraft) -> CopyString?
  ) {
    self.recipe = recipe
    self.chooseSlot = chooseSlot
    self.chooseDay = chooseDay
    self.onBack = onBack
    self.onLog = onLog
    _draft = State(initialValue: draft)
  }

  var body: some View {
    Form {
      Section {
        HStack {
          Text(verbatim: recipe.title).brandText(.section)
          Spacer()
          if let onBack {
            Button(Copy.tracker.logRecipe.change.text, action: onBack)
              .brandText(.control)
          }
        }
        .listRowBackground(Brand.Colors.mantle)
      }

      Section {
        HStack {
          Button {
            draft.nudge(by: -RecipeLogDraft.step)
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
            draft.nudge(by: RecipeLogDraft.step)
          } label: {
            Image(systemName: "plus.circle")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(entry.more.text)
        }
        .listRowBackground(Brand.Colors.mantle)
        HStack(spacing: 8) {
          ForEach(RecipeLogDraft.quickServings, id: \.self) { amount in
            Button {
              draft.servings = showNumber(amount, digits: 2)
            } label: {
              Text(verbatim: Self.chipLabel(amount))
                .brandText(.quantity)
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .tint(draft.servingsValue == amount ? Brand.Colors.magic : Brand.Colors.overlay1)
            .accessibilityAddTraits(draft.servingsValue == amount ? .isSelected : [])
          }
        }
        .listRowBackground(Brand.Colors.mantle)
        FieldError(attempted ? draft.servingsError : nil)
        Text(monoNumbers("\(entry.total.text): \(totalText)", size: 13))
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
          .listRowBackground(Color.clear)
      } header: {
        Text(verbatim: entry.servings.text)
      }

      if hasGaps(recipe.macros) {
        Section {
          Text(verbatim: Copy.tracker.logRecipe.gaps.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
            .listRowBackground(Brand.Colors.mantle)
          LogRecipeDivineOffer(recipe: recipe)
            .listRowBackground(Brand.Colors.mantle)
        }
      }

      if chooseSlot || chooseDay {
        Section {
          if chooseSlot {
            Picker(selection: $draft.slot) {
              ForEach(MealSlot.allCases, id: \.self) { slot in
                Text(verbatim: Copy.week.slots[slot].text).tag(slot)
              }
            } label: {
              Text(verbatim: entry.meal.text)
            }
            .brandText(.body)
            .listRowBackground(Brand.Colors.mantle)
          }
          if chooseDay {
            DatePicker(selection: day, displayedComponents: .date) {
              Text(verbatim: entry.day.text)
            }
            .brandText(.quantity)
            .listRowBackground(Brand.Colors.mantle)
          }
        }
      }

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
            Text(verbatim: entry.log.text).foregroundStyle(Brand.Colors.base)
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
    .background(Brand.Colors.base)
  }

  private var day: Binding<Date> {
    Binding(
      get: { draft.day.date(in: .current) ?? .now },
      set: { draft.day = LocalDate($0, in: .current) ?? draft.day })
  }

  private static func chipLabel(_ amount: Double) -> String {
    switch amount {
    case 0.5: "½"
    case 1.5: "1½"
    default: showNumber(amount, digits: 2)
    }
  }

  /// "320 kcal · 12g protein · …" for the servings as typed.
  private var totalText: String {
    let totals = draft.totals(of: recipe)
    let macros = Copy.tracker.macros
    let grams = macros.grams.text
    return [
      "\(MacroMeter.whole(totals.calories)) \(macros.calories.text)",
      "\(MacroMeter.whole(totals.protein))\(grams) \(macros.protein.text)",
      "\(MacroMeter.whole(totals.carbs))\(grams) \(macros.carbs.text)",
      "\(MacroMeter.whole(totals.fat))\(grams) \(macros.fat.text)",
    ].joined(separator: " · ")
  }

  private func log() {
    attempted = true
    guard draft.servingsValue != nil else { return }
    failure = onLog(draft)
  }
}
