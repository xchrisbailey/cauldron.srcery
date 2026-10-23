import CauldronImports
import CauldronKit
import SwiftData
import SwiftUI

// The ingredient list and the method: rows the cook types, reorders and removes. They change
// the draft only, through its methods, so pasting and Return split rows the same way in tests.

struct RecipeIngredientsSection: View {
  @Binding var draft: RecipeDraft
  let recipe: RecipeRecord?
  let errors: RecipeDraft.Errors?
  @FocusState private var focus: UUID?
  /// The line whose reading is open for fixing.
  @State private var fixing: UUID?

  var body: some View {
    Section {
      if draft.ingredientsLocked {
        Text(verbatim: Copy.recipeEditor.ingredientsReadOnly.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
        ForEach(Array(readOnlyRows.enumerated()), id: \.offset) { _, row in
          IngredientRowView(row: row)
        }
      } else {
        ForEach(draft.ingredients) { row in
          VStack(alignment: .leading, spacing: 4) {
            TextField("", text: text(of: row.id), axis: .vertical)
              .lineLimit(1...4)
              .textFieldStyle(.plain)
              .multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, alignment: .leading)
              .brandText(row.isHeading ? .section : .body)
              .focused($focus, equals: row.id)
              .onSubmit { draft.commitIngredient(row.id) }
              .accessibilityLabel(
                Text(
                  verbatim: row.isHeading
                    ? Copy.editor.heading(index(of: row.id)).text
                    : Copy.editor.ingredientLine(index(of: row.id)).text))
            if !row.isBlank, !row.isHeading {
              IngredientFixView(
                draft: $draft, row: row, open: fixing == row.id,
                toggle: { fixing = fixing == row.id ? nil : row.id })
            }
            if let error = errors?[.ingredient(row.id)] {
              Text(verbatim: error.text).brandText(.control).foregroundStyle(Brand.Colors.heat)
            }
            if row.flagged { FlagNote(detail: Copy.imports.unsureLine) }
          }
          .flagged(row.flagged)
          .contextMenu {
            Button(role: .destructive) {
              draft.removeIngredient(row.id)
            } label: {
              Text(verbatim: Copy.editor.remove.text)
            }
          }
        }
        .onDelete { offsets in
          for id in offsets.map({ draft.ingredients[$0].id }) { draft.removeIngredient(id) }
        }
        .onMove { draft.moveIngredients(from: $0, to: $1) }
        if let error = errors?[.ingredientList] {
          Text(verbatim: error.text).brandText(.control).foregroundStyle(Brand.Colors.heat)
        }
        HStack {
          Button {
            draft.addIngredient()
            focus = draft.ingredients.last?.id
          } label: {
            Label {
              Text(verbatim: Copy.editor.addIngredient.text)
            } icon: {
              Image(systemName: "plus")
            }
          }
          Button {
            draft.addHeading()
            focus = draft.ingredients.last?.id
          } label: {
            Label {
              Text(verbatim: Copy.editor.addHeading.text)
            } icon: {
              Image(systemName: "text.badge.plus")
            }
          }
        }
        .buttonStyle(.borderless)
        .brandText(.control)
        .tint(Brand.Colors.magic)
      }
    } header: {
      Text(verbatim: Copy.editor.ingredients.text)
    } footer: {
      Text(verbatim: Copy.editor.ingredientsHint.text).fixedSize(horizontal: false, vertical: true)
    }
    .listRowBackground(Brand.Colors.mantle)
  }

  private func index(of id: UUID) -> Int {
    (draft.ingredients.firstIndex { $0.id == id } ?? 0) + 1
  }

  /// A change to a row's text goes through the draft, which splits a paste or a line break
  /// into rows and says where to move to.
  private func text(of id: UUID) -> Binding<String> {
    Binding(
      get: { draft.ingredients.first { $0.id == id }?.text ?? "" },
      set: { newText in
        if let next = draft.setIngredientText(id, newText) { focus = next }
      })
  }

  /// The lines a newer build wrote that this one can read, grouped as the recipe shows them.
  private var readOnlyRows: [IngredientRowDraft] { draft.ingredients.filter { !$0.isBlank } }
}

/// A line of the ingredient list as plain text, for a list that can't be edited.
private struct IngredientRowView: View {
  let row: IngredientRowDraft

  var body: some View {
    if row.isHeading {
      Text(verbatim: row.text).brandText(.section)
    } else if let reading = row.reading {
      ReadingView(reading: reading)
    }
  }
}

/// How a line was read: amount and unit in Geist Mono, then the item and its note. `showsEmpty`
/// marks an empty amount or item with a dash, as the editor's chips do.
struct ReadingView: View {
  let reading: IngredientRowDraft.Reading
  var showsEmpty = false

  var body: some View {
    FlowLayout(spacing: 8) {
      if let amount = reading.amount {
        QuantityText(amount, unit: reading.unit)
      } else if showsEmpty {
        QuantityText("—", unit: reading.unit)
      } else if let unit = reading.unit {
        QuantityText(unit)
      }
      if let alt = reading.alt {
        Text(verbatim: Copy.display.alternative(alt.amount, unit: alt.unit).text).brandText(
          .quantity)
      }
      if !reading.item.isEmpty || showsEmpty {
        Text(verbatim: reading.item.isEmpty ? Copy.display.unavailable.text : reading.item)
          .brandText(.control)
      }
      if let note = reading.note {
        Text(verbatim: note).brandText(.control).foregroundStyle(Brand.Colors.subtext)
      }
      if reading.optional {
        Text(verbatim: Copy.display.parenthesized(Copy.recipeView.optional.text).text)
          .brandText(.control).foregroundStyle(Brand.Colors.subtext)
      }
    }
    .foregroundStyle(Brand.Colors.subtext)
    .accessibilityElement(children: .combine)
  }
}

struct RecipeStepsSection: View {
  @Binding var draft: RecipeDraft
  let recipe: RecipeRecord?
  let errors: RecipeDraft.Errors?
  @FocusState private var focus: UUID?
  /// The step whose timer is open for changing.
  @State private var timing: UUID?

  var body: some View {
    Section {
      if draft.stepsLocked {
        Text(verbatim: Copy.recipeEditor.stepsReadOnly.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
        ForEach(draft.steps.filter { !$0.isBlank }) { step in
          Text(verbatim: step.text).brandText(.body)
        }
      } else {
        ForEach(draft.steps) { step in
          VStack(alignment: .leading, spacing: 4) {
            TextField("", text: text(of: step.id), axis: .vertical)
              .lineLimit(1...10)
              .textFieldStyle(.plain)
              .multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, alignment: .leading)
              .brandText(.body)
              .focused($focus, equals: step.id)
              .accessibilityLabel(Text(verbatim: Copy.editor.step(index(of: step.id)).text))
            StepTimerView(
              draft: $draft, step: step, open: timing == step.id,
              toggle: { timing = timing == step.id ? nil : step.id })
            if let error = errors?[.step(step.id)] {
              Text(verbatim: error.text).brandText(.control).foregroundStyle(Brand.Colors.heat)
            }
            if step.flagged { FlagNote(detail: Copy.imports.unsureLine) }
          }
          .flagged(step.flagged)
          .contextMenu {
            Button(role: .destructive) {
              draft.removeStep(step.id)
            } label: {
              Text(verbatim: Copy.editor.remove.text)
            }
          }
        }
        .onDelete { offsets in
          for id in offsets.map({ draft.steps[$0].id }) { draft.removeStep(id) }
        }
        .onMove { draft.moveSteps(from: $0, to: $1) }
        if let error = errors?[.stepList] {
          Text(verbatim: error.text).brandText(.control).foregroundStyle(Brand.Colors.heat)
        }
        Button {
          draft.addStep()
          focus = draft.steps.last?.id
        } label: {
          Label {
            Text(verbatim: Copy.editor.addStep.text)
          } icon: {
            Image(systemName: "plus")
          }
        }
        .buttonStyle(.borderless)
        .brandText(.control)
        .tint(Brand.Colors.magic)
      }
    } header: {
      Text(verbatim: Copy.editor.steps.text)
    }
    .listRowBackground(Brand.Colors.mantle)
  }

  private func index(of id: UUID) -> Int {
    (draft.steps.firstIndex { $0.id == id } ?? 0) + 1
  }

  private func text(of id: UUID) -> Binding<String> {
    Binding(
      get: { draft.steps.first { $0.id == id }?.text ?? "" },
      set: { newText in
        if let next = draft.setStepText(id, newText) { focus = next }
      })
  }
}
