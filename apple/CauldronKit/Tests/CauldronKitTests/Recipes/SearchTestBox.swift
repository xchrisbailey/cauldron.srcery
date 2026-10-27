import CauldronKit
import Foundation

/// A small recipe box for search tests: titles and the words a recipe holds, in the shape the
/// app gives the index (`searchText` plus the description, lowercased).
enum SearchTestBox {
  static func entry(
    _ title: String, tags: [String] = [], items: [String] = [], summary: String = "", id: UInt8
  ) -> RecipeSearchIndex.Entry {
    let document = ([title] + items + tags).joined(separator: " ").lowercased() + " " + summary
    return RecipeSearchIndex.Entry(
      id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id)), title: title,
      document: document.lowercased())
  }

  /// The five sample recipes of the app and the five more that #245 assumes a box will hold,
  /// with ingredient items as the line parser leaves them.
  static let corpus: [RecipeSearchIndex.Entry] = [
    entry(
      "Shakshuka with feta", tags: ["Middle Eastern", "Breakfast", "Vegetarian"],
      items: [
        "olive oil", "onion", "red bell pepper", "garlic", "ground cumin", "smoked paprika",
        "chili flakes", "crushed tomatoes", "salt and pepper", "eggs", "crumbled feta", "parsley",
      ],
      summary: "Eggs poached in a spiced tomato and pepper sauce, finished with feta and herbs.",
      id: 1),
    entry(
      "Weeknight chicken thighs with lemon and garlic", tags: ["Dinner", "Gluten-free"],
      items: [
        "chicken thighs", "small potatoes", "olive oil", "lemon", "garlic", "thyme",
        "kosher salt", "black pepper",
      ],
      summary: "Crisp-skinned thighs roasted over potatoes with lemon, garlic and thyme.", id: 2),
    entry(
      "Overnight oats", tags: ["Breakfast", "Vegetarian"],
      items: [
        "rolled oats", "milk", "plain yogurt", "chia seeds", "maple syrup", "salt", "berries",
        "toasted almonds",
      ],
      summary: "Oats soaked in milk and yogurt overnight, ready to eat in the morning.", id: 3),
    entry(
      "Tomato and white bean soup", tags: ["Italian", "Lunch", "Vegan"],
      items: [
        "olive oil", "onion", "carrots", "garlic", "dried oregano", "diced tomatoes",
        "cannellini beans", "vegetable stock", "spinach", "salt",
      ],
      summary: "A quick pantry soup of canned tomatoes and beans, blended until half smooth.",
      id: 4),
    entry(
      "Brown butter chocolate chip cookies", tags: ["Dessert"],
      items: [
        "unsalted butter", "brown sugar", "granulated sugar", "eggs", "vanilla extract",
        "all-purpose flour", "baking soda", "kosher salt", "chocolate chips", "flaky salt",
      ],
      summary: "Chewy cookies with nutty brown butter and a little flaky salt.", id: 5),
    entry(
      "Pad thai",
      items: [
        "rice noodles", "peanuts", "scallions", "tamarind", "fish sauce", "chili",
      ], id: 6),
    entry(
      "Aubergine parmigiana",
      items: ["aubergine", "mozzarella", "parmesan", "basil", "tomato"], id: 7),
    entry(
      "Chicken tikka masala",
      items: ["chicken", "yoghurt", "garam masala", "cream", "coriander"], id: 8),
    entry(
      "Kimchi fried rice",
      items: ["day-old cooked rice", "kimchi", "egg", "gochujang", "spring onion"], id: 9),
    entry(
      "Guacamole", items: ["avocado", "lime", "cilantro", "jalapeño", "red onion"], id: 10),
  ]

  static func title(of id: UUID, in box: [RecipeSearchIndex.Entry] = corpus) -> String {
    box.first { $0.id == id }?.title ?? "?"
  }

  /// The titles a search finds, in result order.
  static func titles(
    _ text: String, in box: [RecipeSearchIndex.Entry] = corpus
  ) -> [String] {
    RecipeSearchIndex(box).search(text).map { title(of: $0.id, in: box) }
  }
}
