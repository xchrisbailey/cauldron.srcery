import CauldronKit
import SwiftData
import SwiftUI

/// One week of the Gather list: the rows built from the week's plan, grouped by aisle, and
/// every change to them. The week to show comes from `GatherRoot`.
///
/// Opening a week, or changing its plan, rebuilds the rows (see `GatherPlan.rebuild`); the
/// screen then only reads them, so a tick made on one device shows on the others as it syncs.
struct GatherScreen: View {
  let cursor: WeekCursor

  @Environment(\.modelContext) private var context
  @Query private var plan: [PlanEntryRecord]
  @Query private var records: [GatherItemRecord]
  @Query private var pantry: [PantryItemRecord]
  @AppStorage("cauldron:gather-hide-checked") private var hideChecked = false
  @State private var line = ""
  @State private var notice: String?
  @State private var noticeCount = 0

  init(cursor: WeekCursor) {
    self.cursor = cursor
    let start = cursor.start
    let key = start.description
    _plan = Query(filter: WeekPlan.predicate(from: start, through: start.adding(days: 6)))
    _records = Query(filter: #Predicate<GatherItemRecord> { $0.weekStartKey == key })
  }

  /// The list is as wide as a page of reading needs, however wide the window.
  private static let columnWidth: CGFloat = 760

  var body: some View {
    let snapshot = GatherSnapshot(start: cursor.start, records: records, pantry: pantry)
    // The rebuild, the notice and its timer hang off the stack, not its content. Inside it they
    // crash an `ImageRenderer` on iOS when the render is torn down, which is how the tests
    // draw this screen.
    NavigationStack {
      VStack(alignment: .leading, spacing: 0) {
        top(snapshot)
        if snapshot.isEmpty {
          EmptyState(systemImage: AppDestination.gather.systemImage, message: Copy.gather.empty)
        } else {
          list(snapshot)
        }
      }
      .frame(maxWidth: Self.columnWidth, maxHeight: .infinity, alignment: .top)
      .frame(maxWidth: .infinity)
      .background(Brand.Colors.base)
      .navigationTitle(AppDestination.gather.title.text)
    }
    .overlay(alignment: .bottom) {
      if let notice {
        WeekNoticeBanner(text: notice, canUndo: false, onUndo: {})
          .padding(16)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .task(id: GatherSignature(week: cursor.start, entries: plan)) {
      do {
        try GatherPlan.open(week: cursor.start, in: context)
      } catch {
        show(GatherPlan.message(for: error).text)
      }
    }
    .task(id: noticeCount) {
      guard notice != nil else { return }
      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled { withAnimation { notice = nil } }
    }
  }

  // MARK: Pieces

  private func top(_ snapshot: GatherSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      WeekHeaderView(
        start: cursor.start, isCurrent: cursor.isCurrent, onPrevious: cursor.previous,
        onNext: cursor.next, onThisWeek: cursor.thisWeek)
      addRow
      if !snapshot.isEmpty {
        HStack {
          Text(verbatim: snapshot.progress.text)
            .brandText(.quantity)
            .foregroundStyle(Brand.Colors.subtext)
          Spacer(minLength: 8)
          Toggle(isOn: $hideChecked) {
            Text(verbatim: Copy.gather.hideChecked.text).brandText(.control)
          }
          .toggleStyle(GatherCheckStyle())
          .fixedSize()
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var addRow: some View {
    HStack(spacing: 8) {
      TextField(
        text: Binding(
          get: { line }, set: { line = GatherLimits.capped($0) }),
        prompt: Text(verbatim: Copy.gather.addPlaceholder.text)
      ) {
        Text(verbatim: Copy.gather.addItem.text)
      }
      .brandText(.body)
      .textFieldStyle(.plain)
      .padding(.horizontal, 12)
      .frame(minHeight: 44)
      .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.Colors.surface1, lineWidth: 1))
      .onSubmit(add)
      Button(action: add) {
        Text(verbatim: Copy.gather.add.text)
          .brandText(.control)
          .foregroundStyle(canAdd ? Brand.Colors.magic : Brand.Colors.overlay1)
          .frame(minHeight: 44)
      }
      .buttonStyle(.plain)
      .disabled(!canAdd)
    }
  }

  private var canAdd: Bool {
    !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func list(_ snapshot: GatherSnapshot) -> some View {
    List {
      ForEach(snapshot.sections(hidingChecked: hideChecked)) { section in
        Section {
          ForEach(section.items, id: \.id) { item in
            row(item)
          }
        } header: {
          Text(verbatim: section.title.text.uppercased())
            .brandText(.quantity)
            .foregroundStyle(Brand.Colors.subtext)
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
  }

  private func row(_ item: GatherItem) -> some View {
    GatherItemRow(
      item: item,
      onCheck: { checked in perform { try GatherPlan.setChecked(item.id, checked, in: context) } },
      onPantry: { on in perform { try GatherPlan.setPantry(itemKey: item.itemKey, on, in: context) }
      },
      onRemove: { remove(item) }
    )
    .listRowBackground(Color.clear)
    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 8))
    .listRowSeparatorTint(Brand.Colors.surface0)
    .swipeActions(edge: .trailing) {
      if item.manual {
        Button(role: .destructive) {
          remove(item)
        } label: {
          Text(verbatim: Copy.week.remove.text)
        }
      }
    }
  }

  // MARK: Changes

  /// Runs a change and saves it; a refusal is rolled back and shown. Returns whether it landed.
  @discardableResult
  private func perform(_ work: () throws -> some Any) -> Bool {
    do {
      try GatherPlan.commit(in: context) { _ = try work() }
      return true
    } catch {
      show(GatherPlan.message(for: error).text)
      return false
    }
  }

  private func add() {
    let text = line
    if perform({ try GatherPlan.add(text, week: cursor.start, in: context) }) { line = "" }
  }

  private func remove(_ item: GatherItem) {
    perform { try GatherPlan.remove(item.id, in: context) }
  }

  private func show(_ text: String) {
    withAnimation { notice = text }
    noticeCount += 1
    AccessibilityNotification.Announcement(text).post()
  }
}
