import CauldronKit
import SwiftData
import SwiftUI

/// A recipe's per-serving macros at the foot of its page, marked when they are an estimate,
/// with the button that divines them from the ingredients when they are missing.
struct RecipeMacrosSection: View {
  let recipe: RecipeRecord

  var body: some View {
    let line = macroLine(recipe.macros)
    if line != nil || RecipeMacroEstimates.state(of: recipe) != .hidden {
      VStack(alignment: .leading, spacing: 8) {
        if let line {
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: Copy.editor.macros.text)
              .brandText(.control)
              .foregroundStyle(Brand.Colors.subtext)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(verbatim: line.text)
                .brandText(.quantity)
                .accessibilityLabel(Text(verbatim: line.label))
              if recipe.macrosSource == .estimated {
                Text(verbatim: Copy.tracker.diary.estimate.text)
                  .brandText(.unit)
                  .foregroundStyle(Brand.Colors.subtext)
              }
            }
          }
          .accessibilityElement(children: .combine)
        }
        RecipeDivineControl(recipe: recipe)
      }
    }
  }
}

/// "Divine from ingredients" for a saved recipe, in the state the recipe is in: the button, a
/// line saying the estimate is waiting, or a note that the last try gave up (with the button
/// there to ask again). The line for how the AI stands sits beside it when it needs attention.
/// It shows nothing where the recipe has nothing to divine, or where there is no AI service.
struct RecipeDivineControl: View {
  let recipe: RecipeRecord

  @Environment(RecipeAIService.self) private var ai: RecipeAIService?
  @Environment(\.modelContext) private var context

  var body: some View {
    if let ai {
      let state = RecipeMacroEstimates.state(of: recipe)
      if state != .hidden {
        VStack(alignment: .leading, spacing: 8) {
          switch state {
          case .waiting:
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text(verbatim: Copy.editor.divining.text).brandText(.control)
            }
            .foregroundStyle(Brand.Colors.subtext)
            .accessibilityElement(children: .combine)
          case .idle, .failed, .hidden:
            if state == .failed {
              Text(verbatim: Copy.editor.divineFailed.text)
                .brandText(.control)
                .foregroundStyle(Brand.Colors.heat)
            }
            Button {
              Task { await RecipeMacroEstimates.divine(recipe, in: context, using: ai) }
            } label: {
              Text(verbatim: Copy.editor.divineMacros.text)
            }
            .buttonStyle(RecipeActionButtonStyle())
            // A button that fills its width would stretch across a wide window.
            .frame(maxWidth: 320)
          }
          if ai.status.needsAttention {
            AIStatusLine(status: ai.status)
              .brandText(.control)
              .foregroundStyle(Brand.Colors.subtext)
          }
        }
      }
    }
  }
}
