#if DEBUG
  import SwiftUI

  /// A debug-only screen with the palette and the type scale, for checking the brand against
  /// the brand book in both appearances.
  struct BrandPreview: View {
    private enum Appearance: String, CaseIterable, Identifiable {
      case system = "System"
      case light = "Light"
      case dark = "Dark"

      var id: Self { self }

      var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
      }
    }

    @State private var appearance = Appearance.system

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          Picker("Appearance", selection: $appearance) {
            ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()

          // copylint:ignore -- brand specimen, not app product copy
          Text(verbatim: "cauldron").brandText(.title)

          VStack(alignment: .leading, spacing: 12) {
            // copylint:ignore -- brand specimen, not app product copy
            Text(verbatim: "Palette").brandText(.section)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
              ForEach(Brand.Colors.Token.allCases, id: \.self) { token in
                swatch(token)
              }
            }
          }

          VStack(alignment: .leading, spacing: 12) {
            // copylint:ignore -- brand specimen, not app product copy
            Text(verbatim: "Type").brandText(.section)
            // copylint:ignore -- brand specimen, not app product copy
            Text(verbatim: "Title, Geist 34 bold").brandText(.title)
            // copylint:ignore -- brand specimen, not app product copy
            Text(verbatim: "Section, Geist 20 semibold").brandText(.section)
            // copylint:ignore -- brand specimen, not app product copy
            Text(
              verbatim:
                "Body, Geist 15 on a 1.6 line. Fold the egg whites into the batter in three "
                + "additions, turning the bowl as you go."
            )
            .brandText(.body)
            // copylint:ignore -- brand specimen, not app product copy
            Text(verbatim: "Control, Geist 14 medium").brandText(.control)
            HStack(spacing: 16) {
              QuantityText("1 1/2", unit: "cups")
              QuantityText("350", unit: "°F")
              QuantityText("12:30")
              QuantityText("Oct 11")
            }
          }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Brand.Colors.base)
      .foregroundStyle(Brand.Colors.ink)
      .preferredColorScheme(appearance.scheme)
    }

    private func swatch(_ token: Brand.Colors.Token) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        RoundedRectangle(cornerRadius: 8)
          .fill(token.color)
          .frame(height: 28)
          .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Brand.Colors.surface1, lineWidth: 1))
        Text(verbatim: token.rawValue).brandText(.control).lineLimit(1).minimumScaleFactor(0.7)
      }
    }
  }

  #Preview {
    BrandPreview()
  }
#endif
