import CauldronKit
import SwiftData
import SwiftUI

/// The diary: one day at a time, eaten against target on top, then breakfast, lunch, dinner and
/// snack with their entries and subtotals. The day's logic is `DayLog` and `MacroMeter`.
struct DiaryView: View {
  let targets: TargetsRecord?
  let openTargets: () -> Void

  @Environment(\.scenePhase) private var scenePhase
  @State private var today: LocalDate
  @State private var day: LocalDate

  init(today: LocalDate, targets: TargetsRecord?, openTargets: @escaping () -> Void) {
    self.targets = targets
    self.openTargets = openTargets
    _today = State(initialValue: today)
    _day = State(initialValue: today)
  }

  var body: some View {
    VStack(spacing: 0) {
      DayNavigator(day: $day, today: today)
      DiaryDayList(day: day, targets: targets, openTargets: openTargets)
    }
    .background(Brand.Colors.base)
    .onChange(of: scenePhase) { _, phase in
      // A diary left open past midnight: follow the new day if it was showing the old one.
      guard phase == .active, let now = TargetsForm.today(), now != today else { return }
      if day == today { day = now }
      today = now
    }
  }
}

/// Previous, next and today, with the date in Geist Mono.
struct DayNavigator: View {
  @Binding var day: LocalDate
  let today: LocalDate

  private let diary = Copy.tracker.diary

  var body: some View {
    HStack(spacing: 8) {
      Button {
        day = day.adding(days: -1)
      } label: {
        Image(systemName: "chevron.left").frame(width: 40, height: 40)
      }
      .accessibilityLabel(diary.previousDay.text)

      VStack(spacing: 2) {
        Text(verbatim: Self.label(for: day, today: today))
          .brandText(.section)
          .foregroundStyle(day == today ? Brand.Colors.heat : Brand.Colors.ink)
        Text(verbatim: day.description).brandText(.quantity)
          .foregroundStyle(Brand.Colors.subtext)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .combine)

      if day != today {
        Button(diary.today.text) { day = today }
          .brandText(.control)
      }

      Button {
        day = day.adding(days: 1)
      } label: {
        Image(systemName: "chevron.right").frame(width: 40, height: 40)
      }
      .accessibilityLabel(diary.nextDay.text)
    }
    .buttonStyle(.borderless)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(diary.pickDay.text)
  }

  /// "Today", "Yesterday" and "Tomorrow", or the weekday and date.
  static func label(for day: LocalDate, today: LocalDate) -> String {
    switch today.days(until: day) {
    case 0: return Copy.tracker.diary.today.text
    case -1: return Copy.tracker.diary.yesterday.text
    case 1: return Copy.tracker.diary.tomorrow.text
    default:
      return day.date(in: .current)?.formatted(.dateTime.weekday(.wide).month(.wide).day())
        ?? day.description
    }
  }
}

/// A meal being added to.
private struct AddRequest: Identifiable {
  let slot: MealSlot
  var id: MealSlot { slot }
}

/// One day's entries. The entries are read live with `@Query`, so every change shows at once.
private struct DiaryDayList: View {
  let day: LocalDate
  let targets: TargetsRecord?
  let openTargets: () -> Void

  @Query private var records: [DiaryEntryRecord]
  @Environment(\.modelContext) private var context
  @State private var adding: AddRequest?
  @State private var editing: DiaryEntryRecord?
  @State private var failure: CopyString?

  init(day: LocalDate, targets: TargetsRecord?, openTargets: @escaping () -> Void) {
    self.day = day
    self.targets = targets
    self.openTargets = openTargets
    let key = day.description
    _records = Query(filter: #Predicate<DiaryEntryRecord> { $0.dayKey == key })
  }

  private var log: DayLog { DayLog(day: day, records: records) }

  var body: some View {
    let log = log
    let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    List {
      Section {
        DayHeaderView(
          meters: MacroMeter.meters(totals: log.totals, targets: targets?.macroTargets),
          openTargets: openTargets)
      }
      .listRowBackground(Brand.Colors.mantle)

      if log.isEmpty {
        Section {
          Text(verbatim: Copy.tracker.diary.empty.text)
            .brandText(.body)
            .foregroundStyle(Brand.Colors.subtext)
        }
        .listRowBackground(Color.clear)
      }

      ForEach(log.sections) { section in
        Section {
          ForEach(section.entries, id: \.id) { entry in
            if let record = byID[entry.id] {
              Button {
                editing = record
              } label: {
                EntryRow(entry: entry)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(Copy.tracker.diary.edit(entry.name).text)
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                  remove(record)
                } label: {
                  Text(verbatim: Copy.tracker.entry.remove.text)
                }
              }
              .contextMenu {
                Button(role: .destructive) {
                  remove(record)
                } label: {
                  Text(verbatim: Copy.tracker.entry.remove.text)
                }
              }
            }
          }
        } header: {
          SlotHeader(section: section) { adding = AddRequest(slot: section.slot) }
        }
        .listRowBackground(Brand.Colors.mantle)
      }
    }
    .scrollContentBackground(.hidden)
    .sheet(item: $adding) { request in
      DiaryAddSheet(day: day, slot: request.slot) { adding = nil }
    }
    .sheet(item: $editing) { record in
      DiaryEntrySheet(
        record: record, onClose: { editing = nil },
        onFailure: { message in
          editing = nil
          failure = message
        })
    }
    .alert(
      Text(verbatim: failure?.text ?? ""),
      isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    ) {
      Button(Copy.ui.close.text) { failure = nil }
    }
  }

  private func remove(_ record: DiaryEntryRecord) {
    do {
      try DiaryWrites.remove(record, in: context)
    } catch {
      failure = Copy.tracker.diary.couldntSave
    }
  }
}

private struct SlotHeader: View {
  let section: DayLog.Section
  let add: () -> Void

  var body: some View {
    let name = Copy.week.slots[section.slot].text
    HStack {
      Text(verbatim: name)
        .brandText(.section)
        .foregroundStyle(Brand.Colors.ink)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
      Spacer()
      if !section.entries.isEmpty {
        Text(
          verbatim:
            "\(MacroMeter.whole(section.subtotal.calories)) \(Copy.tracker.macros.calories.text)"
        )
        .brandText(.quantity)
        .foregroundStyle(Brand.Colors.subtext)
      }
      Button(action: add) {
        Image(systemName: "plus").frame(width: 32, height: 32)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(Copy.tracker.diary.addTo(name).text)
    }
  }
}

private struct EntryRow: View {
  let entry: DiaryEntry

  var body: some View {
    let totals = entryTotals(entry)
    let amount = [
      entry.amount, entry.servings == 1 ? nil : "× \(showNumber(entry.servings, digits: 2))",
    ].compactMap { $0 }.joined(separator: " ")
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: entry.name).brandText(.body).lineLimit(1)
        HStack(spacing: 8) {
          if !amount.isEmpty { Text(verbatim: amount).brandText(.quantity) }
          if entry.source == .described {
            Text(verbatim: Copy.tracker.diary.estimate.text).brandText(.unit)
          }
          if hasGaps(entry) {
            Text(verbatim: Copy.tracker.diary.gaps.text).brandText(.unit)
          }
        }
        .foregroundStyle(Brand.Colors.subtext)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        Text(
          verbatim:
            "\(MacroMeter.whole(totals.calories)) \(Copy.tracker.macros.calories.text)"
        )
        .font(.brand(.quantity, size: 14))
        .fontWeight(.semibold)
        HStack(spacing: 8) {
          ForEach([MacroKey.protein, .carbs, .fat], id: \.self) { key in
            HStack(spacing: 3) {
              Circle().fill(key.tint).frame(width: 6, height: 6)
              Text(verbatim: "\(MacroMeter.whole(totals[key]))\(Copy.tracker.macros.grams.text)")
                .brandText(.unit)
            }
          }
        }
        .accessibilityHidden(true)
      }
    }
    .contentShape(Rectangle())
  }
}
