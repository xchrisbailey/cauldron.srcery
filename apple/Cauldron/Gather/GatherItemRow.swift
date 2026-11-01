import CauldronKit
import SwiftUI

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
  /// Whether the list holds a line added by hand. Every row then keeps a slot for the remove
  /// control, so the pantry control stands at one x position down the whole list.
  var reservesRemove = false
  @ScaledMetric(relativeTo: .body) private var amountWidth: CGFloat = 68
  @ScaledMetric(relativeTo: .body) private var firstLine: CGFloat = 19
  @Environment(\.dynamicTypeSize) private var typeSize

  /// The target the remove control gets on either platform.
  private static let removeSlot: CGFloat = 44
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
        HStack(alignment: .center, spacing: 8) {
          check(text, stacked: false)
          pantryButton
          if item.manual || reservesRemove { removeControl }
        }
      }
    }
    .padding(.vertical, 4)
    .background(item.inPantry ? Brand.Colors.fresh.opacity(0.12) : Color.clear)
    // Separators start at the row's own edge, not where this row's text happens to begin.
    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
  }

  @ViewBuilder
  private var removeControl: some View {
    if item.manual {
      WeekIconButton(
        systemImage: "xmark", label: Copy.gather.remove(item.item).text, action: onRemove
      )
      .frame(width: Self.removeSlot)
    } else {
      Color.clear.frame(width: Self.removeSlot, height: 1).accessibilityHidden(true)
    }
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
      HStack(spacing: 4) {
        if item.inPantry {
          Image(systemName: "checkmark").accessibilityHidden(true)
        }
        Text(verbatim: Copy.gather.inPantry.text)
      }
      .brandText(.control)
      .lineLimit(1)
      .fixedSize()
      .foregroundStyle(item.inPantry ? Brand.Colors.ink : Brand.Colors.subtext)
      .padding(.horizontal, 10)
      .frame(minHeight: 32)
      .background(item.inPantry ? Brand.Colors.fresh.opacity(0.22) : Color.clear, in: Capsule())
      .overlay(
        Capsule().stroke(item.inPantry ? Brand.Colors.fresh : Brand.Colors.surface1, lineWidth: 1)
      )
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(verbatim: Copy.gather.markInPantry(item.item).text))
    .accessibilityAddTraits(item.inPantry ? [.isToggle, .isSelected] : .isToggle)
  }
}
