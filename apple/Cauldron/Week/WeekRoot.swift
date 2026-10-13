import CauldronKit
import SwiftData
import SwiftUI

/// The week section: a calendar of the week's meals with the calories and macros they add up
/// to, and the weeks either side. It reads the week's first day from the cook's preference and
/// hands one week at a time to `WeekPlanner`.
struct WeekRoot: View {
  var body: some View {
    WeekCursorHost { cursor in
      WeekPlanner(
        start: cursor.start, today: cursor.today, startsOn: cursor.startsOn,
        isCurrent: cursor.isCurrent, onPrevious: cursor.previous, onNext: cursor.next,
        onThisWeek: cursor.thisWeek, onStartsOn: cursor.setStartsOn
      )
      #if os(macOS)
        .focusedSceneValue(\.stepCommands, StepCommands.weeks(cursor))
      #endif
    }
  }
}

#if DEBUG
  #Preview("Week") {
    let container = RecipePreviewData.container()
    WeekRoot()
      .modelContainer(container)
  }
#endif
