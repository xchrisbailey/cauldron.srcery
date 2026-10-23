/// Every user-facing string, marked `voice` or `plain`, ported from
/// `packages/shared/src/copy.ts`. Views never carry a string literal: they read
/// `Copy.recipes.conjure.text`, or call the function for a string that takes arguments.
///
/// The web app's sign-in and account strings (`auth`, and the account page titles) have no
/// native screen, so they are not here. Nothing is localised yet; every string is a plain
/// `String` inside a `CopyString`, so a String Catalog can take over the lookup later without
/// touching the call sites.
///
/// `settings`, `export`, `recipeEditor`, `brewMode`, `macMenu`, `describeNative`,
/// `importNative` and `libraryNative` are the native-only sections (see `Copy+Settings.swift`,
/// `Copy+Export.swift`, `Copy+RecipeEditor.swift`, `Copy+BrewMode.swift`,
/// `Copy+MacMenu.swift`, `Copy+DescribeNative.swift` and `Copy+ImportNative.swift`); the rest
/// is the web table.
public enum Copy {
  /// The whole table as one value, so tests can walk it.
  public static let catalogue = Catalogue()

  public static let errors = catalogue.errors
  public static let recipes = catalogue.recipes
  public static let validation = catalogue.validation
  public static let editor = catalogue.editor
  public static let recipeView = catalogue.recipeView
  public static let library = catalogue.library
  public static let photos = catalogue.photos
  public static let imports = catalogue.imports
  public static let brewing = catalogue.brewing
  public static let week = catalogue.week
  public static let gather = catalogue.gather
  public static let tracker = catalogue.tracker
  public static let nav = catalogue.nav
  public static let pageTitles = catalogue.pageTitles
  public static let ui = catalogue.ui
  public static let quantities = catalogue.quantities
  public static let settings = catalogue.settings
  public static let export = catalogue.export
  public static let recipeEditor = catalogue.recipeEditor
  public static let brewMode = catalogue.brewMode
  public static let macMenu = catalogue.macMenu
  public static let describeNative = catalogue.describeNative
  public static let importNative = catalogue.importNative
  public static let libraryNative = catalogue.libraryNative
  public static let display = Display()

  /// Small product-visible formatters that keep punctuation and spacing out of views.
  public struct Display: Sendable {
    public let unavailable = plain("—")

    public init() {}
    public func number(_ value: Int) -> CopyString { plain("\(value)") }
    public func calories(_ value: String, unit: String) -> CopyString {
      plain("\(value) \(unit)")
    }
    public func compactUnit(_ value: String, unit: String) -> CopyString {
      plain("\(value)\(unit)")
    }
    public func macroTotal(
      calories: String, caloriesUnit: String, protein: String, proteinUnit: String,
      carbs: String, carbsUnit: String, fat: String, fatUnit: String, grams: String
    ) -> CopyString {
      plain(
        "\(calories) \(caloriesUnit) · \(protein)\(grams) \(proteinUnit) · \(carbs)\(grams) \(carbsUnit) · \(fat)\(grams) \(fatUnit)"
      )
    }
    public func target(_ value: String) -> CopyString { plain("/ \(value)") }
    public func proposedTarget(_ value: String, unit: String) -> CopyString {
      plain("\(value) \(unit)")
    }
    public func parenthesized(_ value: String) -> CopyString { plain("(\(value))") }
    public func alternative(_ amount: String, unit: String) -> CopyString {
      plain("(\(amount) \(unit))")
    }
    public func duplicateWarning(_ title: String, saveAnyway: String) -> CopyString {
      plain("\(title) \(saveAnyway)")
    }
    public func accessibleStep(_ step: String, text: String) -> CopyString {
      plain("\(step). \(text)")
    }
    public func accessibleStepAndTimer(_ step: String, text: String, timer: String?) -> CopyString {
      plain("\(step). \(text)\(timer.map { " \($0)" } ?? "")")
    }
    public func leaveRecipe(_ leave: String, title: String) -> CopyString {
      plain("\(leave): \(title)")
    }
    public func withSuffix(_ text: String, suffix: String) -> CopyString {
      plain("\(text) \(suffix)")
    }
  }

  public struct Catalogue: Sendable {
    public let errors = Errors()
    public let recipes = Recipes()
    public let validation = Validation()
    public let editor = Editor()
    public let recipeView = RecipeView()
    public let library = Library()
    public let photos = Photos()
    public let imports = Imports()
    public let brewing = Brewing()
    public let week = Week()
    public let gather = Gather()
    public let tracker = Tracker()
    public let nav = Nav()
    public let pageTitles = PageTitles()
    public let ui = UI()
    public let quantities = Quantities()
    public let settings = Settings()
    public let export = Export()
    public let recipeEditor = RecipeEditorNative()
    public let brewMode = BrewModeNative()
    public let macMenu = MacMenu()
    public let describeNative = DescribeNative()
    public let importNative = ImportNative()
    public let libraryNative = LibraryNative()

    public init() {}
  }
}
