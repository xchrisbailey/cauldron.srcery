import Foundation
import Testing

@testable import CauldronKit

/// The order text recognised on a page is read in, with boxes written by hand. Every box is a
/// fraction of the page from its top-left corner; a line is about 0.02 high and 0.03 apart.
@Suite("Reading order")
struct ReadingOrderTests {
  private func piece(
    _ text: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double = 0.02
  )
    -> TextFragment
  {
    TextFragment(text: text, box: TextBox(x: x, y: y, width: width, height: height))
  }

  /// Lines of one column, stacked 0.03 apart from `top`.
  private func column(_ lines: [String], x: Double, width: Double, top: Double) -> [TextFragment] {
    lines.enumerated().map { index, text in
      piece(text, x, top + Double(index) * 0.03, width)
    }
  }

  @Test func aSingleColumnReadsTopToBottomWhateverOrderItArrivesIn() {
    let page = column(
      ["Tomato soup", "Serves 4", "Chop the onion.", "Simmer."], x: 0.1, width: 0.7, top: 0.1)
    #expect(
      ReadingOrder.lines(page.reversed())
        == ["Tomato soup", "Serves 4", "Chop the onion.", "Simmer."])
    #expect(
      ReadingOrder.lines(page.shuffled()) == [
        "Tomato soup", "Serves 4", "Chop the onion.", "Simmer.",
      ]
    )
  }

  @Test func twoColumnsAreReadLeftInFullThenRight() {
    let ingredients = column(
      ["2 onions", "1 tbsp oil", "400 g tomatoes", "500 ml stock"], x: 0.08, width: 0.3, top: 0.2)
    let method = column(
      [
        "Fry the onions in the oil.", "Add the tomatoes.", "Pour in the stock.",
        "Simmer for 20 minutes.",
      ],
      x: 0.5, width: 0.4, top: 0.2)
    let page = ingredients + method
    let expected = ingredients.map(\.text) + method.map(\.text)
    #expect(ReadingOrder.lines(page) == expected)
    #expect(ReadingOrder.lines(page.reversed()) == expected)
    // Reading across would have given the lines interleaved.
    #expect(ReadingOrder.lines(page.shuffled()) == expected)
  }

  @Test func aTitleSpanningBothColumnsComesFirstAndAFooterLast() {
    let title = piece("Tomato soup", 0.2, 0.08, 0.6, 0.04)
    let ingredients = column(
      ["2 onions", "1 tbsp oil", "400 g tomatoes"], x: 0.08, width: 0.3, top: 0.2)
    let method = column(
      ["Fry the onions.", "Add the tomatoes.", "Simmer for 20 minutes."], x: 0.5, width: 0.4,
      top: 0.2)
    let footer = piece("Page 42 · from Grandma's book", 0.25, 0.9, 0.5)
    let page = [footer] + method + [title] + ingredients
    #expect(
      ReadingOrder.lines(page)
        == ["Tomato soup"] + ingredients.map(\.text) + method.map(\.text)
        + ["Page 42 · from Grandma's book"])
  }

  @Test func aHeadingInTheMiddleSplitsTheColumnsIntoBands() {
    let upperLeft = column(["a1", "a2", "a3"], x: 0.08, width: 0.3, top: 0.1)
    let upperRight = column(["b1", "b2", "b3"], x: 0.52, width: 0.3, top: 0.1)
    let heading = piece("Sauce", 0.3, 0.3, 0.4, 0.03)
    let lowerLeft = column(["c1", "c2", "c3"], x: 0.08, width: 0.3, top: 0.4)
    let lowerRight = column(["d1", "d2", "d3"], x: 0.52, width: 0.3, top: 0.4)
    let page = lowerRight + lowerLeft + [heading] + upperRight + upperLeft
    #expect(
      ReadingOrder.lines(page)
        == ["a1", "a2", "a3", "b1", "b2", "b3", "Sauce", "c1", "c2", "c3", "d1", "d2", "d3"])
  }

  @Test func piecesOnOneBaselineAreJoinedLeftToRight() {
    let page = [
      piece("flour", 0.3, 0.2, 0.1),
      piece("2 cups", 0.1, 0.2, 0.15),
      piece("1 egg", 0.1, 0.23, 0.1),
      piece("Serves 4", 0.7, 0.2, 0.15),
    ]
    #expect(ReadingOrder.lines(page) == ["2 cups flour Serves 4", "1 egg"])
  }

  @Test func slightlySkewedLinesStillJoinAndStillSeparate() {
    // The right half of each line sits a little lower, as on a page photographed askew.
    var page: [TextFragment] = []
    for (index, words) in [
      ("Heat the oil in a wide pan", "and fry the onions."),
      ("Add the garlic and cook", "for one more minute."),
      ("Stir in the tomatoes", "and the stock."),
    ].enumerated() {
      let y = 0.2 + Double(index) * 0.03
      page.append(piece(words.0, 0.1, y, 0.4))
      page.append(piece(words.1, 0.52, y + 0.008, 0.3))
    }
    #expect(
      ReadingOrder.lines(page.shuffled())
        == [
          "Heat the oil in a wide pan and fry the onions.",
          "Add the garlic and cook for one more minute.",
          "Stir in the tomatoes and the stock.",
        ])
  }

  @Test func aSidebarNoteIsReadAfterTheMainText() {
    let main = column(
      ["Roast chicken", "Rub the skin with butter.", "Roast at 200 C.", "Rest for ten minutes."],
      x: 0.06, width: 0.6, top: 0.1)
    let note = column(
      ["Cook's note", "Use a thermometer.", "75 C is done."], x: 0.74, width: 0.2, top: 0.1)
    #expect(ReadingOrder.lines(note + main) == main.map(\.text) + note.map(\.text))
  }

  @Test func aRaggedColumnEdgeDoesNotMoveTheGutter() {
    var left = column(
      ["2 onions, very finely chopped and fried", "1 tbsp oil", "400 g tomatoes"],
      x: 0.08, width: 0.3, top: 0.2)
    // The first line runs further than the rest, into the gap but short of the right column.
    left[0].box.width = 0.38
    let right = column(["Fry.", "Add.", "Simmer."], x: 0.52, width: 0.3, top: 0.2)
    #expect(ReadingOrder.lines(right + left) == left.map(\.text) + right.map(\.text))
  }

  @Test func threeColumnsAreReadOneAfterAnother() {
    let one = column(["a1", "a2", "a3"], x: 0.05, width: 0.25, top: 0.1)
    let two = column(["b1", "b2", "b3"], x: 0.38, width: 0.25, top: 0.1)
    let three = column(["c1", "c2", "c3"], x: 0.71, width: 0.25, top: 0.1)
    #expect(
      ReadingOrder.lines(three + one + two)
        == ["a1", "a2", "a3", "b1", "b2", "b3", "c1", "c2", "c3"])
  }

  @Test func aColumnOfQuantitiesBesideTheirIngredientsIsNotTwoColumns() {
    let quantities = column(["2 cups", "1 tsp", "3", "250 g"], x: 0.1, width: 0.08, top: 0.2)
    let items = column(["flour", "salt", "eggs", "butter"], x: 0.3, width: 0.2, top: 0.2)
    #expect(
      ReadingOrder.lines(items + quantities)
        == ["2 cups flour", "1 tsp salt", "3 eggs", "250 g butter"])
  }

  @Test func fullWidthParagraphsAreNeverSplit() {
    // Short pieces on the right of a page of long lines are not a second column.
    let paragraph = column(
      [
        "Heat the oil in a wide pan.", "Fry the onions until soft.", "Add the garlic.",
        "Stir in the tomatoes.",
      ],
      x: 0.08, width: 0.8, top: 0.2)
    let corner = [piece("p. 3", 0.8, 0.06, 0.1)]
    #expect(
      ReadingOrder.lines(paragraph + corner)
        == ["p. 3"] + paragraph.map(\.text))
  }

  @Test func emptyInputAndUnusableBoxesGiveNothing() {
    #expect(ReadingOrder.lines([]).isEmpty)
    #expect(ReadingOrder.text([]) == "")
    let junk = [
      piece("   ", 0.1, 0.1, 0.3),
      piece("", 0.1, 0.2, 0.3),
      piece("ghost", 0.1, 0.3, 0, 0.02),
      piece("nan", .nan, 0.4, 0.3),
      piece("real", 0.1, 0.5, 0.3),
    ]
    #expect(ReadingOrder.lines(junk) == ["real"])
  }

  @Test func pagesJoinInOrderWithABlankLineAndSkipEmptyOnes() {
    let first = ReadingOrder.text(column(["Soup", "2 onions"], x: 0.1, width: 0.5, top: 0.1))
    let second = ReadingOrder.text(column(["Simmer."], x: 0.1, width: 0.5, top: 0.1))
    #expect(
      ReadingOrder.join(pages: [first, "  \n", second])
        == "Soup\n2 onions\n\nSimmer.")
    #expect(ReadingOrder.join(pages: []) == "")
  }
}
