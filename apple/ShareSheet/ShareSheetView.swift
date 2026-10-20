import CauldronImports
import CauldronKit
import SwiftUI

/// The share sheet, variant B ("Summary", #195): reading with Cancel; one screen of what was
/// found with Save and the ways out; a plain notice when it couldn't read; and the two
/// confirmations. All the logic is `ShareSheetModel`; this only draws it.
struct ShareSheetView: View {
  /// The Mac share popover's size (#205). It is fixed: the popover doesn't grow with its content.
  /// The ready state scrolls inside it with Save pinned under; every other state fits as it is.
  static let popoverSize = CGSize(width: 380, height: 520)

  let model: ShareSheetModel
  /// Starts with the folded sections open; for the view checks.
  var unfolded = false
  @ScaledMetric private var bodySize = 15

  var body: some View {
    Group {
      switch model.phase {
      case .reading: reading
      case .ready(let review):
        VStack(spacing: 0) {
          if let failure = model.retainedFailure {
            Text(verbatim: failure.message.text).foregroundStyle(Brand.Colors.heat).padding()
          }
          ReadySummary(review: review, model: model, unfolded: unfolded)
        }
      case .saved:
        ShareConfirmation(
          outcome: .sent(
            title: Copy.importNative.savedToRecipes.text,
            detail: Copy.importNative.savedDetail.text))
      case .sent:
        ShareConfirmation(
          outcome: .sent(
            title: Copy.importNative.sentToCauldron.text,
            detail: Copy.sharedDrafts.openToFinish.text))
      case .failed(let notice): failed(notice)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.Colors.base.ignoresSafeArea())
    .tint(Brand.Colors.magic)
    .task { model.start() }
  }

  private var reading: some View {
    VStack(spacing: 16) {
      ProgressView().tint(Brand.Colors.magic)
      Text(verbatim: Copy.importNative.readingRecipe.text)
        .font(ShareFonts.font(size: bodySize, weight: 400))
        .foregroundStyle(Brand.Colors.subtext)
      Button(Copy.recipeView.cancel.text) { model.cancel() }
        .buttonStyle(ShareButtonStyle(kind: .plain))
    }
    .frame(maxWidth: 360)
    .padding(24)
  }

  private func failed(_ notice: ShareSheetModel.Notice) -> some View {
    VStack(spacing: 16) {
      Image(systemName: notice.kind == .noKey ? "key" : "exclamationmark.circle")
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(notice.kind == .noKey ? Brand.Colors.tips : Brand.Colors.heat)
        .accessibilityHidden(true)
      Text(verbatim: notice.message.text)
        .font(ShareFonts.font(size: bodySize, weight: 400))
        .foregroundStyle(Brand.Colors.ink)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: 8) {
        if notice.canSend {
          Button(Copy.importNative.sendInstead.text) { model.sendToCauldron() }
            .buttonStyle(ShareButtonStyle(kind: .prominent))
          Text(verbatim: Copy.importNative.opensAsDraft.text)
            .font(ShareFonts.font(size: bodySize - 2, weight: 400))
            .foregroundStyle(Brand.Colors.subtext)
            .multilineTextAlignment(.center)
        }
        Button(Copy.recipeView.cancel.text) { model.cancel() }
          .buttonStyle(ShareButtonStyle(kind: notice.canSend ? .plain : .prominent))
      }
    }
    .frame(maxWidth: 360)
    .padding(24)
  }
}

// MARK: - The ready state

/// What was found, in the order the cook reads it: the recipe, its numbers, anything to check,
/// the folded lists; and Save with the ways out pinned under them so they stay in reach.
private struct ReadySummary: View {
  let review: ShareSheetModel.Review
  let model: ShareSheetModel
  @State private var ingredientsOpen: Bool
  @State private var stepsOpen: Bool
  @State private var validationRequest = 0
  @FocusState private var focus: RecipeDraft.Field?
  @AccessibilityFocusState private var accessibilityFocus: RecipeDraft.Field?
  @ScaledMetric private var bodySize = 15

  init(review: ShareSheetModel.Review, model: ShareSheetModel, unfolded: Bool) {
    self.review = review
    self.model = model
    _ingredientsOpen = State(initialValue: unfolded)
    _stepsOpen = State(initialValue: unfolded)
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            header
            ShareSheetFields(model: model, focus: $focus, accessibilityFocus: $accessibilityFocus)
            ForEach(Array(readOnlyProblems.enumerated()), id: \.offset) { _, problem in
              note(problem.text, "exclamationmark.circle")
            }
            StatsStrip(review: review)
            macroLineSlot
            duplicateBannerSlot
            if review.linesToCheck > 0 {
              note(
                Copy.importNative.linesToCheck(review.linesToCheck).text, "exclamationmark.circle")
            }
            if review.rough {
              note(Copy.importNative.rough.text, "wand.and.stars")
            }
            Text(verbatim: Copy.shareSheetFields.readOnlyLists.text)
              .font(ShareFonts.font(size: bodySize - 2, weight: 400))
              .foregroundStyle(Brand.Colors.subtext)
            DisclosureGroup(isExpanded: $ingredientsOpen) {
              IngredientList(draft: review.draft).padding(.top, 8)
            } label: {
              sectionTitle(Copy.importNative.ingredientsSection.text)
            }
            DisclosureGroup(isExpanded: $stepsOpen) {
              StepList(draft: review.draft).padding(.top, 8)
            } label: {
              sectionTitle(Copy.importNative.stepsSection.text)
            }
          }
          .padding(16)
          .frame(maxWidth: 520, alignment: .leading)
          .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: focus) { old, new in
          if let old {
            model.blurred(old)
            if let error = model.error(for: old) {
              AccessibilityNotification.Announcement(error.text).post()
            }
          }
          if let new { withAnimation { proxy.scrollTo(new, anchor: .center) } }
        }
        .onChange(of: validationRequest) {
          if let field = model.firstInvalidField {
            withAnimation { proxy.scrollTo(field, anchor: .center) }
          }
        }
        .onAppear {
          if model.currentDraft?.trimmed(review.draft.title).isEmpty == true { focus = .title }
        }
      }
      actions
    }
  }

  /// Read-only problems use the same messages as the full editor, with the affected section.
  private var readOnlyProblems: [CopyString] {
    guard model.saveAttempted else { return [] }
    let errors = review.draft.validate()
    let fields: [(RecipeDraft.Field, CopyString)] =
      [
        (.summary, Copy.editor.description), (.totalMinutes, Copy.editor.totalMinutes),
        (.calories, Copy.editor.macros), (.protein, Copy.editor.macros),
        (.carbs, Copy.editor.macros), (.fat, Copy.editor.macros),
        (.sourceURL, Copy.editor.sourceUrl), (.notes, Copy.editor.notes), (.tags, Copy.editor.tags),
        (.ingredientList, Copy.editor.ingredients), (.stepList, Copy.editor.steps),
      ] + review.draft.ingredients.map { (.ingredient($0.id), Copy.editor.ingredients) }
      + review.draft.steps.map { (.step($0.id), Copy.editor.steps) }
    return fields.compactMap { field, label in
      errors[field].map { Copy.shareSheetFields.problem(label, $0) }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      thumbnailSlot
      VStack(alignment: .leading, spacing: 4) {
        if let source = review.source {
          Text(verbatim: source)
            .font(ShareFonts.font(size: bodySize - 2, weight: 400))
            .foregroundStyle(Brand.Colors.subtext)
        }
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  /// The imported cover stays with the source context above the corrections.
  @ViewBuilder private var thumbnailSlot: some View {
    if let cover = PhotoProcessing.thumbnail(of: review.thumbnail?.data, maxPixel: 240) {
      Image(decorative: cover, scale: 1)
        .resizable()
        .scaledToFill()
        .frame(width: 72, height: 72)
        .clipShape(.rect(cornerRadius: 12))
    }
  }

  /// The macros per serving, or why there are none yet (#203). Never a guess: an estimate says
  /// so.
  @ViewBuilder private var macroLineSlot: some View {
    if let macros = review.macros, let line = macroLine(macros) {
      Text(
        verbatim: review.macrosEstimated
          ? Copy.importNative.estimatedMacros(line.text).text : line.text
      )
      .font(ShareFonts.mono(size: bodySize - 2))
      .foregroundStyle(Brand.Colors.subtext)
      .accessibilityLabel(Text(verbatim: line.label))
    } else if review.macrosPending {
      Text(verbatim: Copy.importNative.macrosLater.text)
        .font(ShareFonts.font(size: bodySize - 2, weight: 400))
        .foregroundStyle(Brand.Colors.subtext)
    }
  }

  /// "You already have this one", when a recipe from the same link is in the box (#204).
  /// Saving still works.
  @ViewBuilder private var duplicateBannerSlot: some View {
    if review.duplicate {
      Label {
        Text(verbatim: Copy.importNative.alreadyInBox.text)
      } icon: {
        Image(systemName: "square.on.square")
      }
      .font(ShareFonts.font(size: bodySize - 1, weight: 500))
      .foregroundStyle(Brand.Colors.tips)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Brand.Colors.surface0, in: .rect(cornerRadius: 10))
    }
  }

  private func note(_ text: String, _ symbol: String) -> some View {
    Label {
      Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: symbol)
    }
    .font(ShareFonts.font(size: bodySize - 1, weight: 500))
    .foregroundStyle(Brand.Colors.tips)
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(verbatim: text)
      .font(ShareFonts.font(size: bodySize + 1, weight: 600))
      .foregroundStyle(Brand.Colors.ink)
  }

  private var saveLabel: CopyString {
    review.duplicate ? Copy.importNative.saveAnotherCopy : Copy.importNative.saveToRecipes
  }

  private var actions: some View {
    VStack(spacing: 4) {
      if model.saveAttempted && model.hasReadOnlyErrors {
        Text(verbatim: Copy.shareSheetFields.readOnlyProblems.text)
          .font(ShareFonts.font(size: bodySize - 2, weight: 400))
          .foregroundStyle(Brand.Colors.heat)
          .fixedSize(horizontal: false, vertical: true)
      }
      Button(saveLabel.text) {
        model.save()
        if case .ready = model.phase {
          validationRequest += 1
          if let field = model.firstInvalidField {
            focus = field
            accessibilityFocus = field
            if let error = model.error(for: field) {
              AccessibilityNotification.Announcement(error.text).post()
            }
          } else if model.hasReadOnlyErrors {
            AccessibilityNotification.Announcement(Copy.shareSheetFields.readOnlyProblems.text)
              .post()
          }
        }
      }
      .buttonStyle(ShareButtonStyle(kind: .prominent))
      ViewThatFits(in: .horizontal) {
        HStack {
          Button(Copy.recipeView.cancel.text) { model.cancel() }
          Button(review.editLabel.text) { model.sendToCauldron() }
        }
        VStack(spacing: 0) {
          Button(review.editLabel.text) { model.sendToCauldron() }
          Button(Copy.recipeView.cancel.text) { model.cancel() }
        }
      }
      .buttonStyle(ShareButtonStyle(kind: .plain))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity)
    .background(Brand.Colors.mantle)
  }
}

/// Ingredients, steps, total time and servings, set in Geist Mono.
private struct StatsStrip: View {
  let review: ShareSheetModel.Review
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric private var valueSize = 17
  @ScaledMetric private var labelSize = 12

  var body: some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 2 : 4),
      spacing: 10
    ) {
      stat("\(review.ingredients)", Copy.importNative.ingredientsLabel.text)
      stat("\(review.steps)", Copy.importNative.stepsLabel.text)
      stat(
        review.minutes.flatMap { $0 > 0 ? formatTimer($0 * 60) : nil }
          ?? Copy.importNative.unknownStat.text,
        Copy.recipeView.total.text)
      stat(
        review.servings.map(String.init) ?? Copy.importNative.unknownStat.text,
        Copy.importNative.servesLabel.text)
    }
    .padding(.vertical, 10)
    .background(Brand.Colors.mantle, in: .rect(cornerRadius: 12))
  }

  private func stat(_ value: String, _ label: String) -> some View {
    VStack(spacing: 2) {
      Text(verbatim: value)
        .font(ShareFonts.mono(size: valueSize, weight: 500))
        .foregroundStyle(Brand.Colors.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(verbatim: label)
        .font(ShareFonts.font(size: labelSize, weight: 400))
        .foregroundStyle(Brand.Colors.subtext)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}

/// The ingredient lines as the importer read them; ones it wasn't sure of in the tips colour.
private struct IngredientList: View {
  let draft: RecipeDraft
  @ScaledMetric private var size = 15

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(draft.ingredients.filter { !$0.isBlank }) { row in
        if row.isHeading {
          Text(verbatim: row.text)
            .font(ShareFonts.font(size: size, weight: 600))
            .foregroundStyle(Brand.Colors.subtext)
            .padding(.top, 4)
        } else {
          line(row)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func line(_ row: IngredientRowDraft) -> some View {
    let colour = row.flagged ? Brand.Colors.tips : Brand.Colors.ink
    return HStack(alignment: .firstTextBaseline, spacing: 8) {
      if let parsed = row.parsed {
        if let quantity = parsed.quantity {
          let measure = measureParts(quantity, unit: parsed.unit)
          Text(verbatim: measure.amount)
            .font(ShareFonts.mono(size: size, weight: 500))
            .foregroundStyle(colour)
          if let unit = measure.unit {
            Text(verbatim: unit)
              .font(ShareFonts.mono(size: size - 2))
              .foregroundStyle(Brand.Colors.overlay1)
          }
        }
        Text(verbatim: parsed.note.map { "\(parsed.item), \($0)" } ?? parsed.item)
          .font(ShareFonts.font(size: size, weight: 400))
          .foregroundStyle(colour)
      } else {
        Text(verbatim: row.text)
          .font(ShareFonts.font(size: size, weight: 400))
          .foregroundStyle(colour)
      }
      if row.flagged {
        // Not by colour alone.
        Image(systemName: "exclamationmark.circle")
          .font(.system(size: size - 2))
          .foregroundStyle(Brand.Colors.tips)
          .accessibilityHidden(true)
      }
    }
  }
}

/// The steps, numbered.
private struct StepList: View {
  let draft: RecipeDraft
  @ScaledMetric private var size = 15

  var body: some View {
    let steps = draft.steps.filter { !$0.isBlank }
    VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(verbatim: "\(index + 1)")
            .font(ShareFonts.mono(size: size - 1, weight: 500))
            .foregroundStyle(Brand.Colors.magic)
            .frame(minWidth: 18, alignment: .trailing)
          Text(verbatim: step.text)
            .font(ShareFonts.font(size: size, weight: 400))
            .foregroundStyle(step.flagged ? Brand.Colors.tips : Brand.Colors.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The sheet's two kinds of button, in the brand colours (the app's own styles are not in the
/// extension).
private struct ShareButtonStyle: ButtonStyle {
  enum Kind { case prominent, plain }
  let kind: Kind
  @Environment(\.isEnabled) private var isEnabled
  @ScaledMetric private var buttonSize = 16

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(ShareFonts.font(size: buttonSize, weight: 600))
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, minHeight: 44)
      .foregroundStyle(kind == .prominent ? Brand.Colors.base : Brand.Colors.magic)
      .background(kind == .prominent ? Brand.Colors.magic : .clear, in: Capsule())
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
      .contentShape(Capsule())
  }
}
