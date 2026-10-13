extension Copy {
  /// What the Mac's menu bar says that nothing else already does. These strings have no
  /// counterpart in the web copy, so the reference fixture leaves them out. A menu item is a
  /// control, so all of it is plain; the items that name a magic verb (Start brewing, Stir into
  /// the week) reuse the strings of the buttons they mirror instead of having a copy here.
  public struct MacMenu: Sendable {
    /// The menu of places to go: the sections, today, and the days or weeks either side.
    public let goMenu = plain("Go")
    public let newRecipe = plain("New Recipe")
    public let newWindow = plain("New Window")
    /// File > Import Recipe…, which opens Distill. The ellipsis is the Mac's mark for a command that
    /// asks for more before it acts.
    public let importRecipe = plain("Import Recipe…")
    public let findRecipes = plain("Find Recipes")
    public let addMeal = plain("Add Meal")
    public let addItem = plain("Add Item")
    public let logFood = plain("Log Food")
    public let goToToday = plain("Go to Today")
    /// The Go menu's step items when the section has no days or weeks to step through.
    public let previous = plain("Previous")
    public let next = plain("Next")
    public let openInNewWindow = plain("Open in New Window")

    public init() {}
  }
}
