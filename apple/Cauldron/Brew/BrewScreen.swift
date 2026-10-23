import CauldronKit
import SwiftData
import SwiftUI

/// Brew mode: one step at a time in large type, with the step's ingredients and timer, and
/// Previous and Next. Timers keep running across steps, and the screen stays on. Shared by the
/// iPhone's full-screen cover and the Mac's brew window.
struct BrewScreen: View {
  let model: BrewModel
  /// The recipe, to mark it cooked when the last step is done.
  let recipe: RecipeRecord
  let onClose: () -> Void

  @Environment(\.modelContext) private var context
  @State private var couldntSave = false
  /// The log sheet, offered on the last step, and the editor, offered when there are no steps.
  @State private var logging = false
  @State private var editing = false
  @ScaledMetric(relativeTo: .title) private var stepSize: CGFloat = 24

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      progressBar
      if model.hasSteps {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            stepBody
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        otherTimers
        controls
      } else {
        EmptyState(systemImage: "timer", message: Copy.brewing.noSteps)
        Button {
          editing = true
        } label: {
          Text(verbatim: Copy.brewing.editRecipe.text)
        }
        .buttonStyle(RecipeActionButtonStyle(.primary))
        Button(action: onClose) {
          Text(verbatim: Copy.brewing.leave.text)
        }
        .buttonStyle(RecipeActionButtonStyle())
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 18)
    .frame(maxWidth: 680, maxHeight: .infinity, alignment: .top)
    .frame(maxWidth: .infinity)
    .background(Brand.Colors.base.ignoresSafeArea())
    .foregroundStyle(Brand.Colors.ink)
    .task {
      await model.begin()
      // Notice timers that ran out. The notification for each was scheduled when it started.
      while !Task.isCancelled {
        await model.timers.refresh()
        try? await Task.sleep(for: .milliseconds(250))
      }
    }
    .onDisappear { model.end() }
    .sheet(isPresented: $logging) {
      RecipeLogSheet(recipe: recipe, onClose: { logging = false })
    }
    // The steps this brew was planned from are the ones the recipe had when it began, so after
    // an edit the cook goes back to the recipe and starts again.
    .sheet(isPresented: $editing) {
      RecipeEditorSheet(recipe: recipe, onSaved: { _ in onClose() })
    }
  }

  // MARK: Top

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Button(action: onClose) {
        HStack(spacing: 4) {
          Image(systemName: "chevron.left").accessibilityHidden(true)
          Text(verbatim: model.plan.recipe.title).lineLimit(1)
        }
        .brandText(.control)
        .foregroundStyle(Brand.Colors.subtext)
        .frame(minHeight: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        Text(
          verbatim: Copy.display.leaveRecipe(
            Copy.brewing.leave.text, title: model.plan.recipe.title
          ).text)
      )
      #if os(macOS)
        .keyboardShortcut(.escape, modifiers: [])
      #endif
      Spacer()
      if model.hasSteps {
        Text(verbatim: Copy.brewing.stepOf(model.index + 1, model.plan.count).text)
          .brandText(.quantity)
          .foregroundStyle(Brand.Colors.overlay1)
      }
    }
  }

  private var progressBar: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Brand.Colors.surface0)
        Capsule().fill(Brand.Colors.magic)
          .frame(width: proxy.size.width * model.progress)
      }
    }
    .frame(height: 4)
    .animation(.easeOut(duration: 0.2), value: model.index)
    .accessibilityElement()
    .accessibilityLabel(Text(verbatim: Copy.brewing.stepOf(model.index + 1, model.plan.count).text))
  }

  // MARK: The step

  @ViewBuilder
  private var stepBody: some View {
    if let step = model.step {
      if let section = step.section, !section.isEmpty {
        Text(verbatim: section)
          .brandText(.quantity)
          .foregroundStyle(Brand.Colors.subtext)
          .textCase(.uppercase)
      }
      Text(BrewStepText.attributed(step.text, size: stepSize))
        .lineSpacing(stepSize * 0.25)
        .accessibilityLabel(
          Text(
            verbatim: Copy.display.accessibleStep(
              Copy.brewing.stepOf(model.index + 1, model.plan.count).text, text: step.text
            ).text))
      let ingredients = model.plan.ingredients(for: model.index)
      if !ingredients.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text(verbatim: Copy.brewing.forThisStep.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
            .accessibilityAddTraits(.isHeader)
          ForEach(Array(ingredients.enumerated()), id: \.offset) { _, line in
            IngredientLineView(line: line)
          }
        }
      }
      if let seconds = model.timerSeconds {
        BrewTimerRing(model: model, seconds: seconds)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var otherTimers: some View {
    let timers = model.otherTimers
    return Group {
      if !timers.isEmpty {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(timers, id: \.step) { timer in
              Button {
                model.go(to: timer.step)
              } label: {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                  HStack(spacing: 6) {
                    Text(verbatim: Copy.brewing.timerFor(timer.step + 1).text)
                    Text(
                      verbatim: timer.state == .done
                        ? Copy.brewing.timeUp.text
                        : BrewClock.text(model.timers.remaining(of: timer.step))
                    )
                    .brandText(.quantity)
                  }
                  .brandText(.control)
                  .padding(.horizontal, 12)
                  .frame(minHeight: 44)
                  .background(
                    timer.state == .done ? Brand.Colors.heat.opacity(0.24) : Brand.Colors.surface0,
                    in: Capsule())
                }
              }
              .buttonStyle(.plain)
            }
          }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(Text(verbatim: Copy.brewing.timers.text))
      }
    }
  }

  // MARK: Controls

  private var controls: some View {
    VStack(spacing: 10) {
      // Side by side where they fit; stacked, with the way forward first, where they don't.
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          previousButton
          forwardButtons
        }
        VStack(spacing: 8) {
          forwardButtons
          previousButton
        }
      }
      if couldntSave {
        Text(verbatim: Copy.errors.internal.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.heat)
      }
      if model.timers.notificationsRefused && !model.timers.board.timers.isEmpty {
        Text(verbatim: Copy.brewMode.notificationsRefused.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.heat)
      }
      #if os(iOS)
        Text(verbatim: Copy.brewing.wakeOn.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.overlay1)
      #else
        Text(verbatim: Copy.brewing.keys.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.overlay1)
      #endif
    }
  }

  private var previousButton: some View {
    Button {
      model.previous()
    } label: {
      Text(verbatim: Copy.brewing.previousStep.text)
    }
    .buttonStyle(RecipeActionButtonStyle())
    .disabled(!model.canGoBack)
    .keyboardShortcut(.leftArrow, modifiers: [])
  }

  /// Next step; on the last step, Log it and Brewed.
  @ViewBuilder
  private var forwardButtons: some View {
    if model.isLast {
      Button {
        logging = true
      } label: {
        Text(verbatim: Copy.tracker.logRecipe.title.text)
      }
      .buttonStyle(RecipeActionButtonStyle())
      Button {
        Task { await finish() }
      } label: {
        Text(verbatim: Copy.brewing.brewed.text)
      }
      .buttonStyle(RecipeActionButtonStyle(.primary))
    } else {
      Button {
        model.next()
      } label: {
        Text(verbatim: Copy.brewing.nextStep.text)
      }
      .buttonStyle(RecipeActionButtonStyle(.primary))
      .keyboardShortcut(.rightArrow, modifiers: [])
    }
  }

  private func finish() async {
    couldntSave = false
    do {
      let finished = try await model.finish {
        guard let today = RecipeCooking.today() else { throw RecipeCooking.NoDay() }
        try RecipeCooking.markCooked(recipe, on: today, context: context)
      }
      if finished { onClose() }
    } catch {
      couldntSave = true
    }
  }
}

/// The timer on a step: a ring that empties, the time left, and Start, Pause, Resume or Reset,
/// and a minute more. It reads the clock itself, so it is right whenever it is drawn.
struct BrewTimerRing: View {
  let model: BrewModel
  let seconds: Int

  var body: some View {
    VStack(spacing: 14) {
      TimelineView(.periodic(from: .now, by: 0.25)) { _ in
        let timer = model.timers.timer(for: model.index)
        let left = timer == nil ? seconds : model.timers.remaining(of: model.index)
        let total = max(1, timer?.totalSeconds ?? seconds)
        let done = timer?.state == .done
        ZStack {
          Circle().stroke(Brand.Colors.surface0, lineWidth: 8)
          Circle()
            .trim(from: 0, to: done ? 0 : CGFloat(left) / CGFloat(total))
            .stroke(
              done ? Brand.Colors.heat : Brand.Colors.magic,
              style: StrokeStyle(lineWidth: 8, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
          Text(verbatim: done ? Copy.brewing.timeUp.text : BrewClock.text(left))
            .font(.brand(.quantity, size: done ? 20 : 40))
            .monospacedDigit()
            .foregroundStyle(done ? Brand.Colors.heat : Brand.Colors.ink)
        }
        .frame(width: 190, height: 190)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: Copy.brewing.timers.text))
        .accessibilityValue(
          Text(verbatim: done ? Copy.brewing.timeUp.text : BrewClock.text(left)))
      }
      HStack(spacing: 8) {
        if let action = model.timerAction {
          Button {
            Task { await model.toggleTimer() }
          } label: {
            Text(verbatim: Self.label(action))
          }
          .buttonStyle(RecipeActionButtonStyle(action == .pause ? .secondary : .primary))
          .keyboardShortcut(.space, modifiers: [])
        }
        if let timer = model.timers.timer(for: model.index), timer.state != .done {
          Button {
            Task { await model.addMinute() }
          } label: {
            Text(verbatim: Copy.brewMode.addMinute.text)
          }
          .buttonStyle(RecipeActionButtonStyle())
          Button {
            Task { await model.resetTimer() }
          } label: {
            Text(verbatim: Copy.brewing.reset.text)
          }
          .buttonStyle(RecipeActionButtonStyle())
        }
      }
    }
  }

  static func label(_ action: BrewModel.TimerAction) -> String {
    switch action {
    case .start: Copy.brewing.startTimer.text
    case .pause: Copy.brewing.pause.text
    case .resume: Copy.brewing.resume.text
    case .reset: Copy.brewing.reset.text
    }
  }
}

extension RecipeCooking {
  /// There was no calendar day for now, which doesn't happen.
  struct NoDay: Error {}
}

/// A step's text, with its quantities, temperatures and times in Geist Mono.
enum BrewStepText {
  static func attributed(_ text: String, size: CGFloat) -> AttributedString {
    var result = AttributedString(text)
    result.font = .brand(.body, size: size)
    for range in StepMeasures.ranges(in: text) {
      if let lower = AttributedString.Index(range.lowerBound, within: result),
        let upper = AttributedString.Index(range.upperBound, within: result)
      {
        result[lower..<upper].font = .brand(.quantity, size: size * 0.92)
      }
    }
    return result
  }
}
