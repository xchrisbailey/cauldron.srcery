#if os(iOS)
  import ActivityKit
  import CauldronKit
  import SwiftUI
  import WidgetKit

  /// The Lock Screen and Dynamic Island views for a step timer. They only draw what the app put
  /// in `BrewTimerAttributes`: the countdown is the system's own `Text(timerInterval:)`, which
  /// keeps counting with the app suspended. The brand's colours and Geist Mono live in the app
  /// target, so these use system colours and the monospaced system face for now.
  struct BrewTimerActivity: Widget {
    var body: some WidgetConfiguration {
      ActivityConfiguration(for: BrewTimerAttributes.self) { context in
        BrewTimerLockScreen(attributes: context.attributes, state: context.state)
          .padding(16)
      } dynamicIsland: { context in
        DynamicIsland {
          DynamicIslandExpandedRegion(.leading) {
            BrewTimerTitle(attributes: context.attributes)
          }
          DynamicIslandExpandedRegion(.trailing) {
            BrewTimerCountdown(state: context.state)
              .font(.system(.title2, design: .monospaced, weight: .semibold))
          }
          DynamicIslandExpandedRegion(.bottom) {
            BrewTimerProgress(attributes: context.attributes, state: context.state)
          }
        } compactLeading: {
          Image(systemName: "timer").foregroundStyle(.orange)
        } compactTrailing: {
          BrewTimerCountdown(state: context.state)
            .font(.system(.footnote, design: .monospaced, weight: .semibold))
            .frame(maxWidth: 52)
        } minimal: {
          Image(systemName: "timer").foregroundStyle(.orange)
        }
      }
    }
  }

  private struct BrewTimerLockScreen: View {
    let attributes: BrewTimerAttributes
    let state: BrewTimerAttributes.ContentState

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          BrewTimerTitle(attributes: attributes)
          Spacer()
          BrewTimerCountdown(state: state)
            .font(.system(size: 34, weight: .semibold, design: .monospaced))
        }
        BrewTimerProgress(attributes: attributes, state: state)
      }
    }
  }

  /// The recipe and the step, over the timer.
  private struct BrewTimerTitle: View {
    let attributes: BrewTimerAttributes

    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: attributes.recipeTitle)
          .font(.headline)
          .lineLimit(1)
        Text(verbatim: attributes.label)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// The time left: counting down while it runs, held while it's paused, and "Time's up" at the end.
  struct BrewTimerCountdown: View {
    let state: BrewTimerAttributes.ContentState

    var body: some View {
      if state.finished {
        Text(verbatim: Copy.brewing.timeUp.text)
          .foregroundStyle(.orange)
      } else if let endsAt = state.endsAt {
        Text(timerInterval: Date.now...max(endsAt, Date.now), countsDown: true)
          .monospacedDigit()
      } else {
        Text(Duration.seconds(state.remainingSeconds), format: .time(pattern: .minuteSecond))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
  }

  private struct BrewTimerProgress: View {
    let attributes: BrewTimerAttributes
    let state: BrewTimerAttributes.ContentState

    var body: some View {
      if let endsAt = state.endsAt, !state.finished {
        let start = endsAt.addingTimeInterval(-TimeInterval(attributes.totalSeconds))
        ProgressView(timerInterval: start...max(endsAt, start), countsDown: true) {
          EmptyView()
        } currentValueLabel: {
          EmptyView()
        }
        .tint(.orange)
      } else if state.finished {
        ProgressView(value: 1).tint(.orange)
      } else {
        HStack {
          ProgressView(
            value: Double(state.remainingSeconds), total: Double(max(1, attributes.totalSeconds))
          )
          .tint(.secondary)
          Text(verbatim: Copy.brewMode.paused.text)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
#endif
