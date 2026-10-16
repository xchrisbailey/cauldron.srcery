import CauldronImports
import CauldronKit
import SwiftData
import SwiftUI

/// The add sheet's "Describe" way in (#179): say what you ate, and the model splits it into foods
/// with numbers to check before they are logged. When the model can't be reached the description
/// is saved as a waiting entry instead. The rules are in `DescribeModel`.
struct AddDescribeTab: View {
  nonisolated static let isAvailable = true

  let context: AddContext
  /// Closes the sheet, from the waiting state's button.
  let onClose: () -> Void

  @Environment(RecipeAIService.self) private var ai
  @Environment(\.modelContext) private var modelContext
  @State private var model: DescribeModel

  init(context: AddContext, onClose: @escaping () -> Void) {
    self.init(
      context: context, onClose: onClose,
      model: DescribeModel(day: context.day, slot: context.slot))
  }

  /// With a model already in some state, for previews and tests.
  init(context: AddContext, onClose: @escaping () -> Void, model: DescribeModel) {
    self.context = context
    self.onClose = onClose
    _model = State(initialValue: model)
  }

  private let describe = Copy.tracker.describe

  var body: some View {
    Group {
      switch model.phase {
      case .writing, .asking: writing
      case .reviewing: reviewing
      case .waiting: waiting
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .onDisappear { model.cancel() }
  }

  // MARK: Writing

  private var writing: some View {
    let asking = model.phase == .asking
    return Form {
      Section {
        TextField(
          describe.label.text, text: $model.text,
          prompt: Text(verbatim: describe.placeholder.text), axis: .vertical
        )
        .lineLimit(3...8)
        .brandText(.body)
        .disabled(asking)
        .listRowBackground(Brand.Colors.mantle)
        FieldError(model.lengthError)
      } header: {
        Text(verbatim: describe.heading.text)
      } footer: {
        Text(verbatim: describe.hint.text)
      }
      if ai.status.needsAttention {
        Section {
          AIStatusLine(status: ai.status)
        }
        .listRowBackground(Brand.Colors.mantle)
      }
      failureSection
      Section {
        HStack {
          Spacer()
          Button {
            model.startDivining(using: ai, in: modelContext)
          } label: {
            // `base` reads on the brand colour in both appearances.
            Text(verbatim: (asking ? describe.divining : describe.divine).text)
              .foregroundStyle(Brand.Colors.base)
          }
          .buttonStyle(.brandProminent)
          .tint(Brand.Colors.magic)
          .brandText(.control)
          .disabled(asking)
        }
        .listRowBackground(Color.clear)
      }
    }
  }

  // MARK: Reviewing

  private var reviewing: some View {
    Form {
      Section {
        Text(verbatim: describe.review.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
          .listRowBackground(Color.clear)
      }
      if model.rows.isEmpty {
        Section {
          Text(verbatim: describe.nothingLeft.text)
            .brandText(.body)
            .foregroundStyle(Brand.Colors.subtext)
        }
        .listRowBackground(Color.clear)
      }
      ForEach($model.rows) { $row in
        FoodRow(
          row: $row, errors: model.errors(for: row), onRemove: { model.remove(row) })
      }
      Section {
        totalLine
      }
      .listRowBackground(Brand.Colors.mantle)
      failureSection
      Section {
        HStack {
          Button(describe.startOver.text) { model.startOver() }
            .brandText(.control)
          Spacer()
          Button {
            model.log(through: context)
          } label: {
            Text(verbatim: describe.log(model.rows.count).text)
              .foregroundStyle(Brand.Colors.base)
          }
          .buttonStyle(.brandProminent)
          .tint(Brand.Colors.magic)
          .brandText(.control)
          .disabled(model.rows.isEmpty)
        }
        .buttonStyle(.borderless)
        .listRowBackground(Color.clear)
      }
    }
  }

  private var totalLine: some View {
    let totals = model.totals
    let macros = Copy.tracker.macros
    let grams = macros.grams.text
    return VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: describe.total.text).brandText(.body)
      Text(
        verbatim: [
          "\(MacroMeter.whole(totals.calories)) \(macros.calories.text)",
          "\(MacroMeter.whole(totals.protein))\(grams) \(macros.protein.text)",
          "\(MacroMeter.whole(totals.carbs))\(grams) \(macros.carbs.text)",
          "\(MacroMeter.whole(totals.fat))\(grams) \(macros.fat.text)",
        ].joined(separator: " · ")
      )
      .brandText(.quantity)
      Text(verbatim: Copy.tracker.diary.estimate.text)
        .brandText(.unit)
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: Waiting

  private var waiting: some View {
    Form {
      Section {
        Label {
          Text(verbatim: Copy.describeNative.waitingSheet.text).brandText(.body)
        } icon: {
          Image(systemName: "clock").foregroundStyle(Brand.Colors.magic)
        }
        if ai.status.needsAttention {
          AIStatusLine(status: ai.status)
        }
      }
      .listRowBackground(Brand.Colors.mantle)
      Section {
        HStack {
          Spacer()
          Button(action: onClose) {
            Text(verbatim: Copy.ui.close.text).foregroundStyle(Brand.Colors.base)
          }
          .buttonStyle(.brandProminent)
          .tint(Brand.Colors.magic)
          .brandText(.control)
        }
        .listRowBackground(Color.clear)
      }
    }
  }

  @ViewBuilder
  private var failureSection: some View {
    if let failure = model.failure {
      Section {
        Text(verbatim: failure.text)
          .brandText(.body)
          .foregroundStyle(Brand.Colors.heat)
          .listRowBackground(Brand.Colors.mantle)
      }
    }
  }
}

/// One food the model found: its name and amount, the four numbers for that amount, and a way to
/// drop it.
private struct FoodRow: View {
  @Binding var row: DescribeModel.Row
  let errors: [EntryDraft.Field: CopyString]
  let onRemove: () -> Void

  private let entry = Copy.tracker.entry

  var body: some View {
    Section {
      HStack {
        TextField(
          entry.name.text, text: $row.draft.name,
          prompt: Text(verbatim: entry.namePlaceholder.text)
        )
        .brandText(.body)
        Button(action: onRemove) {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(Brand.Colors.overlay1)
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Copy.tracker.describe.remove(row.draft.name).text)
      }
      .listRowBackground(Brand.Colors.mantle)
      FieldError(errors[.name])
      TextField(
        entry.amount.text, text: $row.draft.amount,
        prompt: Text(verbatim: entry.amountPlaceholder.text)
      )
      .brandText(.quantity)
      .listRowBackground(Brand.Colors.mantle)
      FieldError(errors[.amount])
      if row.hasNoNumbers {
        Text(verbatim: Copy.tracker.describe.notFood.text)
          .brandText(.control)
          .italic()
          .foregroundStyle(Brand.Colors.subtext)
          .listRowBackground(Brand.Colors.mantle)
      }
      HStack(alignment: .top, spacing: 8) {
        ForEach(MacroKey.allCases, id: \.self) { key in
          VStack(spacing: 2) {
            TextField(
              MacroMeter(key: key, eaten: 0, target: nil).name.text,
              text: $row.draft[macro: key], prompt: Text(verbatim: "0")
            )
            .labelsHidden()
            .multilineTextAlignment(.center)
            .brandText(.quantity)
            #if os(iOS)
              .keyboardType(key == .calories ? .numberPad : .decimalPad)
            #endif
            HStack(spacing: 3) {
              Circle().fill(key.tint).frame(width: 6, height: 6)
                .opacity(key == .calories ? 0 : 1)
                .accessibilityHidden(true)
              Text(verbatim: MacroMeter(key: key, eaten: 0, target: nil).unit.text)
                .brandText(.unit)
            }
          }
          .frame(maxWidth: .infinity)
        }
      }
      .listRowBackground(Brand.Colors.mantle)
      ForEach(MacroKey.allCases, id: \.self) { key in
        FieldError(errors[.macro(key)])
      }
    }
  }
}
