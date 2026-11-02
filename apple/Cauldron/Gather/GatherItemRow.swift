import CauldronKit
import SwiftUI

/// Measures shared by the Gather list and the block above it.
enum GatherLayout {
  /// The space between the edge of the list column and everything in it.
  static let gutter: CGFloat = 16
  /// What the list itself adds on each side before a row's own gutter: the Mac's table view
  /// insets its rows by 8 points, and the block above the list (outside it) makes up the same
  /// so both share one left and right edge. The iPhone and iPad lists add nothing.
  static var listInset: CGFloat {
    #if os(macOS)
      8
    #else
      0
    #endif
  }
}

/// One line of the list: a tick box, the amount in Geist Mono, the item and who it's for, and
/// the way to mark it as already in the pantry (or, for one added by hand, to remove it).
///
/// Every row of a list has one shape at a given width and text size: tick, amount, item, pantry
/// control, each in its own column. A long "For ..." line truncates instead of moving the
/// controls. At the accessibility text sizes every row stacks the same way instead.
struct GatherItemRow: View {
  let item: GatherItem
  let onCheck: (Bool) -> Void
  let onPantry: (Bool) -> Void
  let onRemove: () -> Void
  @ScaledMetric(relativeTo: .body) private var amountWidth: CGFloat = 68
  @ScaledMetric(relativeTo: .body) private var firstLine: CGFloat = 19
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.horizontalSizeClass) private var sizeClass

  /// The box and the gap after it, which the controls line up under at the largest sizes.
  private static let checkInset: CGFloat = 30

  var body: some View {
    let text = GatherRowText(item)
    Group {
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 0) {
          check(text, stacked: true)
          HStack(spacing: 4) {
            pantryButton
            if item.manual { removeControl }
          }
          .padding(.leading, Self.checkInset)
        }
      } else {
        // The pantry control is last, so it stands at one x down the whole list. A line added
        // by hand puts its remove control before it, taking room from that row's item column.
        HStack(alignment: .center, spacing: 4) {
          check(text, stacked: false)
          if item.manual { removeControl }
          pantryButton
        }
      }
    }
    .padding(.vertical, 4)
    .background(item.inPantry ? Brand.Colors.fresh.opacity(0.12) : Color.clear)
    // The row owns its gutters (the list adds none), so ticks, text, controls and separators
    // share the edges of the header block above the list on every platform.
    .padding(.horizontal, GatherLayout.gutter)
    .alignmentGuide(.listRowSeparatorLeading) { _ in GatherLayout.gutter }
    .alignmentGuide(.listRowSeparatorTrailing) { $0.width - GatherLayout.gutter }
  }

  /// Whether the pantry control is a bare icon: on a narrow screen the labelled capsule leaves
  /// the item too little room. The text sizes that stack every row have room for the label.
  private var iconOnlyPantry: Bool {
    sizeClass == .compact && !typeSize.isAccessibilitySize
  }

  /// `WeekIconButton` is a 44 point target on iPhone and iPad; the Mac's pointer gets 28, and
  /// the frame keeps the column the same width there.
  private var removeControl: some View {
    WeekIconButton(
      systemImage: "xmark", label: Copy.gather.remove(item.item).text, action: onRemove
    )
    .frame(minWidth: 44, minHeight: 44)
  }

  private func check(_ text: GatherRowText, stacked: Bool) -> some View {
    Toggle(isOn: Binding(get: { item.checked }, set: { onCheck($0) })) {
      Group {
        if stacked {
          VStack(alignment: .leading, spacing: 2) {
            if let amount = text.amount { QuantityText(amount, unit: text.unit) }
            nameAndDetail(text, nameLines: nil, detailLines: 3)
          }
        } else {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
              if let amount = text.amount {
                QuantityText(amount, unit: text.unit)
                  .lineLimit(1)
                  .minimumScaleFactor(0.7)
              } else {
                Color.clear.frame(height: 1)
              }
            }
            .frame(width: amountWidth, alignment: .trailing)
            nameAndDetail(text, nameLines: 2, detailLines: 1)
          }
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: text.spoken))
    }
    .toggleStyle(GatherCheckStyle(firstLineHeight: firstLine))
  }

  private func nameAndDetail(_ text: GatherRowText, nameLines: Int?, detailLines: Int)
    -> some View
  {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: text.name)
        .brandText(.body)
        .foregroundStyle(item.checked ? Brand.Colors.overlay1 : Brand.Colors.ink)
        .strikethrough(item.checked, color: Brand.Colors.overlay0)
        .lineLimit(nameLines)
      Text(verbatim: text.detail)
        .brandText(.control)
        .foregroundStyle(Brand.Colors.subtext)
        .lineLimit(detailLines)
        .truncationMode(.tail)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var pantryButton: some View {
    Button {
      onPantry(!item.inPantry)
    } label: {
      Group {
        if iconOnlyPantry { pantryIcon } else { pantryCapsule }
      }
      // Either way the target is at least 44 points square.
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(verbatim: Copy.gather.markInPantry(item.item).text))
    .accessibilityAddTraits(item.inPantry ? [.isToggle, .isSelected] : .isToggle)
  }

  private var pantryTint: Color { item.inPantry ? Brand.Colors.fresh.opacity(0.22) : Color.clear }
  private var pantryEdge: Color { item.inPantry ? Brand.Colors.fresh : Brand.Colors.surface1 }
  private var pantryInk: Color { item.inPantry ? Brand.Colors.ink : Brand.Colors.subtext }

  /// The labelled control, for wide layouts and the stacked accessibility layout.
  private var pantryCapsule: some View {
    HStack(spacing: 4) {
      if item.inPantry {
        Image(systemName: "checkmark").accessibilityHidden(true)
      }
      Text(verbatim: Copy.gather.inPantry.text)
    }
    .brandText(.control)
    .lineLimit(1)
    .fixedSize()
    .foregroundStyle(pantryInk)
    .padding(.horizontal, 10)
    .frame(minHeight: 32)
    .background(pantryTint, in: Capsule())
    .overlay(Capsule().stroke(pantryEdge, lineWidth: 1))
  }

  /// The same control as one symbol on a narrow screen. The symbol fills when the item is in
  /// the pantry, with the same tint and edge as the capsule.
  private var pantryIcon: some View {
    Image(systemName: item.inPantry ? "cabinet.fill" : "cabinet")
      .font(.system(size: 16))
      .foregroundStyle(pantryInk)
      .frame(width: 34, height: 34)
      .background(pantryTint, in: Circle())
      .overlay(Circle().stroke(pantryEdge, lineWidth: 1))
      .accessibilityHidden(true)
  }
}
