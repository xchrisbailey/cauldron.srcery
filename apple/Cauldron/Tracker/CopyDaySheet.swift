import CauldronKit
import SwiftData
import SwiftUI

/// What copying a day came to, as the line to show: how many entries went in, or that there was
/// nothing there to copy.
enum CopyDayOutcome {
  static func message(copied count: Int) -> CopyString {
    count > 0 ? Copy.tracker.copyDay.copied(count) : Copy.tracker.copyDay.nothing
  }

  /// Copies from `source` into `target` and says how it went. A refusal is the message to show
  /// in place of the outcome, and leaves the diary as it was.
  @MainActor
  static func run(
    from source: LocalDate, to target: LocalDate, slot: MealSlot?, in context: ModelContext
  ) -> (message: CopyString, failed: Bool) {
    do {
      let copies = try DiaryEditor(context: context).copy(from: source, to: target, slot: slot)
      return (message(copied: copies.count), false)
    } catch DiaryWrites.Failure.dayFull {
      return (Copy.tracker.dayFull, true)
    } catch DiaryWrites.Failure.invalid where source == target {
      return (Copy.tracker.copyDay.sameDay, true)
    } catch {
      return (Copy.tracker.diary.couldntSave, true)
    }
  }
}

/// Copy a day, or one meal of it, into the day the diary shows. It opens on yesterday, as the
/// web does.
struct CopyDaySheet: View {
  let day: LocalDate
  let onClose: () -> Void
  /// Called once the copy ran: the line to show, and whether it was refused.
  let onDone: (CopyString, Bool) -> Void

  @Environment(\.modelContext) private var context
  @State private var from: LocalDate
  /// Nil is the whole day.
  @State private var slot: MealSlot?
  @State private var error: CopyString?

  private let copyDay = Copy.tracker.copyDay

  init(
    day: LocalDate, onClose: @escaping () -> Void,
    onDone: @escaping (CopyString, Bool) -> Void
  ) {
    self.day = day
    self.onClose = onClose
    self.onDone = onDone
    _from = State(initialValue: day.adding(days: -1))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          DatePicker(selection: fromDate, in: dateRange, displayedComponents: .date) {
            Text(verbatim: copyDay.from.text)
          }
          .brandText(.quantity)
          .listRowBackground(Brand.Colors.mantle)
          Picker(selection: $slot) {
            Text(verbatim: copyDay.wholeDay.text).tag(MealSlot?.none)
            ForEach(MealSlot.allCases, id: \.self) { slot in
              Text(verbatim: Copy.week.slots[slot].text).tag(MealSlot?.some(slot))
            }
          } label: {
            Text(verbatim: copyDay.meal.text)
          }
          .brandText(.body)
          .listRowBackground(Brand.Colors.mantle)
        }
        if let error {
          Section { FieldError(error) }
        }
        Section {
          Button(action: run) {
            Text(verbatim: copyDay.copy.text).frame(maxWidth: .infinity)
          }
          .buttonStyle(.brandProminent)
          .listRowBackground(Color.clear)
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
      .navigationTitle(copyDay.title(Self.longLabel(of: day)).text)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(Copy.tracker.entry.cancel.text, action: onClose)
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 360)
    #endif
  }

  /// A year back from the open day, up to the day itself.
  private var dateRange: ClosedRange<Date> {
    let calendar = DayKeyCalendar.current
    let earliest = day.adding(days: -365).date(in: calendar) ?? .distantPast
    let latest = day.date(in: calendar) ?? .distantFuture
    return earliest...latest
  }

  private var fromDate: Binding<Date> {
    Binding(
      get: { from.date(in: DayKeyCalendar.current) ?? .now },
      set: { date in
        error = nil
        if let picked = LocalDate(date, in: DayKeyCalendar.current) { from = picked }
      })
  }

  private func run() {
    guard from != day else {
      error = copyDay.sameDay
      return
    }
    let outcome = CopyDayOutcome.run(from: from, to: day, slot: slot, in: context)
    onDone(outcome.message, outcome.failed)
  }

  /// "Wednesday, October 14", as the diary's header names a day.
  static func longLabel(of day: LocalDate) -> String {
    day.date(in: DayKeyCalendar.current)?.formatted(.dateTime.weekday(.wide).month(.wide).day())
      ?? day.description
  }
}
