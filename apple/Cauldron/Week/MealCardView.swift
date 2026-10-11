import CauldronKit
import SwiftUI

/// The payload of dragging a meal to another meal or day: the entry's id, and nothing else.
struct MealDrag: Codable, Transferable {
  let id: UUID

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .json)
  }
}

/// One planned meal on the calendar: its name, and what it adds up to.
struct MealCardView: View {
  let meal: PlanEntry
  /// It's on today's column.
  var isToday = false
  /// Its day has gone by.
  var isPast = false
  let onOpen: () -> Void
  let onRemove: () -> Void

  var body: some View {
    let card = MealCard(meal)
    Button(action: onOpen) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: card.title)
          .brandText(.control)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        if let detail = card.detail {
          Text(verbatim: detail)
            .brandText(.quantity)
            .foregroundStyle(Brand.Colors.subtext)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(
        card.isRecipe ? Brand.Colors.mantle : Brand.Colors.surface0.opacity(0.5),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isToday ? Brand.Colors.heat.opacity(0.6) : Brand.Colors.surface0, lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 8))
      .opacity(isPast ? 0.65 : 1)
    }
    .buttonStyle(.plain)
    .draggable(MealDrag(id: meal.id))
    .contextMenu {
      Button(action: onOpen) { Text(verbatim: Copy.week.edit(card.title).text) }
      Button(role: .destructive, action: onRemove) {
        Text(verbatim: Copy.week.remove.text)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityHint(Text(verbatim: Copy.week.edit(card.title).text))
  }
}

/// A round icon button at least as big as a thumb.
struct WeekIconButton: View {
  let systemImage: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Brand.Colors.magic)
        .frame(minWidth: Self.size, minHeight: Self.size)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(verbatim: label))
  }

  private static var size: CGFloat {
    #if os(iOS)
      44
    #else
      28
    #endif
  }
}
