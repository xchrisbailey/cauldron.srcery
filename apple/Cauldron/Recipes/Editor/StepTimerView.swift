import CauldronKit
import SwiftUI

/// A step's timer: the time it will count, and a control to add, change or remove it
/// (`Timer` in the web editor's `StepRows.tsx`). Once set by hand it no longer follows the
/// step's text.
struct StepTimerView: View {
  @Binding var draft: RecipeDraft
  let step: StepRowDraft
  let open: Bool
  let toggle: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        if let seconds = step.timerSeconds {
          Label {
            Text(verbatim: formatTimer(seconds)).brandText(.quantity)
          } icon: {
            Image(systemName: "timer")
          }
          .foregroundStyle(Brand.Colors.heat)
        }
        Button(action: toggle) {
          Text(
            verbatim: (step.timerSeconds == nil ? Copy.editor.addTimer : Copy.editor.changeTimer)
              .text)
        }
        .buttonStyle(.borderless)
        .brandText(.control)
        .tint(Brand.Colors.magic)
        .accessibilityAddTraits(open ? .isSelected : [])
      }
      if open { StepTimerFields(draft: $draft, stepID: step.id) }
    }
  }
}

private struct StepTimerFields: View {
  @Binding var draft: RecipeDraft
  let stepID: UUID
  /// What is typed, which can be something that isn't a number yet; the timer keeps its last
  /// good value meanwhile.
  @State private var minutes: String

  init(draft: Binding<RecipeDraft>, stepID: UUID) {
    _draft = draft
    self.stepID = stepID
    let seconds = draft.wrappedValue.steps.first { $0.id == stepID }?.timerSeconds
    _minutes = State(initialValue: stepTimerMinutesText(seconds))
  }

  private var seconds: Int? { draft.steps.first { $0.id == stepID }?.timerSeconds }

  var body: some View {
    HStack(spacing: 10) {
      Text(verbatim: Copy.editor.timerMinutes.text)
        .brandText(.control)
        .foregroundStyle(Brand.Colors.subtext)
      TextField("", text: binding)
        .textFieldStyle(.plain)
        .brandText(.quantity)
        #if os(iOS)
          .keyboardType(.decimalPad)
        #endif
        .autocorrectionDisabled()
        .frame(width: 80)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Brand.Colors.surface0, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(Text(verbatim: Copy.editor.timerMinutes.text))
      if seconds != nil {
        Button {
          draft.clearTimer(stepID)
          minutes = ""
        } label: {
          Text(verbatim: Copy.editor.clearTimer.text)
        }
        .buttonStyle(.borderless)
        .brandText(.control)
        .tint(Brand.Colors.magic)
      }
    }
    .padding(10)
    .background(Brand.Colors.crust, in: RoundedRectangle(cornerRadius: 10))
  }

  private var binding: Binding<String> {
    Binding(
      get: { minutes },
      set: { text in
        minutes = text
        draft.setTimer(stepID, minutes: text)
      })
  }
}
