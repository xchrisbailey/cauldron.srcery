import SwiftUI

/// A short-lived line at the bottom of the library: what just happened, and Undo when it can
/// be taken back.
struct RecipeNoticeBanner: View {
  let notice: RecipeNotice
  let onUndo: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(verbatim: notice.text)
        .brandText(.body)
        .lineLimit(2)
      if let undo = notice.undoLabel {
        Button(action: onUndo) {
          Text(verbatim: undo)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.magic)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
    .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.Colors.surface1, lineWidth: 1))
    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    .accessibilityElement(children: .contain)
  }
}
