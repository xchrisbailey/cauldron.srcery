/// Every user-facing string, marked `voice` or `plain`, ported from
/// `packages/shared/src/copy.ts`. Views never carry a string literal: they read
/// `Copy.recipes.conjure.text`, or call the function for a string that takes arguments.
///
/// The web app's sign-in and account strings (`auth`, and the account page titles) have no
/// native screen, so they are not here. Nothing is localised yet; every string is a plain
/// `String` inside a `CopyString`, so a String Catalog can take over the lookup later without
/// touching the call sites.
///
/// `settings` is the one native-only section (see `Copy+Settings.swift`); the rest is the
/// web table.
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

    public init() {}
  }
}
