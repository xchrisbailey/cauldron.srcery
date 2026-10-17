import CauldronKit
import SwiftUI
import WidgetKit

/// The macros widget in every size it comes in. It lives in `Shared` so the app's tests can draw
/// it; the widget extension only wraps it in a configuration.
///
/// The colours are the brand's (`Brand.Colors`, from the catalogue both targets compile). The
/// type is the system face, with the monospaced design for every number: WidgetKit draws a
/// widget outside the extension's process, and Geist is registered at runtime there, so the
/// brand fonts aren't used until they are declared in the extension's Info.plist.
struct TodayMacrosWidgetView: View {
  let entry: TodayMacrosEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    TodayMacrosContent(entry: entry, family: family)
  }
}

/// The widget for a given family. The family is a parameter because the environment's is
/// read-only, which a test can't set.
struct TodayMacrosContent: View {
  let entry: TodayMacrosEntry
  let family: WidgetFamily

  var body: some View {
    content
      .widgetURL(AppLink.todayDiary.url)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(TodayMacrosSpeech.label(for: entry.snapshot))
      .containerBackground(for: .widget) { background }
  }

  @ViewBuilder
  private var content: some View {
    if let snapshot = entry.snapshot {
      switch family {
      #if os(iOS)
        case .accessoryCircular: AccessoryCircularMacros(snapshot: snapshot)
        case .accessoryRectangular: AccessoryRectangularMacros(snapshot: snapshot)
      #endif
      case .systemMedium: MediumMacros(snapshot: snapshot)
      default: SmallMacros(snapshot: snapshot)
      }
    } else {
      NoDataView(style: noDataStyle)
    }
  }

  /// The Lock Screen draws its own backing; everything else sits on the brand's page colour.
  @ViewBuilder
  private var background: some View {
    if isAccessory { Color.clear } else { Brand.Colors.base }
  }

  private var noDataStyle: NoDataView.Style {
    #if os(iOS)
      if family == .accessoryCircular { return .icon }
    #endif
    return isAccessory ? .line : .full
  }

  /// The Lock Screen's families, which only an iPhone or iPad has.
  private var isAccessory: Bool {
    #if os(iOS)
      family == .accessoryCircular || family == .accessoryRectangular
        || family == .accessoryInline
    #else
      false
    #endif
  }
}

// MARK: Type

/// The widget's type: the system face, monospaced for numbers.
private enum WidgetType {
  static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }

  static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
    .system(size: size, weight: weight)
  }
}

// MARK: Pieces

private func name(of key: MacroKey) -> String {
  let names = Copy.tracker.macroNames
  switch key {
  case .calories: return names.calories.text
  case .protein: return names.protein.text
  case .carbs: return names.carbs.text
  case .fat: return names.fat.text
  }
}

private func unit(of key: MacroKey) -> String {
  key == .calories ? Copy.tracker.macros.calories.text : Copy.tracker.macros.grams.text
}

/// A ring that fills as the target is reached, and turns `heat` once it is passed. Without a
/// target there is no ring to fill, so nothing is drawn.
private struct MacroRing<Center: View>: View {
  let meter: TodayMacrosMeter
  let lineWidth: CGFloat
  @ViewBuilder let center: Center

  var body: some View {
    ZStack {
      if meter.target != nil {
        Circle().stroke(Brand.Colors.surface1, lineWidth: lineWidth)
        Circle()
          .trim(from: 0, to: meter.fill)
          .stroke(
            meter.isOver ? Brand.Colors.heat : meter.key.tint,
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
          .widgetAccentable()
      }
      center
    }
    .padding(lineWidth / 2)
  }
}

/// "A meal is still being estimated", small, with a clock.
private struct EstimatingNote: View {
  var body: some View {
    Label {
      Text(verbatim: Copy.tracker.widget.estimating.text)
        .font(WidgetType.label(11))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    } icon: {
      Image(systemName: "clock").foregroundStyle(Brand.Colors.magic)
    }
    .foregroundStyle(Brand.Colors.subtext)
    .labelStyle(.titleAndIcon)
  }
}

/// A line of quiet text.
private struct QuietLine: View {
  let text: String
  var size: CGFloat = 11

  var body: some View {
    Text(verbatim: text)
      .font(WidgetType.label(size))
      .foregroundStyle(Brand.Colors.subtext)
      .lineLimit(2)
      .minimumScaleFactor(0.85)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// "320 kcal left" or "45 kcal over".
private func leftText(_ meter: TodayMacrosMeter) -> String? {
  guard let target = meter.target else { return nil }
  let amount = "\(TodayMacrosMeter.whole(abs(Double(target) - meter.eaten))) \(unit(of: meter.key))"
  return meter.isOver
    ? Copy.tracker.header.over(amount).text : Copy.tracker.header.left(amount).text
}

// MARK: Small

private struct SmallMacros: View {
  let snapshot: TodayMacrosSnapshot

  var body: some View {
    let meter = snapshot.meter(.calories)
    VStack(spacing: 6) {
      Text(verbatim: name(of: .calories))
        .font(WidgetType.label(12))
        .foregroundStyle(Brand.Colors.subtext)
        .frame(maxWidth: .infinity, alignment: .leading)
      if meter.target != nil {
        MacroRing(meter: meter, lineWidth: 9) {
          VStack(spacing: 0) {
            Text(verbatim: meter.eatenText)
              .font(WidgetType.number(22))
              .minimumScaleFactor(0.6)
              .lineLimit(1)
            Text(verbatim: unit(of: .calories))
              .font(WidgetType.number(10, weight: .regular))
              .foregroundStyle(Brand.Colors.overlay1)
          }
          .padding(.horizontal, 14)
        }
        .frame(maxHeight: .infinity)
      } else {
        Spacer(minLength: 0)
        VStack(spacing: 0) {
          Text(verbatim: meter.eatenText)
            .font(WidgetType.number(34))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
          Text(verbatim: unit(of: .calories))
            .font(WidgetType.number(12, weight: .regular))
            .foregroundStyle(Brand.Colors.overlay1)
        }
        Spacer(minLength: 0)
      }
      bottomLine(meter)
    }
    .foregroundStyle(Brand.Colors.ink)
  }

  /// A waiting meal means the eaten figure is short, so the note stands in for what is left.
  @ViewBuilder
  private func bottomLine(_ meter: TodayMacrosMeter) -> some View {
    Group {
      if snapshot.hasWaitingEntry {
        EstimatingNote()
      } else if let left = leftText(meter) {
        Text(verbatim: left)
          .font(WidgetType.number(11, weight: .regular))
          .foregroundStyle(meter.isOver ? Brand.Colors.heat : Brand.Colors.subtext)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      } else {
        QuietLine(text: Copy.tracker.widget.noTargets.text)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: Medium

private struct MediumMacros: View {
  let snapshot: TodayMacrosSnapshot

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Text(verbatim: Copy.tracker.diary.today.text)
          .font(WidgetType.label(13, weight: .semibold))
        Spacer(minLength: 8)
        if snapshot.hasWaitingEntry {
          EstimatingNote()
        } else if snapshot.targets == nil {
          QuietLine(text: Copy.tracker.widget.noTargets.text, size: 11)
        }
      }
      HStack(alignment: .top, spacing: 6) {
        ForEach(MacroKey.allCases, id: \.self) { key in
          MacroColumn(meter: snapshot.meter(key))
        }
      }
      .frame(maxHeight: .infinity)
    }
    .foregroundStyle(Brand.Colors.ink)
  }
}

/// One macro in the medium widget: a ring with the eaten figure in it, the name, and the target.
private struct MacroColumn: View {
  let meter: TodayMacrosMeter

  var body: some View {
    VStack(spacing: 4) {
      MacroRing(meter: meter, lineWidth: 6) {
        Text(verbatim: meter.eatenText)
          .font(WidgetType.number(meter.target == nil ? 17 : 15))
          .minimumScaleFactor(0.6)
          .lineLimit(1)
          .padding(.horizontal, 4)
      }
      .frame(maxWidth: 66, maxHeight: 66)
      Text(verbatim: name(of: meter.key))
        .font(WidgetType.label(11))
        .foregroundStyle(Brand.Colors.subtext)
        .lineLimit(1)
      Text(verbatim: figure)
        .font(WidgetType.number(10, weight: .regular))
        .foregroundStyle(meter.isOver ? Brand.Colors.heat : Brand.Colors.overlay1)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity)
  }

  /// The target, `/ 2000`, or the unit when there is no target to show.
  private var figure: String {
    let suffix = meter.key == .calories ? "" : unit(of: meter.key)
    return meter.targetText.map { "/ \($0)\(suffix)" } ?? unit(of: meter.key)
  }
}

#if os(iOS)
  // MARK: Lock Screen

  private struct AccessoryCircularMacros: View {
    let snapshot: TodayMacrosSnapshot

    var body: some View {
      let meter = snapshot.meter(.calories)
      if meter.target != nil {
        Gauge(value: meter.fill) {
          Text(verbatim: unit(of: .calories))
        } currentValueLabel: {
          Text(verbatim: meter.eatenText)
            .font(WidgetType.number(14))
            .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
      } else {
        VStack(spacing: 0) {
          Text(verbatim: meter.eatenText)
            .font(WidgetType.number(18))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
          Text(verbatim: unit(of: .calories))
            .font(WidgetType.number(10, weight: .regular))
        }
      }
    }
  }

  private struct AccessoryRectangularMacros: View {
    let snapshot: TodayMacrosSnapshot

    var body: some View {
      let calories = snapshot.meter(.calories)
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(verbatim: calories.eatenText)
            .font(WidgetType.number(17))
            .widgetAccentable()
          if let target = calories.targetText {
            Text(verbatim: "/ \(target)").font(WidgetType.number(12, weight: .regular))
          }
          Text(verbatim: unit(of: .calories)).font(WidgetType.number(11, weight: .regular))
          if snapshot.hasWaitingEntry {
            Image(systemName: "clock").font(.system(size: 11))
          }
        }
        HStack(spacing: 8) {
          ForEach([MacroKey.protein, .carbs, .fat], id: \.self) { key in
            let meter = snapshot.meter(key)
            HStack(spacing: 1) {
              Text(verbatim: String(name(of: key).prefix(1))).font(WidgetType.label(11))
              Text(verbatim: meter.eatenText).font(WidgetType.number(11))
            }
          }
        }
        if snapshot.targets == nil {
          Text(verbatim: Copy.tracker.widget.noTargets.text)
            .font(WidgetType.label(10, weight: .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
#endif

// MARK: No data

/// Before the app has left anything: a fresh install, or a build with no App Group.
private struct NoDataView: View {
  enum Style {
    /// A Home Screen or desktop widget: a mark and the words.
    case full
    /// The Lock Screen's rectangle: the words alone.
    case line
    /// The Lock Screen's circle, which has no room for words.
    case icon
  }

  let style: Style

  var body: some View {
    switch style {
    case .full:
      VStack(spacing: 8) {
        Image(systemName: "fork.knife").font(.title2).foregroundStyle(Brand.Colors.magic)
        Text(verbatim: Copy.tracker.widget.noData.text)
          .font(WidgetType.label(13, weight: .regular))
          .foregroundStyle(Brand.Colors.subtext)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(0.8)
      }
    case .line:
      Text(verbatim: Copy.tracker.widget.noData.text)
        .font(WidgetType.label(11, weight: .regular))
        .minimumScaleFactor(0.7)
    case .icon:
      Image(systemName: "fork.knife").font(.title3)
    }
  }
}

// MARK: Spoken

/// The widget as one sentence for VoiceOver: each macro eaten against its target.
enum TodayMacrosSpeech {
  static func label(for snapshot: TodayMacrosSnapshot?) -> String {
    guard let snapshot else { return Copy.tracker.widget.noData.text }
    var parts = MacroKey.allCases.map { key -> String in
      let meter = snapshot.meter(key)
      var part = "\(name(of: key)) \(meter.eatenText) \(unit(of: key))"
      if let target = meter.targetText { part += " \(Copy.tracker.header.of.text) \(target)" }
      return part
    }
    if snapshot.targets == nil { parts.append(Copy.tracker.widget.noTargets.text) }
    if snapshot.hasWaitingEntry { parts.append(Copy.tracker.widget.estimating.text) }
    return ([Copy.tracker.header.label.text] + parts).joined(separator: ", ")
  }
}
