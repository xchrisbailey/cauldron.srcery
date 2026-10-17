import CauldronKit
import SwiftUI

/// One line of the list: a tick box, the amount in Geist Mono, the item and who it's for, and
/// the way to mark it as already in the pantry (or, for one added by hand, to remove it).
struct GatherItemRow: View {
  let item: GatherItem
  let onCheck: (Bool) -> Void
  let onPantry: (Bool) -> Void
  let onRemove: () -> Void
  @ScaledMetric private var amountWidth: CGFloat = 76

  var body: some View {
    let text = GatherRowText(item)
    HStack(alignment: .center, spacing: 4) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: 8) {
          check(text)
          pantryButton
        }
        VStack(alignment: .leading, spacing: 0) {
          check(text)
          pantryButton.padding(.leading, 30)
        }
      }
      if item.manual {
        WeekIconButton(
          systemImage: "xmark", label: Copy.gather.remove(item.item).text, action: onRemove)
      }
    }
    .padding(.vertical, 2)
    .background(item.inPantry ? Brand.Colors.fresh.opacity(0.12) : Color.clear)
  }

  private func check(_ text: GatherRowText) -> some View {
    Toggle(isOn: Binding(get: { item.checked }, set: { onCheck($0) })) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Group {
          if let amount = text.amount {
            QuantityText(amount, unit: text.unit)
          } else {
            Color.clear.frame(height: 1)
          }
        }
        .frame(width: amountWidth, alignment: .trailing)
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: text.name)
            .brandText(.body)
            .foregroundStyle(item.checked ? Brand.Colors.overlay1 : Brand.Colors.ink)
            .strikethrough(item.checked, color: Brand.Colors.overlay0)
          Text(verbatim: text.detail)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: text.spoken))
    }
    .toggleStyle(GatherCheckStyle())
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
