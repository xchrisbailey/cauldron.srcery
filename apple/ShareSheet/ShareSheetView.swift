import CauldronImports
import CauldronKit
import SwiftUI

/// The share sheet: reading, a summary of the recipe it found with Save, and what to do when it
/// couldn't. A basic summary for now (#201); the full Summary layout comes with #202.
struct ShareSheetView: View {
  let model: ShareSheetModel
  @ScaledMetric private var titleSize = 22
  @ScaledMetric private var bodySize = 15

  var body: some View {
    Group {
      switch model.phase {
      case .reading: reading
      case .ready(let review): ready(review)
      case .saved:
        ShareConfirmation(
          outcome: .sent(
            title: Copy.importNative.savedToRecipes.text,
            detail: Copy.importNative.savedDetail.text))
      case .sent:
        ShareConfirmation(
          outcome: .sent(
            title: Copy.importNative.sentToCauldron.text,
            detail: Copy.importNative.opensAsDraft.text))
      case .failed(let notice): failed(notice)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.Colors.base.ignoresSafeArea())
    .task { model.start() }
  }

  private var reading: some View {
    VStack(spacing: 16) {
      ProgressView()
      Text(verbatim: Copy.importNative.readingRecipe.text)
        .font(ShareFonts.font(size: bodySize, weight: 400))
        .foregroundStyle(Brand.Colors.subtext)
      Button(Copy.recipeView.cancel.text) { model.cancel() }
        .buttonStyle(ShareButtonStyle(kind: .plain))
    }
    .padding(24)
  }

  private func ready(_ review: ShareSheetModel.Review) -> some View {
    VStack(spacing: 16) {
      if let cover = Self.cover(of: review.thumbnail) {
        Image(decorative: cover, scale: 1)
          .resizable()
          .scaledToFill()
          .frame(width: 96, height: 96)
          .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      VStack(spacing: 6) {
        Text(verbatim: review.title)
          .font(ShareFonts.font(size: titleSize, weight: 650))
          .foregroundStyle(Brand.Colors.ink)
        if let source = review.source {
          Text(verbatim: source)
            .font(ShareFonts.font(size: bodySize, weight: 400))
            .foregroundStyle(Brand.Colors.subtext)
        }
        Text(
          verbatim:
            "\(Copy.importNative.ingredientCount(review.ingredients).text) · \(Copy.importNative.stepCount(review.steps).text)"
        )
        .font(ShareFonts.font(size: bodySize, weight: 400))
        .monospacedDigit()
        .foregroundStyle(Brand.Colors.subtext)
        if let macros = review.macros, let line = macroLine(macros) {
          Text(verbatim: macroText(line, estimated: review.macrosEstimated))
            .font(ShareFonts.font(size: bodySize, weight: 400))
            .monospacedDigit()
            .foregroundStyle(Brand.Colors.subtext)
            .accessibilityLabel(Text(verbatim: line.label))
        } else if review.macrosPending {
          Text(verbatim: Copy.importNative.macrosLater.text)
            .font(ShareFonts.font(size: bodySize, weight: 400))
            .foregroundStyle(Brand.Colors.subtext)
        }
      }
      .multilineTextAlignment(.center)
      if review.duplicate {
        Text(verbatim: Copy.importNative.alreadyInBox.text)
          .font(ShareFonts.font(size: bodySize, weight: 600))
          .foregroundStyle(Brand.Colors.ink)
          .multilineTextAlignment(.center)
          .padding(.vertical, 8)
          .padding(.horizontal, 12)
          .frame(maxWidth: .infinity)
          .background(Brand.Colors.surface0, in: RoundedRectangle(cornerRadius: 10))
      }
      VStack(spacing: 8) {
        if review.canSave {
          Button(
            (review.duplicate ? Copy.importNative.saveAnotherCopy : Copy.importNative.saveToRecipes)
              .text
          ) { model.save() }
          .buttonStyle(ShareButtonStyle(kind: .prominent))
        }
        Button(Copy.importNative.editInCauldron.text) { model.sendToCauldron() }
          .buttonStyle(ShareButtonStyle(kind: review.canSave ? .plain : .prominent))
        Button(Copy.recipeView.cancel.text) { model.cancel() }
          .buttonStyle(ShareButtonStyle(kind: .plain))
      }
    }
    .frame(maxWidth: 360)
    .padding(24)
  }

  /// The thumbnail's bytes as an image to draw.
  private static func cover(of photo: ProcessedPhoto?) -> CGImage? {
    PhotoProcessing.thumbnail(of: photo?.data, maxPixel: 320)
  }

  private func macroText(_ line: MacroLine, estimated: Bool) -> String {
    estimated ? "\(line.text) · \(Copy.tracker.diary.estimate.text)" : line.text
  }

  private func failed(_ notice: ShareSheetModel.Notice) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.circle")
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(Brand.Colors.heat)
        .accessibilityHidden(true)
      Text(verbatim: notice.message.text)
        .font(ShareFonts.font(size: bodySize, weight: 400))
        .foregroundStyle(Brand.Colors.heat)
        .multilineTextAlignment(.center)
      VStack(spacing: 8) {
        if notice.canSend {
          Button(Copy.importNative.sendInstead.text) { model.sendToCauldron() }
            .buttonStyle(ShareButtonStyle(kind: .prominent))
        }
        Button(Copy.recipeView.cancel.text) { model.cancel() }
          .buttonStyle(ShareButtonStyle(kind: notice.canSend ? .plain : .prominent))
      }
    }
    .frame(maxWidth: 360)
    .padding(24)
  }
}

/// The sheet's two kinds of button, in the brand colours (the app's own styles are not in the
/// extension).
private struct ShareButtonStyle: ButtonStyle {
  enum Kind { case prominent, plain }
  let kind: Kind
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(ShareFonts.font(size: 16, weight: 600))
      .lineLimit(1)
      .frame(maxWidth: .infinity, minHeight: 44)
      .foregroundStyle(kind == .prominent ? Brand.Colors.base : Brand.Colors.magic)
      .background(kind == .prominent ? Brand.Colors.magic : .clear, in: Capsule())
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
      .contentShape(Capsule())
  }
}
