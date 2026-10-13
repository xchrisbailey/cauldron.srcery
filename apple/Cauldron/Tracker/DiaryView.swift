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
      DiaryDayList(day: day, today: today, targets: targets, openTargets: openTargets)
    }
    .readingColumn()
    .background(Brand.Colors.base)
    #if os(macOS)
      .focusedSceneValue(
        \.stepCommands, StepCommands.days(showing: day, today: today) { day = $0 })
    #endif
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { refreshToday() }
    }
    // A diary left open past midnight rolls over to the new day when it comes.
    .task(id: today) {
      while !Task.isCancelled {
        let wait = DayRollover.secondsUntilMidnight(now: .now, calendar: .current)
        try? await Task.sleep(for: .seconds(wait + 1))
        if Task.isCancelled { return }
        refreshToday()
      }
    }
  }
}

extension DiaryView {
  /// Follows the new day if the diary was showing the old one.
  fileprivate func refreshToday() {
    guard let now = TargetsForm.today(), now != today else { return }
    if day == today { day = now }
    today = now
  }
}

/// When a day ends.
enum DayRollover {
  /// Seconds from `now` to the next midnight in `calendar`.
  static func secondsUntilMidnight(now: Date, calendar: Calendar) -> TimeInterval {
    let midnight =
      calendar.nextDate(
        after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
        matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
    return max(1, midnight.timeIntervalSince(now))
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
  let today: LocalDate
  let targets: TargetsRecord?
  let openTargets: () -> Void

  @Query private var records: [DiaryEntryRecord]
  @Query private var weighIns: [WeighInRecord]
  @Query private var profiles: [BodyProfileRecord]
  /// Weigh-ins in the check-in's window, to know whether a check-in is due.
  @Query private var recentWeighIns: [WeighInRecord]
  @Environment(\.modelContext) private var context
  @State private var adding: AddRequest?
  @State private var editing: DiaryEntryRecord?
  @State private var weighing = false
  @State private var failure: CopyString?
  /// The line at the bottom after a delete, with Undo; the count restarts its timer.
  @State private var notice: DiaryWrites.Removed?
  @State private var noticeCount = 0

  init(day: LocalDate, today: LocalDate, targets: TargetsRecord?, openTargets: @escaping () -> Void)
  {
    self.day = day
    self.today = today
    self.targets = targets
    self.openTargets = openTargets
    let key = day.description
    _records = Query(filter: #Predicate<DiaryEntryRecord> { $0.dayKey == key })
    _weighIns = Query(filter: #Predicate<WeighInRecord> { $0.dayKey == key })
    let from = CheckInRules.from(today: today).description
    _recentWeighIns = Query(filter: #Predicate<WeighInRecord> { $0.dayKey >= from })
  }

  private var log: DayLog { DayLog(day: day, records: records) }

  var body: some View {
    let log = log
    let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    List {
      if checkInDue {
        Section {
          CheckInPrompt(context: context)
        }
        .listRowBackground(Brand.Colors.mantle)
      }
      Section {
        DayHeaderView(
          meters: MacroMeter.meters(totals: log.totals, targets: targets?.macroTargets),
          openTargets: openTargets)
        weighInRow
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
    #if os(macOS)
      .toolbar {
        ToolbarItem {
          Button(action: logFood) {
            Label {
              Text(verbatim: Copy.macMenu.logFood.text)
            } icon: {
              Image(systemName: "plus")
            }
          }
        }
      }
      .focusedSceneValue(\.addCommand, AddCommand(kind: .food, perform: logFood))
    #endif
    .sheet(isPresented: $weighing) {
      WeightEntrySheet(
        day: day, today: today, unit: weightUnit, existing: Deduplication.keeper(of: weighIns),
        pickDay: false, onClose: { weighing = false })
    }
    .sheet(item: $adding) { request in
      DiaryAddSheet(day: day, slot: request.slot) { adding = nil }
    }
    .sheet(item: $editing) { record in
      DiaryEntrySheet(
        record: record, onClose: { editing = nil }, onRemoved: show,
        onFailure: { message in
          editing = nil
          failure = message
        })
    }
    .overlay(alignment: .bottom) {
      if let notice {
        DiaryNoticeBanner(name: notice.name, onUndo: undo)
          .padding(16)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .task(id: noticeCount) {
      guard notice != nil else { return }
      try? await Task.sleep(for: .seconds(6))
      if !Task.isCancelled { withAnimation { notice = nil } }
    }
    .alert(
      Text(verbatim: failure?.text ?? ""),
      isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    ) {
      Button(Copy.ui.close.text) { failure = nil }
    }
  }

  /// Offered on today only, once a week, when there is a week of weigh-ins to go on.
  private var checkInDue: Bool {
    day == today
      && CheckInRules.isDue(
        profile: Deduplication.keeper(of: profiles)?.profile, targets: targets?.targets,
        weighInDays: recentWeighIns.compactMap(\.day), today: today)
  }

  private var weightUnit: WeightUnit { Deduplication.keeper(of: profiles)?.weightUnit ?? .kg }

  /// The day's weigh-in (tap to change it) or a way to log one, and the way to the trend.
  private var weighInRow: some View {
    HStack {
      if let weighIn = Deduplication.keeper(of: weighIns) {
        let shown =
          "\(WeightText.label(kg: weighIn.weightKg, unit: weightUnit)) \(Copy.tracker.targets.weightUnits[weightUnit].text)"
        Button {
          weighing = true
        } label: {
          Text(verbatim: shown).brandText(.quantity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.tracker.weight.change(shown).text)
      } else if day <= today {
        Button(Copy.tracker.weight.logWeight.text) { weighing = true }
          .brandText(.control)
      }
      Spacer()
      NavigationLink {
        WeightView(today: today)
      } label: {
        Text(verbatim: Copy.tracker.weight.seeTrend.text).brandText(.control)
      }
      .fixedSize()
    }
  }

  /// Opens the add sheet on the meal the hour suggests.
  private func logFood() {
    adding = AddRequest(slot: suggestedSlot(hour: Calendar.current.component(.hour, from: .now)))
  }

  private func remove(_ record: DiaryEntryRecord) {
    do {
      show(try DiaryEditor(context: context).remove(record))
    } catch {
      failure = Copy.tracker.diary.couldntSave
    }
  }

  private func show(_ removed: DiaryWrites.Removed) {
    withAnimation { notice = removed }
    noticeCount += 1
  }

  private func undo() {
    guard let removed = notice else { return }
    do {
      try DiaryEditor(context: context).restore(removed)
      withAnimation { notice = nil }
    } catch DiaryWrites.Failure.dayFull {
      notice = nil
      failure = Copy.tracker.dayFull
    } catch {
      notice = nil
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

/// "Removed Soup." with Undo, for a few seconds after a delete.
struct DiaryNoticeBanner: View {
  let name: String
  let onUndo: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(verbatim: Copy.tracker.diary.removed(name).text)
        .brandText(.body)
        .lineLimit(2)
      Button(action: onUndo) {
        Text(verbatim: Copy.tracker.diary.undo.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.magic)
          .frame(minHeight: 44)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
    .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.Colors.surface1, lineWidth: 1))
    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    .accessibilityElement(children: .contain)
  }
}
