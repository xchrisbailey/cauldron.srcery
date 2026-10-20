import SwiftUI

/// Views side by side, wrapping onto the next line when they run out of room.
/// Use it as `FlowLayout { chip; chip }`.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arrange(in: proposal.width ?? .infinity, subviews: subviews).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let arranged = arrange(in: bounds.width, subviews: subviews)
    for (subview, placement) in zip(subviews, arranged.placements) {
      subview.place(
        at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
        proposal: placement.proposal)
    }
  }

  private func arrange(in width: CGFloat, subviews: Subviews) -> (
    placements: [(origin: CGPoint, proposal: ProposedViewSize)], size: CGSize
  ) {
    var placements: [(origin: CGPoint, proposal: ProposedViewSize)] = []
    // A long item must wrap within a row. Use the same proposal when placing it so its
    // drawn height agrees with the height reserved here for the next row.
    let proposal = ProposedViewSize(width: width.isFinite ? max(0, width) : nil, height: nil)
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var widest: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(proposal)
      if x > 0 && x + size.width > width {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      placements.append((CGPoint(x: x, y: y), proposal))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      widest = max(widest, x - spacing)
    }
    return (placements, CGSize(width: widest, height: y + rowHeight))
  }
}
