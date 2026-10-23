import CauldronKit
import SwiftData
import SwiftUI

/// Set your targets: body details, activity and a goal go in, daily calories and macros come
/// out with the reasoning shown, and any of them can be typed over by hand. Three short steps
/// the first time; with a profile it opens on the targets, the profile an editable summary.
/// The logic is `TargetsForm`; this draws it and saves it.
struct TargetsView: View {
  private let context: ModelContext
  /// Called after the targets are saved.
  private let onSaved: () -> Void

  @State private var form: TargetsForm?
  @State private var saveError: CopyString?

  /// Reads the saved details as the view is made, so there is no frame without them (and no
  /// state change after the first draw, which a view drawn off screen can't take).
  init(context: ModelContext, onSaved: @escaping () -> Void = {}) {
    self.context = context
    self.onSaved = onSaved
    let loaded = Self.load(from: context)
    _form = State(initialValue: loaded)
  }

  var body: some View {
    Group {
      if let form {
        TargetsEditor(
          form: Binding(get: { form }, set: { self.form = $0 }), saveError: saveError, save: save)
      } else {
        VStack(spacing: 12) {
          Text(verbatim: Copy.tracker.targets.couldntLoad.text)
            .brandText(.body)
            .foregroundStyle(Brand.Colors.subtext)
          Button(Copy.ui.tryAgain.text) {
            form = Self.load(from: context)
          }
          .brandText(.control)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Colors.base)
      }
    }
    .navigationTitle(Copy.tracker.targets.title.text)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  private static func load(from context: ModelContext) -> TargetsForm? {
    guard let today = TargetsForm.today() else { return nil }
    return try? TargetsForm.load(from: context, today: today)
  }

  private func save() {
    guard let form else { return }
    do {
      try form.save(in: context)
      saveError = nil
      onSaved()
    } catch is TargetsForm.Invalid {
      saveError = Copy.tracker.targets.fixThese
    } catch {
      saveError = Copy.tracker.targets.couldntSave
    }
  }
}

/// The steps and their controls. `TargetsView` loads the form and saves it; tests draw this.
struct TargetsEditor: View {
  @Binding var form: TargetsForm
  let saveError: CopyString?
  let save: () -> Void

  @State private var step: Int
  @State private var attempted = false
  @FocusState private var headingFocused: Bool

  private static let steps = 3
  private let t = Copy.tracker.targets

  init(
    form: Binding<TargetsForm>, saveError: CopyString?, step: Int? = nil,
    save: @escaping () -> Void
  ) {
    _form = form
    self.saveError = saveError
    self.save = save
    _step = State(initialValue: step ?? (form.wrappedValue.startsOnTargets ? 2 : 0))
  }

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: t.step(step + 1, Self.steps).text)
            .brandText(.unit)
          Text(verbatim: [t.steps.about, t.steps.activity, t.steps.targets][step].text)
            .brandText(.section)
            .accessibilityAddTraits(.isHeader)
        }
        .listRowBackground(Color.clear)
      }

      switch step {
      case 0: AboutStep(form: $form, errors: attempted ? form.aboutErrors() : [:])
      case 1: ActivityStep(form: $form)
      default: TargetsStep(form: $form, attempted: attempted, goTo: goTo)
      }

      if let saveError {
        Section {
          Text(verbatim: saveError.text)
            .brandText(.body)
            .foregroundStyle(Brand.Colors.heat)
            .listRowBackground(Brand.Colors.mantle)
        }
      }

      Section {
        HStack {
          if step > 0 {
            Button(t.back.text) { goTo(step - 1) }
          }
          Spacer()
          if step < Self.steps - 1 {
            Button(t.continue.text, action: next)
              .buttonStyle(.brandProminent)
              .accessibilityIdentifier("targets.continue")
          } else {
            Button(t.save.text) {
              attempted = true
              save()
            }
            .buttonStyle(.brandProminent)
            .accessibilityIdentifier("targets.save")
            .disabled(form.calculation == nil)
          }
        }
        .brandText(.control)
        .tint(Brand.Colors.magic)
        .buttonStyle(.bordered)
        .listRowBackground(Color.clear)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .readingColumn(maxWidth: ReadingColumn.form)
    .background(Brand.Colors.base)
  }

  private func goTo(_ next: Int) {
    attempted = false
    step = next
  }

  private func next() {
    if step == 0 {
      attempted = true
      guard form.aboutErrors().isEmpty else { return }
    }
    goTo(step + 1)
  }
}

// MARK: Step one: about you

private struct AboutStep: View {
  @Binding var form: TargetsForm
  let errors: [TargetsForm.Field: CopyString]
  private let t = Copy.tracker.targets

  var body: some View {
    Section {
      Picker(selection: $form.sex) {
        ForEach(Sex.allCases, id: \.self) { sex in
          Text(verbatim: t.sexes[sex].text).tag(Sex?.some(sex))
        }
      } label: {
        Text(verbatim: t.sex.text)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("targets.sex")
      .listRowBackground(Brand.Colors.mantle)
      FieldError(errors[.sex])
    } header: {
      Text(verbatim: t.sex.text)
    } footer: {
      Text(verbatim: t.sexHint.text)
    }

    Section {
      DatePicker(
        selection: birthDate, in: birthDateRange, displayedComponents: .date
      ) {
        Text(verbatim: t.birthDate.text)
      }
      .brandText(.body)
      .accessibilityIdentifier("targets.birthDate")
      .opacity(form.birthDate == nil ? 0.55 : 1)
      .listRowBackground(Brand.Colors.mantle)
      FieldError(errors[.birthDate])
    }

    Section {
      Picker(selection: heightUnit) {
        ForEach(HeightUnit.allCases, id: \.self) { unit in
          Text(verbatim: t.heightUnits[unit].text).tag(unit)
        }
      } label: {
        Text(verbatim: t.unitSwitch(t.height.text).text)
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .listRowBackground(Brand.Colors.mantle)

      switch form.heightUnit {
      case .cm:
        NumberField(label: t.height.text, unit: t.heightUnits.cm.text, text: $form.cm)
      case .ftin:
        NumberField(label: t.feet.text, unit: t.feet.text, text: $form.feet, decimal: false)
        NumberField(label: t.inches.text, unit: t.inches.text, text: $form.inches)
      }
      FieldError(errors[.height])
    } header: {
      Text(verbatim: t.height.text)
    }

    Section {
      Picker(selection: weightUnit) {
        ForEach(WeightUnit.allCases, id: \.self) { unit in
          Text(verbatim: t.weightUnits[unit].text).tag(unit)
        }
      } label: {
        Text(verbatim: t.unitSwitch(t.weight.text).text)
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .listRowBackground(Brand.Colors.mantle)

      NumberField(
        label: t.weight.text, unit: t.weightUnits[form.weightUnit].text, text: $form.weight)
      FieldError(errors[.weight])
    } header: {
      Text(verbatim: t.weight.text)
    }
  }

  private var birthDateRange: ClosedRange<Date> {
    let calendar = Calendar.current
    let earliest =
      calendar.date(from: DateComponents(year: TargetsForm.earliestBirthYear)) ?? .distantPast
    let latest = form.today.date(in: calendar) ?? .now
    return earliest...latest
  }

  /// Until one is chosen the picker rests on a day thirty years back, dimmed.
  private var birthDate: Binding<Date> {
    Binding(
      get: {
        let calendar = Calendar.current
        return (form.birthDate ?? form.today.adding(days: -365 * 30)).date(in: calendar) ?? .now
      },
      set: { form.birthDate = LocalDate($0, in: .current) })
  }

  private var heightUnit: Binding<HeightUnit> {
    Binding(get: { form.heightUnit }, set: { form.switchHeightUnit(to: $0) })
  }

  private var weightUnit: Binding<WeightUnit> {
    Binding(get: { form.weightUnit }, set: { form.switchWeightUnit(to: $0) })
  }
}

// MARK: Step two: activity and goal

private struct ActivityStep: View {
  @Binding var form: TargetsForm
  private let t = Copy.tracker.targets

  var body: some View {
    Section {
      ForEach(ActivityLevel.allCases, id: \.self) { level in
        Button {
          form.activity = level
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: t.activityLevels[level].label.text)
                .brandText(.body)
              Text(verbatim: t.activityLevels[level].hint.text)
                .brandText(.control)
                .foregroundStyle(Brand.Colors.subtext)
            }
            Spacer()
            if form.activity == level {
              Image(systemName: "checkmark")
                .foregroundStyle(Brand.Colors.magic)
                .accessibilityHidden(true)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(form.activity == level ? .isSelected : [])
        .listRowBackground(Brand.Colors.mantle)
      }
    } header: {
      Text(verbatim: t.activity.text)
    }

    Section {
      Picker(selection: goal) {
        ForEach(Goal.allCases, id: \.self) { goal in
          Text(verbatim: t.goals[goal].text).tag(goal)
        }
      } label: {
        Text(verbatim: t.goal.text)
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .listRowBackground(Brand.Colors.mantle)
    } header: {
      Text(verbatim: t.goal.text)
    }

    let choices = rateChoices(goal: form.goal, unit: form.weightUnit)
    if !choices.isEmpty {
      Section {
        Picker(selection: $form.rate) {
          ForEach(choices, id: \.amount) { choice in
            Text(
              verbatim: t.perWeek(
                showNumber(choice.amount, digits: 2), t.weightUnits[form.weightUnit].text
              ).text
            )
            .tag(Double?.some(choice.amount))
          }
        } label: {
          Text(verbatim: t.rate.text)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .listRowBackground(Brand.Colors.mantle)
      } header: {
        Text(verbatim: t.rate.text)
      }
    }
  }

  private var goal: Binding<Goal> {
    Binding(get: { form.goal }, set: { form.choose(goal: $0) })
  }
}

// MARK: Step three: your targets

private struct TargetsStep: View {
  @Binding var form: TargetsForm
  let attempted: Bool
  let goTo: (Int) -> Void
  @State private var adjustOpen = false
  private let t = Copy.tracker.targets

  var body: some View {
    if let calculation = form.calculation, let resolved = form.resolved {
      let targetErrors = attempted ? form.targetErrors() : [:]
      let adjustErrors = attempted ? form.adjustErrors() : [:]
      summary
      reasoning(calculation)
      Section {
        ForEach(TargetKey.allCases, id: \.self) { key in
          TargetRow(
            key: key, form: $form, resolved: resolved, error: targetErrors[.target(key)])
        }
      } header: {
        Text(verbatim: t.steps.targets.text)
      }
      Section {
        DisclosureGroup(
          t.adjust.text,
          isExpanded: Binding(
            get: { adjustOpen || !adjustErrors.isEmpty }, set: { adjustOpen = $0 })
        ) {
          NumberField(label: t.proteinPerKg.text, unit: nil, text: $form.proteinPerKg)
          FieldError(adjustErrors[.proteinPerKg])
          NumberField(
            label: t.fatShare.text, unit: nil, text: $form.fatPercent, decimal: false)
          FieldError(adjustErrors[.fatPercent])
        }
        .brandText(.control)
        .listRowBackground(Brand.Colors.mantle)
      }
    } else {
      Section {
        Text(verbatim: t.fixThese.text)
          .brandText(.body)
          .foregroundStyle(Brand.Colors.heat)
          .listRowBackground(Brand.Colors.mantle)
      }
    }
  }

  private var summary: some View {
    Section {
      SummaryRow(label: t.steps.about.text, value: aboutSummary) { goTo(0) }
      SummaryRow(label: t.steps.activity.text, value: lifestyleSummary) { goTo(1) }
    }
  }

  private var weightUnitText: String { t.weightUnits[form.weightUnit].text }

  private var rateText: String { showNumber(form.rate ?? 0, digits: 2) }

  private var aboutSummary: String {
    let height =
      form.heightUnit == .cm
      ? "\(showNumber(form.heightCm ?? 0)) \(t.heightUnits.cm.text)"
      : "\(form.feet) \(t.feet.text) \(form.inches.isEmpty ? "0" : form.inches) \(t.inches.text)"
    let age = form.birthDate.map { ageOn(birthDate: $0, today: form.today) } ?? 0
    return [
      form.sex.map { t.sexes[$0].text } ?? "", t.summaryAge(age).text, height,
      "\(form.weight) \(weightUnitText)",
    ].joined(separator: " · ")
  }

  private var lifestyleSummary: String {
    [
      t.activityLevels[form.activity].label.text,
      form.goal == .maintain
        ? t.goals.maintain.text
        : "\(t.goals[form.goal].text), \(t.perWeek(rateText, weightUnitText).text)",
    ].joined(separator: " · ")
  }

  private func reasoning(_ calculation: CalculatorResult) -> some View {
    let adjustment = abs(calculation.dailyAdjustment)
    var lines = [
      t.breakdown(
        whole(calculation.restingEnergy), showNumber(form.activity.multiplier, digits: 3),
        whole(calculation.expenditure)
      ).text
    ]
    if adjustment >= 1 {
      lines.append(
        calculation.dailyAdjustment < 0
          ? t.adjustLose(whole(adjustment)).text : t.adjustGain(whole(adjustment)).text)
    }
    if calculation.floored {
      lines.append(t.floor(whole(Double(calculation.targets.calories))).text)
    }
    return Section {
      VStack(alignment: .leading, spacing: 6) {
        Text(
          monoNumbers(
            t.headline(
              form.goal, whole(Double(calculation.targets.calories)), rateText, weightUnitText
            ).text, size: 17)
        )
        .brandText(.section)
        Text(monoNumbers(lines.joined(separator: " "), size: 13))
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
      }
      .accessibilityElement(children: .combine)
      .listRowBackground(Brand.Colors.mantle)
    }
  }
}

private struct SummaryRow: View {
  let label: String
  let value: String
  let edit: () -> Void

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: label)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.overlay1)
        Text(monoNumbers(value, size: 14))
          .brandText(.control)
      }
      Spacer()
      Button(Copy.tracker.targets.edit.text, action: edit)
        .brandText(.control)
        .accessibilityLabel("\(Copy.tracker.targets.edit.text): \(label)")
    }
    .listRowBackground(Brand.Colors.mantle)
  }
}

private struct TargetRow: View {
  let key: TargetKey
  @Binding var form: TargetsForm
  let resolved: TargetsForm.Resolved
  let error: CopyString?
  private let t = Copy.tracker.targets

  private var label: String {
    switch key {
    case .calories: t.macroLabels.calories.text
    case .protein: t.macroLabels.protein.text
    case .carbs: t.macroLabels.carbs.text
    case .fat: t.macroLabels.fat.text
    }
  }

  private var dot: Color {
    switch key {
    case .calories: Brand.Colors.magic
    case .protein: Brand.Colors.trackerBlue
    case .carbs: Brand.Colors.trackerTeal
    case .fat: Brand.Colors.trackerRed
    }
  }

  private var overridden: Bool { resolved.overridden.contains(key) }

  private var text: Binding<String> {
    Binding(
      get: {
        overridden
          ? form.overrides[key] ?? "" : String(Int((resolved.values[key] ?? 0).rounded()))
      },
      set: { form.overrides[key] = $0 })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true)
        Text(verbatim: label).brandText(.body)
        Spacer()
        TextField(label, text: text)
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          .brandText(.quantity)
          .frame(maxWidth: 104)
          .accessibilityIdentifier("targets.macro.\(key)")
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
        Text(verbatim: key == .calories ? t.unitKcal.text : t.unitGrams.text)
          .brandText(.unit)
      }
      HStack {
        Text(verbatim: overridden ? t.setByYou.text : t.calculated.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
        if overridden {
          Button(t.reset.text) { form.overrides[key] = nil }
            .brandText(.control)
            .accessibilityLabel(t.resetLabel(label.lowercased()).text)
        }
      }
      FieldError(error)
    }
    .listRowBackground(Brand.Colors.mantle)
  }
}

// MARK: Pieces

struct NumberField: View {
  let label: String
  let unit: String?
  @Binding var text: String
  var decimal = true

  var body: some View {
    HStack {
      // A field named by its unit ("ft", "in") shows the unit once, after the number.
      if label != unit {
        Text(verbatim: label).brandText(.body)
        Spacer()
      }
      TextField(label, text: $text, prompt: Text(0, format: .number))
        .multilineTextAlignment(.trailing)
        .brandText(.quantity)
        .frame(maxWidth: label != unit ? 120 : .infinity)
        .accessibilityIdentifier("targets.field.\(label)")
        #if os(iOS)
          .keyboardType(decimal ? .decimalPad : .numberPad)
        #endif
      if let unit {
        Text(verbatim: unit).brandText(.unit)
      }
    }
    .listRowBackground(Brand.Colors.mantle)
  }
}

struct FieldError: View {
  let message: CopyString?

  init(_ message: CopyString?) {
    self.message = message
  }

  var body: some View {
    if let message {
      Text(verbatim: message.text)
        .brandText(.control)
        .foregroundStyle(Brand.Colors.heat)
        .listRowBackground(Brand.Colors.mantle)
    }
  }
}

/// Whole number with thousands separators, for the reasoning.
private func whole(_ value: Double) -> String {
  Int(value.rounded()).formatted()
}

/// A sentence with its numbers set in Geist Mono.
func monoNumbers(_ text: String, size: CGFloat) -> AttributedString {
  var result = AttributedString(text)
  for range in text.ranges(of: /\d[\d,.]*/) {
    if let attributed = Range(range, in: result) {
      result[attributed].font = .brand(.quantity, size: size)
    }
  }
  return result
}
