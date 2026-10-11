import CauldronKit
import SwiftData
import SwiftUI

/// One step to log or change a weigh-in: a number in the cook's unit, and with `pickDay` the day
/// as well (for a past one). Saving a day that has a weigh-in changes it.
struct WeightEntrySheet: View {
  let day: LocalDate
  let today: LocalDate
  let unit: WeightUnit
  /// What is logged for the day now, if anything.
  let existing: WeighInRecord?
  let pickDay: Bool
  let onClose: () -> Void

  @Environment(\.modelContext) private var context
  @State private var text: String
  @State private var chosenDay: LocalDate
  @State private var error: CopyString?

  private let t = Copy.tracker.weight

  init(
    day: LocalDate, today: LocalDate, unit: WeightUnit, existing: WeighInRecord?, pickDay: Bool,
    onClose: @escaping () -> Void
  ) {
    self.day = day
    self.today = today
    self.unit = unit
    self.existing = existing
    self.pickDay = pickDay
    self.onClose = onClose
    _text = State(
      initialValue: existing.map { showWeight($0.weightKg, unit: unit) } ?? "")
    _chosenDay = State(initialValue: day)
  }

  var body: some View {
    NavigationStack {
      Form {
        if pickDay {
          Section {
            DatePicker(
              selection: dayBinding, in: ...(today.date(in: .current) ?? .now),
              displayedComponents: .date
            ) {
              Text(verbatim: t.day.text)
            }
            .brandText(.quantity)
            .listRowBackground(Brand.Colors.mantle)
          }
        }
        Section {
          HStack {
            TextField(t.label(unit.rawValue).text, text: $text)
              .labelsHidden()
              .multilineTextAlignment(.trailing)
              .brandText(.quantity)
              #if os(iOS)
                .keyboardType(.decimalPad)
              #endif
            Text(verbatim: Copy.tracker.targets.weightUnits[unit].text).brandText(.unit)
          }
          .listRowBackground(Brand.Colors.mantle)
          FieldError(error)
        } header: {
          Text(verbatim: t.label(Copy.tracker.targets.weightUnits[unit].text).text)
        }
        if existing != nil {
          Section {
            Button(role: .destructive, action: remove) {
              Text(verbatim: t.remove.text).brandText(.body)
            }
            .listRowBackground(Brand.Colors.mantle)
          }
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
      .navigationTitle(pickDay ? t.logTitle.text : t.logFor(chosenDay.description).text)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t.cancel.text, action: onClose)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t.save.text, action: save)
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 380, minHeight: 280)
    #endif
  }

  private var dayBinding: Binding<Date> {
    Binding(
      get: { chosenDay.date(in: .current) ?? .now },
      set: { chosenDay = LocalDate($0, in: .current) ?? chosenDay })
  }

  private func save() {
    guard chosenDay <= today else {
      error = t.needDay
      return
    }
    guard let kg = WeightText.parse(text, unit: unit) else {
      let limits = WeightText.limits(unit: unit)
      error = t.outOfRange(
        showNumber(limits.min), showNumber(limits.max), Copy.tracker.targets.weightUnits[unit].text)
      return
    }
    do {
      try WeightWrites.save(kg: kg, on: chosenDay, today: today, in: context)
      onClose()
    } catch {
      self.error = t.couldntSave
    }
  }

  private func remove() {
    do {
      if let sample = try WeightWrites.remove(day: chosenDay, in: context) {
        HealthSync.shared.dismiss(sampleID: sample)
      }
      onClose()
    } catch {
      self.error = t.couldntRemove
    }
  }
}
