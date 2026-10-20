import CauldronKit
import SwiftUI
import Testing

@testable import Cauldron
@testable import CauldronImports

@MainActor
@Suite("Ingredient wrapping")
struct FlowLayoutTests {
  private func image(_ view: some View, width: CGFloat) throws -> CGImage {
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: width, height: nil)
    return try #require(renderer.cgImage)
  }

  @Test func aLongItemWrapsAndIsPlacedAtItsMeasuredWidth() throws {
    let text = Text(verbatim: "pasta with a long ingredient description")
    let expected = try image(text, width: 100)
    let actual = try image(FlowLayout { text }, width: 100)
    #expect(actual.width <= 100)
    #expect(actual.height == expected.height)
    // Correct measurement alone is insufficient: placement must also wrap the text.
    #expect(actual.dataProvider?.data == expected.dataProvider?.data)
  }

  @Test func importedReadingsFitBesideTheFixButton() throws {
    let lines = [
      "3 garlic cloves (or 2tsp garlic powder)",
      "1–2 cups shredded cheese depending on your goals",
      "1 cup pasta (I use my @kaizenfoodco high protein low carb pasta, cooked for half the time on the packaging)",
      "1 tsp cumin, 1 tsp chili powder, 1 tsp smoked paprika, 1/2 tsp oregano, salt & pepper",
      "Optional: pinch of cayenne or chipotle",
    ]
    for line in lines {
      var draft = RecipeDraft()
      let row = IngredientRowDraft.imported(line, flagged: false)
      draft.ingredients = [row]
      for width: CGFloat in [220, 280, 380] {
        for scheme in [ColorScheme.light, .dark] {
          let view = IngredientFixView(
            draft: .constant(draft), row: row, open: false, toggle: {}
          ).environment(\.colorScheme, scheme)
          let rendered = try image(view, width: width)
          #expect(CGFloat(rendered.width) <= width, "\(line) at \(width)")
        }
      }
    }
  }
}
