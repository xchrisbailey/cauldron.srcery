import CauldronKit
import SwiftUI

/// Eaten against target for the day: calories large, then protein, carbs and fat, each with a
/// bar and what is left (or how far over). Without targets it points to the set-up.
struct DayHeaderView: View {
  let meters: [MacroMeter]
  let openTargets: () -> Void

  private var hasTargets: Bool { meters.first?.target != nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let calories = meters.first {
        MeterView(meter: calories, big: true)
      }
      HStack(alignment: .top, spacing: 14) {
        ForEach(meters.dropFirst()) { meter in
          MeterView(meter: meter, big: false)
        }
      }
      if !hasTargets {
        VStack(alignment: .leading, spacing: 8) {
          Text(verbatim: Copy.tracker.header.noTargets.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
          Button(Copy.tracker.header.setTargets.text, action: openTargets)
            .brandText(.control)
        }
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Copy.tracker.header.label.text)
  }
}

private struct MeterView: View {
  let meter: MacroMeter
  let big: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        if meter.key != .calories {
          Circle().fill(meter.key.tint).frame(width: 8, height: 8).accessibilityHidden(true)
        }
        Text(verbatim: meter.name.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
        Spacer(minLength: 4)
      }
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(verbatim: meter.eatenText)
          .font(.brand(.quantity, size: big ? 28 : 17))
          .fontWeight(.semibold)
        if let target = meter.targetText {
          Text(verbatim: Copy.display.target(target).text).brandText(.unit)
        }
        Text(verbatim: meter.unit.text).brandText(.unit)
      }
      if meter.target != nil {
        Bar(meter: meter, height: big ? 10 : 6)
        if let left = meter.leftText {
          Text(monoNumbers(left.text, size: 13))
            .brandText(.control)
            .foregroundStyle(meter.isOver ? Brand.Colors.heat : Brand.Colors.subtext)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: String {
    var parts = [meter.name.text, "\(meter.eatenText) \(meter.unit.text)"]
    if let target = meter.targetText { parts.append("\(Copy.tracker.header.of.text) \(target)") }
    if let left = meter.leftText { parts.append(left.text) }
    return parts.joined(separator: ", ")
  }
}

private struct Bar: View {
  let meter: MacroMeter
  let height: CGFloat

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Brand.Colors.surface0)
        Capsule().fill(meter.key.tint)
          .frame(width: proxy.size.width * meter.fill)
        if meter.isOver {
          Capsule().fill(Brand.Colors.heat)
            .frame(width: proxy.size.width * meter.overFill)
        }
      }
    }
    .frame(height: height)
    .accessibilityHidden(true)
  }
}
