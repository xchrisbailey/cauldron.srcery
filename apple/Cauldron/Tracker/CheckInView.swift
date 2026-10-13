import CauldronKit
import SwiftData
import SwiftUI

/// The weekly check-in: what the body seems to burn, how the trend compares with the goal, and
/// the targets proposed from both, with the ones now beside them. Nothing changes until the cook
/// accepts. The numbers are `CheckInInputs.build`; this only draws them.
struct CheckInView: View {
  private let context: ModelContext
  /// The day it was opened on, from the clock; nil only if the calendar can't say.
  private let today: LocalDate?

  @Environment(\.dismiss) private var dismiss
  @State private var inputs: CheckInInputs?
  @State private var keepOverrides = true
  @State private var failure: CopyString?

  private let t = Copy.tracker.checkIn

  /// Reads what the check-in needs as the view is made, so there is no frame without it. It
  /// takes today from the clock when it opens (never from a screen that has been open past
  /// midnight), so what it checks in is today.
  init(context: ModelContext, today: LocalDate? = TargetsForm.today()) {
    self.context = context
    self.today = today
    _inputs = State(
      initialValue: today.flatMap { try? CheckInInputs.gather(from: context, today: $0) })
  }

  var body: some View {
    Group {
      if let inputs {
        if let check = inputs.build(keepOverrides: keepOverrides), let profile = inputs.profile,
          let targets = inputs.targets
        {
          content(check, inputs: inputs, targets: targets, unit: profile.weightUnit)
        } else {
          message(t.needTargets)
        }
      } else {
        VStack(spacing: 12) {
          Text(verbatim: t.couldntLoad.text)
            .brandText(.body)
            .foregroundStyle(Brand.Colors.subtext)
          Button(t.retry.text) {
            inputs = today.flatMap { try? CheckInInputs.gather(from: context, today: $0) }
          }
          .brandText(.control)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Colors.base)
      }
    }
    .navigationTitle(t.title.text)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  private func message(_ text: CopyString) -> some View {
    Text(verbatim: text.text)
      .brandText(.body)
      .foregroundStyle(Brand.Colors.subtext)
      .multilineTextAlignment(.center)
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Brand.Colors.base)
  }

  private func content(
    _ check: CheckIn, inputs: CheckInInputs, targets: Targets, unit: WeightUnit
  ) -> some View {
    let estimate = check.estimate
    let thin =
      estimate.measured == nil ? t.thin.text : estimate.confidence < 0.5 ? t.leans.text : nil
    return Form {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: MacroMeter.whole(estimate.expenditure))
              .font(.brand(.quantity, size: 32))
              .fontWeight(.semibold)
            Text(verbatim: t.perDay.text).brandText(.unit)
          }
          Text(
            verbatim: t.basedOn(estimate.loggedDays, estimate.weighIns, check.weeks).text
              + (thin.map { " \($0)" } ?? "")
          )
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
        }
        .accessibilityElement(children: .combine)
        .listRowBackground(Brand.Colors.mantle)
      } header: {
        Text(verbatim: t.expenditure.text)
      }

      Section {
        HStack(alignment: .top) {
          fact(t.expected.text, perWeek(check.proposal.expectedWeeklyChangeKg, unit))
          fact(
            t.actual.text,
            check.proposal.actualWeeklyChangeKg.map { perWeek($0, unit) } ?? t.noTrend.text)
        }
        .listRowBackground(Brand.Colors.mantle)
      } header: {
        Text(verbatim: t.progress.text)
      }

      Section {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 10) {
          GridRow {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            Text(verbatim: t.now.text).brandText(.control).foregroundStyle(Brand.Colors.subtext)
            Text(verbatim: t.proposed.text).brandText(.control).foregroundStyle(
              Brand.Colors.subtext)
          }
          ForEach(MacroKey.allCases, id: \.self) { key in
            let meter = MacroMeter(key: key, eaten: 0, target: nil)
            GridRow {
              HStack(spacing: 8) {
                Circle().fill(key.tint).frame(width: 8, height: 8).opacity(key == .calories ? 0 : 1)
                  .accessibilityHidden(true)
                Text(verbatim: meter.name.text).brandText(.body)
              }
              .gridColumnAlignment(.leading)
              Text(verbatim: "\(MacroMeter.whole(current(key, targets))) \(meter.unit.text)")
                .brandText(.quantity)
                .foregroundStyle(Brand.Colors.subtext)
              Text(
                verbatim:
                  "\(MacroMeter.whole(proposed(key, check))) \(meter.unit.text)"
              )
              .font(.brand(.quantity, size: 14))
              .fontWeight(.semibold)
            }
          }
        }
        .listRowBackground(Brand.Colors.mantle)
        if check.proposal.floored {
          note(t.floored.text)
        }
        if check.isUnchanged(from: targets) {
          note(t.unchanged.text)
        }
      } header: {
        Text(verbatim: t.targets.text)
      }

      if inputs.hasHandSetTargets {
        Section {
          Toggle(isOn: $keepOverrides) {
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: t.keepHandSet.text).brandText(.body)
              Text(verbatim: t.keepHandSetHint.text)
                .brandText(.control)
                .foregroundStyle(Brand.Colors.subtext)
            }
          }
          .listRowBackground(Brand.Colors.mantle)
        }
      }

      if let failure {
        Section {
          Text(verbatim: failure.text)
            .brandText(.body)
            .foregroundStyle(Brand.Colors.heat)
            .listRowBackground(Brand.Colors.mantle)
        }
      }

      Section {
        HStack {
          Button(action: { finish(accepting: check) }) {
            Text(verbatim: t.accept.text).foregroundStyle(Brand.Colors.base)
          }
          .buttonStyle(.borderedProminent)
          .tint(Brand.Colors.magic)
          Button(t.notNow.text) { finish(accepting: nil) }
            .buttonStyle(.bordered)
        }
        .brandText(.control)
        .listRowBackground(Color.clear)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .readingColumn(maxWidth: ReadingColumn.form)
    .background(Brand.Colors.base)
  }

  private func fact(_ term: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: term).brandText(.control).foregroundStyle(Brand.Colors.subtext)
      Text(monoNumbers(value, size: 15)).brandText(.body)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func note(_ text: String) -> some View {
    Text(verbatim: text)
      .brandText(.control)
      .foregroundStyle(Brand.Colors.subtext)
      .listRowBackground(Brand.Colors.mantle)
  }

  /// A signed weekly change in the cook's unit, "−0.5 kg a week".
  private func perWeek(_ kg: Double, _ unit: WeightUnit) -> String {
    t.perWeek(
      WeightText.signedChange(deltaKg: kg, unit: unit), Copy.tracker.targets.weightUnits[unit].text
    ).text
  }

  private func current(_ key: MacroKey, _ targets: Targets) -> Double {
    switch key {
    case .calories: Double(targets.calories)
    case .protein: Double(targets.protein)
    case .carbs: Double(targets.carbs)
    case .fat: Double(targets.fat)
    }
  }

  private func proposed(_ key: MacroKey, _ check: CheckIn) -> Double {
    let targets = check.proposal.targets
    return switch key {
    case .calories: Double(targets.calories)
    case .protein: Double(targets.protein)
    case .carbs: Double(targets.carbs)
    case .fat: Double(targets.fat)
    }
  }

  /// Accepts the proposal, or with nil leaves the targets be; either way it is checked in.
  private func finish(accepting check: CheckIn?) {
    guard let today else { return }
    do {
      if let check {
        try CheckInWrites.accept(check, keepOverrides: keepOverrides, today: today, in: context)
      } else {
        try CheckInWrites.dismiss(today: today, in: context)
      }
      dismiss()
    } catch {
      failure = t.couldntSave
    }
  }
}

/// A gentle line on today's diary when a check-in is due.
struct CheckInPrompt: View {
  let context: ModelContext

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: Copy.tracker.checkIn.banner.text)
        .brandText(.control)
        .foregroundStyle(Brand.Colors.subtext)
      NavigationLink {
        CheckInView(context: context)
      } label: {
        Text(verbatim: Copy.tracker.checkIn.bannerAction.text).brandText(.control)
      }
    }
    .accessibilityElement(children: .contain)
  }
}
