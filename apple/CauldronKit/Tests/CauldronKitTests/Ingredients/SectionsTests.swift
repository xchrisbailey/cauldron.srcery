import CauldronKit
import Testing

/// Ported from `packages/shared/test/ingredients/sections.test.ts`. One heading rule for every
/// way lines come in: typed or pasted into the editor, read from a pasted or imported recipe,
/// and written in the seeds.
@Suite("readHeading")
struct ReadHeadingTests {
  @Test(
    arguments: [
      // Typed or pasted into the editor.
      ("For the sauce:", "For the sauce"),
      ("For the crust", "For the crust"),
      ("Dressing:", "Dressing"),
      ("- FOR THE FILLING", "FOR THE FILLING"),
      ("▢ For the crust:", "For the crust"),
      ("  To serve:  ", "To serve"),
      // Pasted from notes, blogs and captions.
      ("**Dressing:**", "Dressing"),
      ("_Topping_:", "Topping"),
      ("🥗 For the salad", "For the salad"),
      ("• For the glaze:", "For the glaze"),
      // Markdown, as the seeds write them.
      ("## To serve", "To serve"),
      ("# Sauce", "Sauce"),
      ("### For the sauce:", "For the sauce"),
    ])
  func readsAHeading(line: String, heading: String) {
    #expect(readHeading(line) == heading)
  }

  @Test(
    arguments: [
      "2 cups flour",
      "Salt, to taste",
      "Kosher salt",
      "1 (14 oz) can crushed tomatoes",
      // Colon lines with a quantity are ingredients, digits or not.
      "One onion:",
      "A pinch:",
      "200 g feta:",
      // Hashtags and empty markdown aren't headings.
      "#vegan",
      "## ",
      "",
      "   ",
    ])
  func isNilForIngredientsAndBlanks(line: String) {
    #expect(readHeading(line) == nil)
  }
}

@Suite("readIngredientBlock")
struct ReadIngredientBlockTests {
  @Test func givesEachLineTheHeadingAboveItAndDropsHeadingsAndBlanks() throws {
    let block = readIngredientBlock([
      "1 cup rice",
      "",
      "For the sauce:",
      "  2 tbsp butter  ",
      "1 tsp salt",
      "## To serve",
      "Parsley",
    ])
    #expect(block.map(\.original) == ["1 cup rice", "2 tbsp butter", "1 tsp salt", "Parsley"])
    #expect(block.map(\.item) == ["rice", "butter", "salt", "Parsley"])
    #expect(block.map(\.section) == [nil, "For the sauce", "For the sauce", "To serve"])
    #expect(block[1].quantity == Quantity(min: 2, max: nil))
    #expect(block[1].unit == .tbsp)
  }

  @Test func isEmptyForNoLinesOrOnlyHeadings() {
    #expect(readIngredientBlock([]).isEmpty)
    #expect(readIngredientBlock(["For the sauce:", ""]).isEmpty)
  }
}

private struct SectionedLine: Sectioned, Equatable {
  let item: String
  let section: String?
}

@Suite("withHeadings")
struct WithHeadingsTests {
  private func line(_ item: String, _ section: String?) -> SectionedLine {
    SectionedLine(item: item, section: section)
  }

  @Test func putsAHeadingBeforeEachNewSectionAndNoneBeforeUnsectionedLines() {
    let rows = withHeadings([
      line("rice", nil),
      line("butter", "For the sauce"),
      line("salt", "For the sauce"),
      line("water", nil),
      line("parsley", "To serve"),
    ])
    let text = rows.map { row in
      switch row {
      case .heading(let text): "# \(text)"
      case .line(let line): line.item
      }
    }
    #expect(
      text == [
        "rice", "# For the sauce", "butter", "salt", "water", "# To serve", "parsley",
      ])
  }

  @Test func roundTripsWithReadIngredientBlock() {
    let lines = ["1 cup rice", "For the sauce", "2 tbsp butter", "For serving", "Parsley"]
    let text = withHeadings(readIngredientBlock(lines)).map { row in
      switch row {
      case .heading(let text): text
      case .line(let line): line.original
      }
    }
    #expect(text == lines)
  }
}
