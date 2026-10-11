import CauldronKit
import SwiftUI

/// A recipe in the library: photo, title, time and tags, and the per-serving macro line.
struct RecipeCardView: View {
  let recipe: RecipeRecord
  /// Whether it's the recipe open beside the list.
  var selected = false
  @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16

  var body: some View {
    let card = RecipeCardInfo(recipe)
    HStack(spacing: 12) {
      RecipePhotoView(photo: recipe.photo)
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 6) {
        Text(verbatim: card.title)
          .font(.brand(.section, size: titleSize))
          .lineLimit(2)
        FlowLayout(spacing: 6) {
          if let time = card.time {
            Text(verbatim: time)
              .brandText(.quantity)
              .foregroundStyle(Brand.Colors.subtext)
          }
          ForEach(card.tags, id: \.self) { TagChipView(tag: $0) }
        }
        if let macros = card.macros {
          Text(verbatim: macros.text)
            .brandText(.quantity)
            .foregroundStyle(Brand.Colors.subtext)
            .lineLimit(1)
            .accessibilityLabel(Text(verbatim: macros.label))
        }
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 14))
    .overlay(
      RoundedRectangle(cornerRadius: 14).stroke(
        selected ? Brand.Colors.magic : Brand.Colors.surface0, lineWidth: selected ? 2 : 1)
    )
    .contentShape(RoundedRectangle(cornerRadius: 14))
  }
}

/// A tag pill. Meal tags take a wash of `tips` and diet tags one of `fresh`, behind ink text
/// so they keep their contrast in Latte.
struct TagChipView: View {
  let tag: TagChip

  var body: some View {
    Text(verbatim: tag.name)
      .brandText(.control)
      .lineLimit(1)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(wash, in: Capsule())
  }

  private var wash: Color {
    switch tag.kind {
    case .meal: Brand.Colors.tips.opacity(0.24)
    case .diet: Brand.Colors.fresh.opacity(0.24)
    default: Brand.Colors.surface0
    }
  }
}
