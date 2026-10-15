import CauldronKit
import SwiftUI

/// How the parser read one ingredient line, with a Fix control that opens fields to correct it
/// (`Reading` in the web editor's `IngredientRows.tsx`). Retyping the line reads it again.
struct IngredientFixView: View {
  @Binding var draft: RecipeDraft
  let row: IngredientRowDraft
  let open: Bool
  let toggle: () -> Void

  var body: some View {
    if let reading = row.reading {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 8) {
          ReadingView(reading: reading, showsEmpty: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button(action: toggle) {
            Text(verbatim: Copy.editor.fix.text)
          }
          .buttonStyle(.borderless)
          .brandText(.control)
          .tint(Brand.Colors.magic)
          .accessibilityLabel(Text(verbatim: Copy.editor.fixLine(row.text).text))
          .accessibilityAddTraits(open ? .isSelected : [])
        }
        if open { IngredientFixFields(draft: $draft, rowID: row.id) }
      }
    }
  }
}

/// The fields that change a reading: amount, unit, ingredient, note and whether it's optional,
/// and a way back to what the parser made of the line.
private struct IngredientFixFields: View {
  @Binding var draft: RecipeDraft
  let rowID: UUID
  /// What is typed in the amount field, which can hold something that isn't an amount yet.
  @State private var quantityText: String
  @State private var quantityInvalid = false

  init(draft: Binding<RecipeDraft>, rowID: UUID) {
    _draft = draft
    self.rowID = rowID
    let parsed = draft.wrappedValue.ingredients.first { $0.id == rowID }?.parsed
    _quantityText = State(
      initialValue: parsed?.quantity.map { quantityEntryText($0, unit: parsed?.unit) } ?? "")
  }

  private var row: IngredientRowDraft? { draft.ingredients.first { $0.id == rowID } }
  private var parsed: ParsedIngredient? { row?.parsed }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      FlowLayout(spacing: 10) {
        field(Copy.editor.quantity) {
          TextField("", text: quantityBinding)
            .brandText(.quantity)
            #if os(iOS)
              .keyboardType(.numbersAndPunctuation)
            #endif
            .autocorrectionDisabled()
            .frame(width: 90)
        }
        field(Copy.editor.unit) {
          Picker(selection: unitBinding) {
            Text(verbatim: Copy.editor.noUnit.text).tag(UnitCode?.none)
            ForEach(UnitCode.allCases, id: \.self) { code in
              Text(verbatim: code.editorLabel).tag(UnitCode?.some(code))
            }
          } label: {
            Text(verbatim: Copy.editor.unit.text)
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .tint(Brand.Colors.magic)
          .frame(width: 130, alignment: .leading)
        }
        field(Copy.editor.item) {
          TextField("", text: itemBinding)
            .brandText(.body)
            .frame(width: 170)
        }
        field(Copy.editor.note) {
          TextField("", text: noteBinding)
            .brandText(.body)
            .frame(width: 170)
        }
      }
      if quantityInvalid {
        Text(verbatim: Copy.editor.badQuantity.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.heat)
      }
      HStack {
        Toggle(isOn: optionalBinding) {
          Text(verbatim: Copy.editor.optional.text).brandText(.control)
        }
        .tint(Brand.Colors.magic)
        .fixedSize()
        Spacer(minLength: 8)
        if row?.corrected == true {
          Button {
            draft.resetIngredient(rowID)
            quantityInvalid = false
            quantityText =
              parsed?.quantity.map { quantityEntryText($0, unit: parsed?.unit) } ?? ""
          } label: {
            Text(verbatim: Copy.editor.resetLine.text)
          }
          .buttonStyle(.borderless)
          .brandText(.control)
          .tint(Brand.Colors.magic)
        }
      }
    }
    .padding(10)
    .background(Brand.Colors.crust, in: RoundedRectangle(cornerRadius: 10))
  }

  /// A labelled box for one field, drawn on `surface0`.
  private func field<Content: View>(_ label: CopyString, @ViewBuilder _ content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: label.text)
        .brandText(.control)
        .foregroundStyle(Brand.Colors.subtext)
      content()
        .textFieldStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Brand.Colors.surface0, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(Text(verbatim: label.text))
    }
  }

  private var quantityBinding: Binding<String> {
    Binding(
      get: { quantityText },
      set: { text in
        quantityText = text
        quantityInvalid = !draft.setIngredientQuantity(rowID, from: text)
      })
  }

  private var unitBinding: Binding<UnitCode?> {
    Binding(
      get: { parsed?.unit },
      set: { draft.setIngredientUnit(rowID, $0) })
  }

  private var itemBinding: Binding<String> {
    Binding(
      get: { parsed?.item ?? "" },
      set: { draft.setIngredientItem(rowID, $0) })
  }

  private var noteBinding: Binding<String> {
    Binding(
      get: { parsed?.note ?? "" },
      set: { draft.setIngredientNote(rowID, $0) })
  }

  private var optionalBinding: Binding<Bool> {
    Binding(
      get: { parsed?.optional ?? false },
      set: { draft.setIngredientOptional(rowID, $0) })
  }
}
