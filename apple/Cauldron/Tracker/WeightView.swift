import CauldronKit
import Charts
import SwiftData
import SwiftUI

/// Weight: weigh-ins as dots, the smoothed trend as a line, how the trend has moved, and what
/// was eaten over the same stretch. The numbers are `WeightHistory`, `WeightChartData` and
/// `IntakeAverages`.
struct WeightView: View {
  let today: LocalDate

  @Query private var records: [WeighInRecord]
  @Query private var meals: [DiaryEntryRecord]
  @Query private var profiles: [BodyProfileRecord]
  @Environment(\.modelContext) private var context
  @Environment(HealthSync.self) private var health
  @State private var range = WeightRange.threeMonths
  @State private var editing: WeighInRecord?
  @State private var adding = false
  @State private var failure: CopyString?

  private let t = Copy.tracker.weight

  /// A year of weigh-ins is always read, so the trend is the same whichever range is showing.
  static let fetchDays = 365

  init(today: LocalDate) {
    self.today = today
    let from = today.adding(days: -Self.fetchDays).description
    _records = Query(filter: #Predicate<WeighInRecord> { $0.dayKey >= from })
    _meals = Query(filter: #Predicate<DiaryEntryRecord> { $0.dayKey >= from })
  }

  private var unit: WeightUnit { Deduplication.keeper(of: profiles)?.weightUnit ?? .kg }

  var body: some View {
    let history = WeightHistory(records: records, today: today)
    List {
      Section {
        Picker(selection: $range) {
          ForEach(WeightRange.allCases, id: \.self) { range in
            Text(verbatim: label(range)).tag(range)
          }
        } label: {
          Text(verbatim: t.rangeLabel.text)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .brandText(.quantity)
        .listRowBackground(Color.clear)
      }

      if history.isEmpty {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: t.empty.text)
              .brandText(.body)
              .foregroundStyle(Brand.Colors.subtext)
            Button(t.logWeight.text) { adding = true }
              .brandText(.control)
          }
          .listRowBackground(Brand.Colors.mantle)
        }
      } else {
        chart(history)
        stats(history)
        intake(history)
        list(history)
      }
    }
    .scrollContentBackground(.hidden)
    .readingColumn()
    .background(Brand.Colors.base)
    .navigationTitle(t.pageTitle.text)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem {
        Button(t.add.text) { adding = true }
      }
    }
    .refreshable { await health.appDidBecomeActive(in: context) }
    .sheet(isPresented: $adding) {
      WeightEntrySheet(
        day: today, today: today, unit: unit, existing: nil, pickDay: true,
        onClose: { adding = false })
    }
    .sheet(item: $editing) { record in
      WeightEntrySheet(
        day: record.day ?? today, today: today, unit: unit, existing: record, pickDay: false,
        onClose: { editing = nil })
    }
    .alert(
      // copylint:ignore -- preserve empty title while this alert is hidden
      Text(verbatim: failure?.text ?? ""),
      isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    ) {
      Button(Copy.ui.close.text) { failure = nil }
    }
  }

  private func label(_ range: WeightRange) -> String {
    switch range {
    case .oneMonth: t.ranges.oneMonth.text
    case .threeMonths: t.ranges.threeMonths.text
    case .oneYear: t.ranges.oneYear.text
    case .all: t.ranges.all.text
    }
  }

  // MARK: Chart

  private func chart(_ history: WeightHistory) -> some View {
    let visible = history.visible(range)
    let data = WeightChartData(
      points: visible, unit: unit, start: history.start(of: range), end: today)
    return Section {
      VStack(alignment: .leading, spacing: 8) {
        Chart {
          ForEach(data.line) { point in
            LineMark(
              x: .value(t.legendTrend.text, point.day.date(in: .current) ?? .now),
              y: .value(t.legendTrend.text, point.value), series: .value("", "trend")
            )
            .foregroundStyle(Brand.Colors.magic)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
          }
          ForEach(data.dots) { point in
            PointMark(
              x: .value(t.legendScale.text, point.day.date(in: .current) ?? .now),
              y: .value(t.legendScale.text, point.value)
            )
            .foregroundStyle(Brand.Colors.overlay1)
            .symbolSize(28)
          }
        }
        .chartXScale(
          domain: (data.start.date(in: .current) ?? .now)...(data.end.date(in: .current) ?? .now)
        )
        .chartYScale(domain: data.yDomain)
        .chartYAxis {
          AxisMarks(values: data.yTicks) { _ in
            AxisGridLine().foregroundStyle(Brand.Colors.surface0)
            AxisValueLabel().foregroundStyle(Brand.Colors.overlay1)
          }
        }
        .chartXAxis {
          AxisMarks { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
              .foregroundStyle(Brand.Colors.overlay1)
          }
        }
        .frame(height: 220)
        .accessibilityLabel(t.chartLabel.text)
        .accessibilityValue(
          t.chartSummary(visible.count, data.start.description, data.end.description).text)
        HStack(spacing: 16) {
          legend(Brand.Colors.overlay1, t.legendScale.text)
          legend(Brand.Colors.magic, t.legendTrend.text)
        }
      }
      .listRowBackground(Brand.Colors.mantle)
    }
  }

  private func legend(_ color: Color, _ text: String) -> some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(verbatim: text).brandText(.control).foregroundStyle(Brand.Colors.subtext)
    }
    .accessibilityHidden(true)
  }

  // MARK: Stats

  private func stats(_ history: WeightHistory) -> some View {
    let unitText = Copy.tracker.targets.weightUnits[unit].text
    return Section {
      HStack(alignment: .top) {
        stat(
          t.trendNow.text, history.trendNow.map { WeightText.label(kg: $0, unit: unit) },
          unit: unitText)
        stat(
          t.lastWeek.text,
          history.weekChange.map { WeightText.signedChange(deltaKg: $0, unit: unit) },
          unit: unitText)
        stat(
          t.lastMonth.text,
          history.monthChange.map { WeightText.signedChange(deltaKg: $0, unit: unit) },
          unit: unitText)
      }
      .listRowBackground(Brand.Colors.mantle)
    }
  }

  private func stat(_ label: String, _ value: String?, unit: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: label).brandText(.control).foregroundStyle(Brand.Colors.subtext)
      if let value {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(verbatim: value).font(.brand(.quantity, size: 17)).fontWeight(.semibold)
          Text(verbatim: unit).brandText(.unit)
        }
      } else {
        Text(verbatim: t.notEnough.text).brandText(.control).foregroundStyle(
          Brand.Colors.subtext)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  // MARK: Intake

  private func intake(_ history: WeightHistory) -> some View {
    let start = history.start(of: range).description
    let days = IntakeAverages.days(of: meals.filter { $0.dayKey >= start })
    let averages = IntakeAverages(days: days)
    return Section {
      if let averages {
        LazyVGrid(
          columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12
        ) {
          ForEach(MacroKey.allCases, id: \.self) { key in
            let meter = MacroMeter(key: key, eaten: averages.totals[key], target: nil)
            VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: 6) {
                if key != .calories {
                  Circle().fill(key.tint).frame(width: 8, height: 8).accessibilityHidden(true)
                }
                Text(verbatim: meter.name.text).brandText(.control).foregroundStyle(
                  Brand.Colors.subtext)
              }
              HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: meter.eatenText).font(.brand(.quantity, size: 15))
                  .fontWeight(.semibold)
                Text(verbatim: meter.unit.text).brandText(.unit)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
          }
        }
        .listRowBackground(Brand.Colors.mantle)
        Text(verbatim: t.intakeAcross(averages.days).text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
          .listRowBackground(Brand.Colors.mantle)
      } else {
        Text(verbatim: t.intakeNone.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
          .listRowBackground(Brand.Colors.mantle)
      }
    } header: {
      Text(verbatim: t.intakeTitle.text)
    }
  }

  // MARK: Weigh-ins

  private func list(_ history: WeightHistory) -> some View {
    let byDay = Dictionary(grouping: records, by: \.dayKey).compactMapValues {
      Deduplication.keeper(of: $0)
    }
    return Section {
      ForEach(history.list(range), id: \.date) { point in
        if let record = byDay[point.date.description] {
          Button {
            editing = record
          } label: {
            HStack {
              Text(verbatim: point.date.description).brandText(.quantity)
              Spacer()
              HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: WeightText.label(kg: point.weightKg, unit: unit))
                  .brandText(.quantity)
                Text(verbatim: Copy.tracker.targets.weightUnits[unit].text).brandText(.unit)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(t.edit(point.date.description).text)
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
              remove(record)
            } label: {
              Text(verbatim: t.remove.text)
            }
          }
          .listRowBackground(Brand.Colors.mantle)
        }
      }
    } header: {
      Text(verbatim: t.listTitle.text)
    }
  }

  private func remove(_ record: WeighInRecord) {
    guard let day = record.day else { return }
    do {
      try WeightWrites.remove(day: day, in: context)
    } catch {
      failure = t.couldntRemove
    }
  }
}
