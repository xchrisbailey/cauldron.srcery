import SwiftUI
import WidgetKit

/// Everything Cauldron shows outside the app: the brew timers' Live Activity (#169) and the
/// day's macros widget (#183).
@main
struct CauldronWidgets: WidgetBundle {
  var body: some Widget {
    TodayMacrosWidget()
    #if os(iOS)
      BrewTimerActivity()
    #endif
  }
}
