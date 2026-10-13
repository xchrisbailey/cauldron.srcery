import CauldronKit
import SwiftData
import SwiftUI

/// The Gather section: the week's shopping, merged and grouped by aisle. It follows the same
/// week cursor as the Week section (the cook's first day of the week, and the weeks either
/// side) and hands one week at a time to `GatherScreen`.
struct GatherRoot: View {
  var body: some View {
    WeekCursorHost { cursor in
      GatherScreen(cursor: cursor)
        #if os(macOS)
          .focusedSceneValue(\.stepCommands, StepCommands.weeks(cursor))
        #endif
    }
  }
}

#if DEBUG
  #Preview("Gather") {
    let container = RecipePreviewData.container()
    GatherRoot()
      .modelContainer(container)
  }
#endif
