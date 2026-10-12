import CauldronKit
import SwiftData
import SwiftUI

/// One recipe: photo, facts, a servings stepper that scales the ingredients, the method, and
/// the actions. Brew, Add to week and Edit are views of their own (`Recipe*Action`), so
/// filling one in doesn't touch this file.
struct RecipeDetailView: View {
  let recipe: RecipeRecord
  /// Asked to banish this recipe. The library confirms it and does the deleting.
  let onBanish: () -> Void

  @Environment(\.modelContext) private var context
  @State private var scale: Scale
  /// The cook's choice on this page; until they make one, the preference in Settings.
  @State private var chosenUnits: UnitSystemChoice?

  init(recipe: RecipeRecord, onBanish: @escaping () -> Void) {
    self.recipe = recipe
    self.onBanish = onBanish
    _scale = State(initialValue: .initial(servings: recipe.servings))
  }

  private var units: UnitSystemChoice {
    chosenUnits ?? (try? context.current(PreferencesRecord.self))?.unitSystem ?? .asWritten
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if recipe.photo?.imageData != nil { hero }
        header
        facts
        meta
        actions
        columns
        macros
        footer
      }
      .padding(20)
      .frame(maxWidth: 1040, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .background(Brand.Colors.base)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  // MARK: Top

  private var hero: some View {
    RecipePhotoView(photo: recipe.photo, maxPixel: 1600)
      .frame(maxWidth: .infinity)
      .frame(height: 260)
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .accessibilityElement()
      .accessibilityLabel(Text(verbatim: Copy.photos.alt(recipe.title).text))
      .accessibilityAddTraits(.isImage)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: recipe.title)
        .brandText(.title)
        .accessibilityAddTraits(.isHeader)
      if let summary = recipe.summary, !summary.isEmpty {
        Text(verbatim: summary)
          .brandText(.body)
          .foregroundStyle(Brand.Colors.subtext)
      }
    }
  }

  private var facts: some View {
    let times = RecipeTimes(recipe)
    return FlowLayout {
      if let total = times.total { chip(total) }
      if let prep = times.prep { chip("\(prep) \(Copy.recipeView.prep.text)") }
      if let cook = times.cook { chip("\(cook) \(Copy.recipeView.cook.text)") }
      stepper
      ForEach(TagChip.chips(recipe), id: \.self) { TagChipView(tag: $0) }
    }
  }

  private func chip(_ text: String) -> some View {
    Text(verbatim: text)
      .brandText(.quantity)
      .padding(.horizontal, 10)
      .padding(.vertical, 3)
      .background(Brand.Colors.surface0, in: Capsule())
  }

  private var stepper: some View {
    HStack(spacing: 0) {
      stepButton(.down, symbol: "minus", label: Copy.recipeView.fewer)
      Text(verbatim: RecipeScale.label(scale))
        .brandText(.quantity)
        .padding(.horizontal, 8)
        .monospacedDigit()
        .accessibilityLabel(Text(verbatim: Copy.recipeView.servingsFor.text))
        .accessibilityValue(Text(verbatim: RecipeScale.label(scale)))
      stepButton(.up, symbol: "plus", label: Copy.recipeView.more)
    }
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.Colors.surface1, lineWidth: 1))
    .accessibilityElement(children: .contain)
  }

  private func stepButton(_ step: ScaleStep, symbol: String, label: CopyString) -> some View {
    Button {
      scale = scale.stepped(step)
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 44, height: 36)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!scale.canStep(step))
    .opacity(scale.canStep(step) ? 1 : 0.4)
    .accessibilityLabel(Text(verbatim: label.text))
  }

  @ViewBuilder
  private var meta: some View {
    let source = recipe.sourceURL.flatMap { $0.isEmpty ? nil : $0 }
    let author = recipe.sourceAuthor.flatMap { $0.isEmpty ? nil : $0 }
    if source != nil || recipe.lastCookedOn != nil {
      FlowLayout {
        if let source {
          if let link = RecipeSource.link(source) {
            Link(destination: link) {
              Text(verbatim: Copy.recipeView.from(RecipeSource.host(source)).text)
                .underline()
            }
            .tint(Brand.Colors.magic)
          } else {
            Text(verbatim: source)
          }
        }
        if let author {
          Text(verbatim: Copy.recipeView.by(author).text)
        }
        if let cooked = recipe.lastCookedOn {
          Text(verbatim: Copy.recipeView.lastCooked(RecipeDates.short(cooked)).text)
            .brandText(.quantity)
        }
      }
      .brandText(.control)
      .foregroundStyle(Brand.Colors.subtext)
    }
  }

  private var actions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { actionButtons }
      VStack(spacing: 8) { actionButtons }
    }
  }

  @ViewBuilder
  private var actionButtons: some View {
    RecipeBrewAction(recipe: recipe, scale: scale)
    RecipeAddToWeekAction(recipe: recipe, scale: scale)
    RecipeLogAction(recipe: recipe)
    RecipeEditAction(recipe: recipe)
  }

  // MARK: Ingredients and method

  private var columns: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 32) {
        ingredients.frame(minWidth: 280, maxWidth: 400, alignment: .leading)
        method.frame(minWidth: 320, maxWidth: .infinity, alignment: .leading)
      }
      VStack(alignment: .leading, spacing: 28) {
        ingredients
        method
      }
    }
  }

  private var ingredients: some View {
    let rows = IngredientRow.rows(
      recipe.ingredients, factor: scale.factor(recipeServings: recipe.servings), system: units)
    return VStack(alignment: .leading, spacing: 10) {
      sectionTitle(Copy.recipeView.ingredients)
      Picker(
        selection: Binding(get: { units }, set: { chosenUnits = $0 })
      ) {
        Text(verbatim: Copy.recipeView.asWritten.text).tag(UnitSystemChoice.asWritten)
        Text(verbatim: Copy.recipeView.metric.text).tag(UnitSystemChoice.metric)
        Text(verbatim: Copy.recipeView.us.text).tag(UnitSystemChoice.us)
      } label: {
        Text(verbatim: Copy.recipeView.units.text)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        switch row {
        case .heading(let name):
          Text(verbatim: name)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
        case .line(let line):
          IngredientLineView(line: line)
        }
      }
    }
  }

  private var method: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionTitle(Copy.recipeView.method)
      ForEach(Array(StepRow.rows(recipe.steps).enumerated()), id: \.offset) { _, row in
        switch row {
        case .heading(let name):
          Text(verbatim: name)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
            .accessibilityAddTraits(.isHeader)
        case .step(let number, let text, let timer):
          StepView(number: number, text: text, timer: timer)
        }
      }
      if let notes = recipe.notes, !notes.isEmpty {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "sparkle")
            .foregroundStyle(Brand.Colors.tips)
            .accessibilityHidden(true)
          Text(verbatim: notes).brandText(.body)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 10))
      }
    }
  }

  private func sectionTitle(_ title: CopyString) -> some View {
    Text(verbatim: title.text)
      .brandText(.section)
      .accessibilityAddTraits(.isHeader)
  }

  // MARK: Bottom

  @ViewBuilder
  private var macros: some View {
    if let line = macroLine(recipe.macros) {
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: Copy.editor.macros.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
        Text(verbatim: line.text)
          .brandText(.quantity)
          .accessibilityLabel(Text(verbatim: line.label))
      }
      .accessibilityElement(children: .combine)
    }
  }

  private var footer: some View {
    Button(role: .destructive, action: onBanish) {
      Text(verbatim: Copy.recipes.banishConfirm(recipe.title).verb.text)
        .brandText(.control)
        .foregroundStyle(Brand.Colors.heat)
        .frame(minHeight: 44)
    }
    .buttonStyle(.plain)
  }
}

/// An ingredient line: the amount in Geist Mono with its unit, then the item.
struct IngredientLineView: View {
  let line: IngredientRow.Line
  @ScaledMetric private var amountWidth: CGFloat = 84

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Group {
        if let amount = line.amount {
          QuantityText(amount, unit: line.unit)
        } else {
          Color.clear.frame(height: 1)
        }
      }
      .frame(width: amountWidth, alignment: .trailing)
      HStack(spacing: 4) {
        Text(verbatim: line.text)
        if line.optional {
          Text(verbatim: "(\(Copy.recipeView.optional.text))")
            .foregroundStyle(Brand.Colors.subtext)
        }
      }
      .brandText(.body)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: spoken))
  }

  private var spoken: String {
    let parts = [line.amount, line.unit, line.text]
    return parts.compactMap { $0 }.joined(separator: " ")
      + (line.optional ? " (\(Copy.recipeView.optional.text))" : "")
  }
}

/// A numbered step, with its timer when it has one.
struct StepView: View {
  let number: Int
  let text: String
  let timer: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(verbatim: "\(number)")
        .brandText(.quantity)
        .foregroundStyle(Brand.Colors.base)
        .frame(width: 24, height: 24)
        .background(Brand.Colors.magic, in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: text).brandText(.body)
        if let timer {
          Label {
            Text(verbatim: timer).brandText(.quantity)
          } icon: {
            Image(systemName: "timer")
          }
          .foregroundStyle(Brand.Colors.heat)
        }
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      Text(verbatim: "\(Copy.editor.step(number).text). \(text)" + (timer.map { " \($0)" } ?? "")))
  }
}
