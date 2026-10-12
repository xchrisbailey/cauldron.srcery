#if DEBUG
  import SwiftUI

  /// The palette and type scale in both appearances, to check against the brand book.
  /// Debug builds only, so its labels are not in the copy module.
  struct BrandPreview: View {
    private enum Appearance: String, CaseIterable {
      case system = "System"
      case latte = "Latte"
      case mocha = "Mocha"

      var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .latte: .light
        case .mocha: .dark
        }
      }
    }

    @State private var appearance: Appearance

    init() {
      // `-brandAppearance Latte` pins an appearance from the command line.
      let pinned = UserDefaults.standard.string(forKey: "brandAppearance")
      _appearance = State(initialValue: pinned.flatMap(Appearance.init(rawValue:)) ?? .system)
    }

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          Picker("Appearance", selection: $appearance) {
            ForEach(Appearance.allCases, id: \.self) { Text($0.rawValue) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()

          palette
          typeScale
          quantities
        }
        .padding(20)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
      .background(Brand.Colors.base)
      .foregroundStyle(Brand.Colors.ink)
      .tint(Brand.Colors.magic)
      .preferredColorScheme(appearance.colorScheme)
    }

    private var palette: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("Palette").brandStyle(.section)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
          ForEach(Brand.Colors.roles, id: \.self) { role in
            VStack(alignment: .leading, spacing: 6) {
              RoundedRectangle(cornerRadius: 10)
                .fill(Brand.Colors.color(role))
                .frame(height: 56)
                .overlay {
                  RoundedRectangle(cornerRadius: 10).strokeBorder(Brand.Colors.surface1)
                }
              Text(role)
                .brandStyle(.control)
                .foregroundStyle(Brand.Colors.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
          }
        }
      }
    }

    private var typeScale: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("Type").brandStyle(.section)
        VStack(alignment: .leading, spacing: 14) {
          sample("Title · Geist 34 / 700", style: .title, text: "Slow-roast tomato soup")
          sample("Section · Geist 20 / 650", style: .section, text: "Ingredients")
          sample(
            "Body · Geist 15 / 400, leading 1.6",
            style: .body,
            text: "Halve the tomatoes and lay them cut side up. Scatter over the garlic, then "
              + "roast until soft and catching at the edges."
          )
          sample("Control · Geist 14 / 500", style: .control, text: "Start brewing")
          sample(
            "Quantity · Geist Mono 13 / 500",
            style: .quantity,
            text: "1 ½ kg · 45 min · 12 Oct"
          )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 14))
      }
    }

    private var quantities: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("Quantities").brandStyle(.section)
        VStack(alignment: .leading, spacing: 10) {
          ingredient("1 ½", unit: "kg", item: "ripe tomatoes")
          ingredient("250", unit: "ml", item: "vegetable stock")
          ingredient("2", unit: "tbsp", item: "olive oil")
          ingredient("6", unit: nil, item: "garlic cloves")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 14))
      }
    }

    private func sample(_ label: String, style: Brand.TextStyle, text: String) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(label)
          .brandStyle(.unit)
          .foregroundStyle(Brand.Colors.overlay1)
        Text(text).brandStyle(style)
      }
    }

    private func ingredient(_ value: String, unit: String?, item: String) -> some View {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        QuantityText(value, unit: unit)
          .frame(width: 84, alignment: .leading)
        Text(item).brandStyle(.body)
      }
    }
  }

  #Preview("Latte") {
    BrandPreview().preferredColorScheme(.light)
  }

  #Preview("Mocha") {
    BrandPreview().preferredColorScheme(.dark)
  }
#endif
