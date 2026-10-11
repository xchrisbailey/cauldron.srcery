import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen and Dynamic Island views for a step timer. A placeholder until #169
/// designs them: it shows the label and the time left.
struct BrewTimerActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BrewTimerAttributes.self) { context in
      HStack {
        Text(verbatim: context.attributes.label)
        Spacer()
        BrewTimerCountdown(state: context.state)
      }
      .padding()
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(verbatim: context.attributes.label)
        }
        DynamicIslandExpandedRegion(.trailing) {
          BrewTimerCountdown(state: context.state)
        }
      } compactLeading: {
        Image(systemName: "timer")
      } compactTrailing: {
        BrewTimerCountdown(state: context.state)
      } minimal: {
        Image(systemName: "timer")
      }
    }
  }
}

struct BrewTimerCountdown: View {
  let state: BrewTimerAttributes.ContentState

  var body: some View {
    if let endsAt = state.endsAt, !state.finished {
      Text(timerInterval: Date.now...max(endsAt, Date.now), countsDown: true)
        .monospacedDigit()
    } else {
      Text(Duration.seconds(state.remainingSeconds), format: .time(pattern: .minuteSecond))
        .monospacedDigit()
    }
  }
}
