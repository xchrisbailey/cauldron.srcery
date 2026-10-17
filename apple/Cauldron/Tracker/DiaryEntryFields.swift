import CauldronKit
import SwiftUI

/// The fields an entry shares between the quick add and the entry sheet: name, amount and the
/// four per-serving numbers, each with its error under it.
struct DiaryEntryFields: View {
  @Binding var draft: EntryDraft
  /// Errors to show, by field; empty until the person has tried to save.
  let errors: [EntryDraft.Field: CopyString]

  private let entry = Copy.tracker.entry

  var body: some View {
    Section {
      TextField(
        entry.name.text, text: $draft.name, prompt: Text(verbatim: entry.namePlaceholder.text)
      )
      .brandText(.body)
      .listRowBackground(Brand.Colors.mantle)
      FieldError(errors[.name])
      TextField(
        entry.amount.text, text: $draft.amount, prompt: Text(verbatim: entry.amountPlaceholder.text)
      )
      .brandText(.quantity)
      .listRowBackground(Brand.Colors.mantle)
      FieldError(errors[.amount])
    }

    Section {
      ForEach(MacroKey.allCases, id: \.self) { key in
        let meter = MacroMeter(key: key, eaten: 0, target: nil)
        HStack {
          Circle().fill(key.tint).frame(width: 8, height: 8).opacity(key == .calories ? 0 : 1)
            .accessibilityHidden(true)
          Text(verbatim: meter.name.text).brandText(.body)
          Spacer()
          TextField(meter.name.text, text: $draft[macro: key], prompt: Text(verbatim: "0"))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .brandText(.quantity)
            #if os(iOS)
              .keyboardType(key == .calories ? .numberPad : .decimalPad)
            #endif
          Text(verbatim: meter.unit.text).brandText(.unit)
        }
        .listRowBackground(Brand.Colors.mantle)
        FieldError(errors[.macro(key)])
      }
    } header: {
      Text(verbatim: entry.perServing.text)
    }
  }
}
