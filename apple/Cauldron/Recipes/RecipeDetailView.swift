import CauldronKit
import SwiftData
import SwiftUI

/// One recipe: photo, facts, a servings stepper that scales the ingredients, the method, and
/// the actions. Brew, Add to week and Edit are views of their own (`Recipe*Action`), so
/// filling one in doesn't touch this file.
struct RecipeDetailView: View {
  let recipe: RecipeRecord
  /// Whether this is the recipe's own window on the Mac, where there is no other window to open.
  let inOwnWindow: Bool
  /// Whether it was pushed onto a phone's navigation stack, whose bar is its own to title. Beside
  /// a list the bar belongs to the whole screen, so the recipe leaves it alone.
  let pushed: Bool
  /// Asked to banish this recipe. The library confirms it and does the deleting.
  let onBanish: () -> Void

  @Environment(\.modelContext) private var context
  #if os(macOS)
    @Environment(\.openWindow) private var openWindow
  #endif
  /// The unit system is the cook's one choice, kept for every page and for brew mode.
  @Query private var preferences: [PreferencesRecord]
  @State private var scale: Scale
  /// The ingredients ticked off while cooking. Not kept: it starts empty each time the page
  /// opens, as on the web.
  @State private var checked: Set<Int> = []
  /// The editor and the week's sheet, held here so the Recipe menu can open them.
  @State private var editing = false
  @State private var choosing = false
  /// The copy just made, whose editor is open.
  @State private var copy: RecipeRecord?
  @State private var couldntCopy = false
  /// Where the page's own title ends in the scrolled content, and whether it has scrolled out of
  /// sight. Until it has, the page's title is the only one; the navigation bar's takes over then.
  @State private var titleBottom: CGFloat = .infinity
  @State private var titleScrolledOut = false

  init(
    recipe: RecipeRecord, inOwnWindow: Bool = false, pushed: Bool = false,
    onBanish: @escaping () -> Void
  ) {
    self.recipe = recipe
    self.inOwnWindow = inOwnWindow
    self.pushed = pushed
    self.onBanish = onBanish
    _scale = State(initialValue: .initial(servings: recipe.servings))
  }

  private static let contentSpace = "recipeContent"

  private var units: UnitSystemChoice { UnitPreference.current(preferences) }

  /// What this page prints, at the scale and in the units on screen.
  private var printout: RecipePrintout { RecipePrintout(recipe, scale: scale, units: units) }

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
      .coordinateSpace(.named(Self.contentSpace))
      .frame(maxWidth: 1040, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .background(Brand.Colors.base)
    .onScrollGeometryChange(for: Bool.self) { [titleBottom] geometry in
      geometry.contentOffset.y + geometry.contentInsets.top >= titleBottom
    } action: { _, scrolledOut in
      titleScrolledOut = scrolledOut
    }
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      .modifier(PushedTitle(pushed: pushed, title: titleScrolledOut ? recipe.title : ""))
    #endif
    .sheet(item: $copy) { RecipeCopySheet(copy: $0) }
    #if os(macOS)
      .focusedSceneValue(\.recipeCommands, menuCommands)
    #endif
  }

  #if os(macOS)
    /// What the Recipe menu does to this recipe, at the scale the cook has chosen.
    private var menuCommands: RecipeCommands {
      let recipeID = recipe.id
      let scale = scale
      let openInWindow: (() -> Void)? =
        inOwnWindow ? nil : { openWindow(value: RecipeWindowRequest(recipeID: recipeID)) }
      return RecipeCommands(
        isBanished: recipe.isBanished,
        edit: { editing = true },
        brew: { openWindow(value: BrewRequest(recipeID: recipeID, scale: scale)) },
        stir: { choosing = true },
        openInWindow: openInWindow,
        duplicate: { makeCopy() },
        printRecipe: { RecipePrinting.print(printout) })
    }
  #endif

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
        // The navigation bar has no title to announce until this one scrolls away.
        .accessibilitySortPriority(1)
        .onGeometryChange(for: CGFloat.self) { proxy in
          proxy.frame(in: .named(Self.contentSpace)).maxY
        } action: {
          titleBottom = $0
        }
      if let summary = recipe.summary, !summary.isEmpty {
        Text(verbatim: summary)
          .brandText(.body)
          .foregroundStyle(Brand.Colors.subtext)
      }
    }
  }

  /// Three rows at every width, so a recipe's facts sit in the same places as the next one's:
  /// its times, the servings stepper, and its tags. A row with nothing to show is left out.
  private var facts: some View {
    let times = RecipeTimes(recipe)
    let tags = TagChip.chips(recipe)
    return VStack(alignment: .leading, spacing: 10) {
      if times.total != nil || times.prep != nil || times.cook != nil {
        FlowLayout {
          if let total = times.total { chip(total) }
          if let prep = times.prep { chip("\(prep) \(Copy.recipeView.prep.text)") }
          if let cook = times.cook { chip("\(cook) \(Copy.recipeView.cook.text)") }
        }
      }
      stepper
      if !tags.isEmpty {
        FlowLayout {
          ForEach(tags, id: \.self) { TagChipView(tag: $0) }
        }
      }
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

  /// Start brewing is the one filled button and Stir into the week sits beside it on a plate.
  /// The rest are bare text under them: no weight of their own, but each still a 44pt target.
  private var actions: some View {
    VStack(alignment: .leading, spacing: 4) {
      row {
        RecipeBrewAction(recipe: recipe, scale: scale)
        RecipeAddToWeekAction(recipe: recipe, scale: scale, isChoosing: $choosing)
      }
      FlowLayout(spacing: 0) {
        RecipeLogAction(recipe: recipe)
        RecipeMarkBrewedAction(recipe: recipe)
        RecipeEditAction(recipe: recipe, isEditing: $editing)
      }
      // The quiet buttons pad their text; take it back so the words line up with the plates.
      .padding(.leading, -8)
    }
    // Buttons that each fill their share would stretch across a wide window.
    .frame(maxWidth: 640, alignment: .leading)
  }

  /// Side by side where they fit, stacked where they don't.
  private func row(@ViewBuilder _ buttons: () -> some View) -> some View {
    let buttons = buttons()
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { buttons }
      VStack(spacing: 8) { buttons }
    }
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
    let lineCount = rows.filter { if case .line = $0 { true } else { false } }.count
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        sectionTitle(Copy.recipeView.ingredients)
        Spacer(minLength: 8)
        if lineCount > 0 {
          Text(verbatim: Copy.recipeView.checked(checked.count, lineCount).text)
            .brandText(.quantity)
            .foregroundStyle(Brand.Colors.subtext)
        }
      }
      Picker(
        selection: Binding(
          get: { units },
          set: { UnitPreference.set($0, preferences: preferences, in: context) })
      ) {
        Text(verbatim: Copy.recipeView.asWritten.text).tag(UnitSystemChoice.asWritten)
        Text(verbatim: Copy.recipeView.metric.text).tag(UnitSystemChoice.metric)
        Text(verbatim: Copy.recipeView.us.text).tag(UnitSystemChoice.us)
      } label: {
        Text(verbatim: Copy.recipeView.units.text)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
        switch row {
        case .heading(let name):
          Text(verbatim: name)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
        case .line(let line):
          Toggle(isOn: tick(offset)) {
            IngredientLineView(line: line, done: checked.contains(offset))
          }
          .toggleStyle(IngredientTickStyle())
        }
      }
    }
  }

  /// Whether the ingredient at a row is ticked off. Rows are counted with their headings, which
  /// stay put when the scale or the units change.
  private func tick(_ offset: Int) -> Binding<Bool> {
    Binding(
      get: { checked.contains(offset) },
      set: { if $0 { checked.insert(offset) } else { checked.remove(offset) } })
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
        // The brand book's cook's tip: a wash of `tips` with a hairline of it, and the sparkle.
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "sparkle")
            .foregroundStyle(Brand.Colors.tips)
            .accessibilityHidden(true)
          Text(verbatim: notes).brandText(.body)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.Colors.tips.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Brand.Colors.tips.opacity(0.3), lineWidth: 1))
      }
    }
  }

  private func sectionTitle(_ title: CopyString) -> some View {
    Text(verbatim: title.text)
      .brandText(.section)
      .accessibilityAddTraits(.isHeader)
  }

  // MARK: Bottom

  private var macros: some View {
    RecipeMacrosSection(recipe: recipe)
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 0) {
      if couldntCopy {
        Text(verbatim: Copy.errors.internal.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.heat)
      }
      FlowLayout(spacing: 20) {
        printButton
        footerButton(Copy.recipeView.duplicate.text, color: Brand.Colors.subtext) { makeCopy() }
          .disabled(recipe.isBanished)
        Button(role: .destructive, action: onBanish) {
          Text(verbatim: Copy.recipes.banishConfirm(recipe.title).verb.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.heat)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
      }
    }
  }

  /// The Mac prints straight to its print panel. The phone shares the recipe as a PDF, whose
  /// share sheet has Print, Save to Files and the rest.
  @ViewBuilder
  private var printButton: some View {
    #if os(macOS)
      footerButton(Copy.recipeView.print.text, color: Brand.Colors.subtext) {
        RecipePrinting.print(printout)
      }
    #else
      ShareLink(item: printout, preview: SharePreview(printout.title)) {
        Text(verbatim: Copy.recipeView.print.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
          .frame(minHeight: 44)
      }
    #endif
  }

  private func footerButton(
    _ title: String, color: Color, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(verbatim: title)
        .brandText(.control)
        .foregroundStyle(color)
        .frame(minHeight: 44)
    }
    .buttonStyle(.plain)
  }

  /// Makes a copy and opens its editor.
  private func makeCopy() {
    guard !recipe.isBanished else { return }
    couldntCopy = false
    do {
      copy = try RecipeDuplication.duplicate(recipe, context: context)
    } catch {
      couldntCopy = true
    }
  }
}

#if os(iOS)
  /// Titles the navigation bar of a recipe pushed onto a stack. Any other recipe leaves the bar be:
  /// setting even an empty title there would blank the list's own.
  private struct PushedTitle: ViewModifier {
    let pushed: Bool
    let title: String

    func body(content: Content) -> some View {
      if pushed {
        content.navigationTitle(title)
      } else {
        content
      }
    }
  }
#endif

/// A flowing ingredient line, with the amount and unit kept together in Geist Mono.
struct IngredientLineView: View {
  let line: IngredientRow.Line
  /// Ticked off: struck through and quieter.
  var done = false
  @ScaledMetric(relativeTo: .footnote) private var quantitySize: CGFloat = 13

  var body: some View {
    Text(attributed)
      .brandText(.body)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .strikethrough(done)
      .foregroundStyle(done ? AnyShapeStyle(Brand.Colors.overlay1) : AnyShapeStyle(.foreground))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: spoken))
  }

  private var attributed: AttributedString {
    var result = AttributedString()
    if let amount = line.amount {
      var value = AttributedString(amount)
      value.font = .brand(.quantity, size: quantitySize)
      result += value
    }
    if let unit = line.unit {
      if !result.characters.isEmpty { result += AttributedString("\u{00a0}") }
      var unit = AttributedString(unit)
      unit.font = .brand(.unit, size: quantitySize)
      unit.foregroundColor = Brand.Colors.overlay1
      result += unit
    }
    // An en space separates the measurement from the ingredient without a fixed column.
    if !result.characters.isEmpty { result += AttributedString("\u{2002}") }
    result += AttributedString(line.text)
    if line.optional {
      var optional = AttributedString(" (\(Copy.recipeView.optional.text))")
      optional.foregroundColor = done ? Brand.Colors.overlay1 : Brand.Colors.subtext
      result += optional
    }
    return result
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
      Text(verbatim: Copy.display.number(number).text)
        .brandText(.quantity)
        .foregroundStyle(Brand.Colors.base)
        .frame(width: 24, height: 24)
        .background(Brand.Colors.magic, in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: text).brandText(.body)
        if let timer {
          // The brand book's timer chip: heat text on a wash of heat.
          Label {
            Text(verbatim: timer).brandText(.quantity)
          } icon: {
            Image(systemName: "timer")
          }
          .foregroundStyle(Brand.Colors.heat)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(Brand.Colors.heat.opacity(0.14), in: Capsule())
        }
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      Text(
        verbatim: Copy.display.accessibleStepAndTimer(
          Copy.editor.step(number).text, text: text, timer: timer
        ).text))
  }
}

/// A tick box before an ingredient, for crossing it off while cooking. The whole line is the
/// button, and VoiceOver reads it as a switch with the ingredient as its name.
struct IngredientTickStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(configuration.isOn ? Brand.Colors.magic : Brand.Colors.overlay1)
          .frame(width: 22)
          .accessibilityHidden(true)
        configuration.label
      }
      .frame(minHeight: 36)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
  }
}
