import CauldronKit
import SwiftData
import SwiftUI

/// What a sheet over the week is for.
private enum WeekSheet: Identifiable {
  case stir(MealTarget)
  /// A recipe dropped on a meal: the days step, at `position` in the meal (nil for the end).
  case dropped(UUID, MealTarget, Int?)
  case change(UUID)
  case batch(UUID)

  var id: String {
    switch self {
    case .stir(let target): "stir-\(target.day)-\(target.slot.rawValue)"
    case .dropped(let id, let target, let position):
      "dropped-\(id.uuidString)-\(target.day)-\(target.slot.rawValue)-\(position ?? -1)"
    case .change(let id): "change-\(id.uuidString)"
    case .batch(let id): "batch-\(id.uuidString)"
    }
  }
}

/// A line at the bottom of the week: what just happened, and Undo when it can be taken back.
private struct WeekNotice {
  let text: String
  var undo: RemovedMeal?
}

/// One week of the plan: its tally, its meals, and every change to them. The week to show
/// comes from `WeekRoot`; this view reads and writes the entries in it.
struct WeekPlanner: View {
  let start: LocalDate
  let today: LocalDate
  let startsOn: WeekStartDay
  let isCurrent: Bool
  let onPrevious: () -> Void
  let onNext: () -> Void
  let onThisWeek: () -> Void
  let onStartsOn: @MainActor (WeekStartDay) -> Void

  @Environment(\.modelContext) private var context
  @Query private var records: [PlanEntryRecord]
  @Query private var batches: [PlannedBatchRecord]
  /// The day whose tally shows beside the week's, and on a narrow window the day shown.
  @State private var chosenDay: LocalDate?
  @State private var sheet: WeekSheet?
  @State private var clearing = false
  @State private var notice: WeekNotice?
  @State private var noticeCount = 0

  init(
    start: LocalDate, today: LocalDate, startsOn: WeekStartDay, isCurrent: Bool,
    onPrevious: @escaping () -> Void, onNext: @escaping () -> Void,
    onThisWeek: @escaping () -> Void, onStartsOn: @escaping @MainActor (WeekStartDay) -> Void
  ) {
    self.start = start
    self.today = today
    self.startsOn = startsOn
    self.isCurrent = isCurrent
    self.onPrevious = onPrevious
    self.onNext = onNext
    self.onThisWeek = onThisWeek
    self.onStartsOn = onStartsOn
    _records = Query(filter: WeekPlan.predicate(from: start, through: start.adding(days: 6)))
    let lower = start.description
    let upper = start.adding(days: 6).description
    _batches = Query(filter: #Predicate { $0.weekStartKey >= lower && $0.weekStartKey <= upper })
  }

  /// The width the seven columns need; narrower than this shows one day at a time.
  private static let gridWidth: CGFloat = 900

  private var snapshot: WeekSnapshot { WeekSnapshot(start: start, records: records) }

  /// A chosen day that isn't in this week (the cook moved to another) counts as none.
  private var shownDay: LocalDate? {
    chosenDay.flatMap { snapshot.days.contains($0) ? $0 : nil }
  }

  var body: some View {
    let snapshot = snapshot
    // The sheet, the dialog, the notice and its timer hang off the stack, not its content.
    // Inside it they crash an `ImageRenderer` on iOS when the render is torn down, which is
    // how the tests draw this screen.
    NavigationStack {
      GeometryReader { proxy in
        if proxy.size.width >= Self.gridWidth {
          gridPage(snapshot)
        } else {
          dayPage(snapshot)
        }
      }
      .background(Brand.Colors.base)
      .navigationTitle(AppDestination.week.title.text)
      .toolbar { weekMenu(snapshot) }
    }
    .sheet(item: $sheet) { sheet in
      switch sheet {
      case .stir(let target):
        StirFlowSheet(target: target, days: snapshot.days, today: today) { text in
          self.sheet = nil
          show(WeekNotice(text: text))
        }
      case .dropped(let id, let target, let position):
        droppedSheet(id, target, position, snapshot)
      case .change(let id):
        changeSheet(id, snapshot)
      case .batch(let id):
        if let batch = batches.first(where: { $0.id == id }) {
          PlannedBatchSheet(batch: batch) { self.sheet = nil }
        }
      }
    }
    .confirmationDialog(
      Text(verbatim: Copy.week.clearWeek.text), isPresented: $clearing, titleVisibility: .visible
    ) {
      Button(role: .destructive, action: clearWeek) {
        Text(verbatim: Copy.week.clearWeek.text)
      }
      Button(role: .cancel) {
      } label: {
        Text(verbatim: Copy.week.cancel.text)
      }
    } message: {
      Text(verbatim: Copy.week.clearConfirm(WeekDates.rangeLabel(start: start)).text)
    }
    .overlay(alignment: .bottom) {
      if let notice {
        WeekNoticeBanner(text: notice.text, canUndo: notice.undo != nil, onUndo: undo)
          .padding(16)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    #if os(macOS)
      .focusedSceneValue(
        \.addCommand, AddCommand(kind: .meal) { sheet = .stir(newMeal(snapshot)) }
      )
    #endif
    .onChange(of: start) { chosenDay = nil }
    .task(id: noticeCount) {
      guard let shown = notice else { return }
      try? await Task.sleep(for: .seconds(shown.undo == nil ? 3 : 6))
      if !Task.isCancelled { withAnimation { notice = nil } }
    }
  }

  @ToolbarContentBuilder
  private func weekMenu(_ snapshot: WeekSnapshot) -> some ToolbarContent {
    #if os(macOS)
      ToolbarItem {
        Button {
          sheet = .stir(newMeal(snapshot))
        } label: {
          Label {
            Text(verbatim: Copy.macMenu.addMeal.text)
          } icon: {
            Image(systemName: "plus")
          }
        }
      }
    #endif
    ToolbarItem {
      Menu {
        Button(action: copyLastWeek) { Text(verbatim: Copy.week.copyLastWeek.text) }
        Button(role: .destructive) {
          clearing = true
        } label: {
          Text(verbatim: Copy.week.clearWeek.text)
        }
        .disabled(snapshot.isEmpty && batches.isEmpty)
      } label: {
        Label {
          Text(verbatim: Copy.week.title.text)
        } icon: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
  }

  /// The meal the toolbar's and the menu's Add Meal starts on.
  private func newMeal(_ snapshot: WeekSnapshot) -> MealTarget {
    WeekPlan.newMeal(chosen: shownDay, week: snapshot.days, today: today)
  }

  // MARK: Pages

  private var header: some View {
    WeekHeaderView(
      start: start, isCurrent: isCurrent, onPrevious: onPrevious, onNext: onNext,
      onThisWeek: onThisWeek)
  }

  private func tally(_ snapshot: WeekSnapshot) -> some View {
    WeekTallyView(snapshot: snapshot, day: shownDay) { chosenDay = nil }
  }

  private func gridPage(_ snapshot: WeekSnapshot) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        tally(snapshot)
        if snapshot.isEmpty && batches.isEmpty {
          Text(verbatim: Copy.week.empty.text)
            .brandText(.body)
            .foregroundStyle(Brand.Colors.subtext)
        }
        batchSummaries
        WeekCalendarGrid(
          snapshot: snapshot, today: today, chosenDay: $chosenDay, onAdd: { sheet = .stir($0) },
          onOpen: { sheet = .change($0) }, onRemove: remove, onDrop: drop,
          onPlanRecipe: planRecipe)
        Text(verbatim: Copy.week.moveHint.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
        WeekStartPicker(startsOn: startsOn, onChange: onStartsOn).fixedSize()
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func dayPage(_ snapshot: WeekSnapshot) -> some View {
    let shown = shownDay ?? (snapshot.days.contains(today) ? today : snapshot.days[0])
    return WeekDayList(
      snapshot: snapshot, today: today, day: shown, onChoose: { chosenDay = $0 },
      onAdd: { sheet = .stir($0) }, onOpen: { sheet = .change($0) }, onRemove: remove,
      onPlanRecipe: planRecipe
    ) {
      VStack(alignment: .leading, spacing: 12) {
        header
        tally(snapshot)
        if snapshot.isEmpty && batches.isEmpty {
          Text(verbatim: Copy.week.empty.text)
            .brandText(.body)
            .foregroundStyle(Brand.Colors.subtext)
        }
        batchSummaries
      }
    } bottom: {
      WeekStartPicker(startsOn: startsOn, onChange: onStartsOn).fixedSize()
    }
  }

  @ViewBuilder
  private var batchSummaries: some View {
    if !batches.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(batches.sorted { $0.createdAt < $1.createdAt }, id: \.id) { batch in
          BatchSummary(batch: batch) { sheet = .batch(batch.id) }
        }
      }
    }
  }

  @ViewBuilder
  private func changeSheet(_ id: UUID, _ snapshot: WeekSnapshot) -> some View {
    if let meal = snapshot.meals.first(where: { $0.id == id }) {
      EntrySheet(
        meal: meal,
        // This week and the weeks either side.
        days: (-7..<14).map { start.adding(days: $0) },
        slotSize: snapshot.meals(on: meal.date, slot: meal.slot).count,
        onSave: { edit in
          sheet = nil
          applyChange(id, edit)
        },
        onShift: { by in
          sheet = nil
          applyChange(id, EntryChange(position: meal.position + by))
        },
        onRemove: {
          sheet = nil
          remove(id)
        })
    }
  }

  // MARK: Changes

  /// Runs a change and saves it; a refusal is rolled back and shown. Returns whether it landed.
  @discardableResult
  private func perform(_ work: () throws -> Void) -> Bool {
    do {
      try WeekPlan.commit(in: context, work)
      return true
    } catch {
      show(WeekNotice(text: WeekPlan.message(for: error).text))
      return false
    }
  }

  private func applyChange(_ id: UUID, _ change: EntryChange) {
    guard let record = records.first(where: { $0.id == id }) else { return }
    perform { try WeekPlan.apply(change, to: record, in: context) }
  }

  private func drop(_ id: UUID, to target: MealTarget, before: UUID?) {
    guard let change = WeekPlan.dropMove(records, moving: id, to: target, before: before)
    else { return }
    applyChange(id, change)
  }

  /// A recipe dragged out of the library onto a meal, before `before` when it landed on a card.
  /// It opens the days step, as the picker does, set to that meal.
  private func planRecipe(_ id: UUID, at target: MealTarget, before: UUID?) {
    do {
      _ = try WeekPlan.droppedRecipe(id: id, in: context)
      sheet = .dropped(id, target, WeekPlan.dropAt(records, target: target, before: before))
    } catch {
      show(WeekNotice(text: WeekPlan.message(for: error).text))
    }
  }

  @ViewBuilder
  private func droppedSheet(
    _ id: UUID, _ target: MealTarget, _ position: Int?, _ snapshot: WeekSnapshot
  ) -> some View {
    if let recipe = try? WeekPlan.droppedRecipe(id: id, in: context) {
      DroppedRecipeSheet(
        recipe: recipe, target: target, position: position, days: snapshot.days, today: today
      ) { text in
        self.sheet = nil
        show(WeekNotice(text: text))
      }
    }
  }

  private func remove(_ id: UUID) {
    guard let record = records.first(where: { $0.id == id }) else { return }
    let title = record.recipe.flatMap { $0.isBanished ? nil : $0.title } ?? record.title
    var removed: RemovedMeal?
    if perform({ removed = try WeekPlan.remove(record, in: context) }) {
      show(WeekNotice(text: Copy.week.removed(title).text, undo: removed))
    }
  }

  private func undo() {
    guard let removed = notice?.undo else { return }
    notice = nil
    perform { try WeekPlan.restore(removed, in: context) }
  }

  private func copyLastWeek() {
    var added = 0
    if perform({ added = try WeekPlan.copyLastWeek(into: start, in: context) }) {
      show(
        WeekNotice(text: (added > 0 ? Copy.week.copiedLastWeek : Copy.week.nothingToCopy).text))
    }
  }

  private func clearWeek() {
    if perform({ try WeekPlan.clear(week: start, in: context) }) {
      chosenDay = nil
      show(WeekNotice(text: Copy.week.cleared.text))
    }
  }

  private func show(_ next: WeekNotice) {
    withAnimation { notice = next }
    noticeCount += 1
    AccessibilityNotification.Announcement(next.text).post()
  }
}

/// A short-lived line over the week.
struct WeekNoticeBanner: View {
  let text: String
  let canUndo: Bool
  let onUndo: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(verbatim: text)
        .brandText(.body)
        .lineLimit(2)
      if canUndo {
        Button(action: onUndo) {
          Text(verbatim: Copy.week.undo.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.magic)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
    .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.Colors.surface1, lineWidth: 1))
    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    .accessibilityElement(children: .contain)
  }
}
