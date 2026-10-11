extension Copy {
  /// The week. Stirring in is voice; days, meals, controls and the literal part of the clear
  /// confirmation are plain.
  public struct Week: Sendable {
    public let title = plain("The week")
    public let empty = voice("The cauldron's cold. Stir in a recipe to start the week.")
    public let slots = Slots()
    public let previousWeek = plain("Previous week")
    public let nextWeek = plain("Next week")
    public let thisWeek = plain("This week")
    public let today = plain("today")
    public let days = plain("Days")
    public let copyLastWeek = plain("Copy last week")
    public let copiedLastWeek = plain("Copied last week's meals.")
    public let nothingToCopy = plain("Last week has nothing planned.")
    /// "Clear" is a plain verb here: it removes things.
    public let clearWeek = plain("Clear week")
    public let cleared = plain("Cleared the week.")
    public let cancel = plain("Cancel")
    public let stirIn = voice("Stir in")
    public let stirIntoWeek = voice("Stir into the week")
    // The meal-picker: search the recipe box, or write a meal that isn't a recipe.
    public let searchRecipes = plain("Search your recipes")
    public let noMatches = plain("No recipes match that.")
    public let orWrite = plain("Or write a meal")
    public let writePlaceholder = plain("Leftovers, eating out…")
    public let add = plain("Add")
    public let day = plain("Day")
    public let slot = plain("Meal")
    public let servings = plain("Servings")
    public let open = plain("Open recipe")
    public let remove = plain("Remove")
    public let undo = plain("Undo")
    public let save = plain("Save")
    public let brewed = voice("✓ brewed")
    public let leftovers = plain("not a recipe")
    public let recipesPanel = plain("Recipes")
    public let dragHint = plain("Drag a recipe onto a meal, or press + on a meal to stir one in.")
    public let moveHint = plain("Drag a meal to move it to another day.")
    public let weekStarts = plain("Week starts on")
    public let monday = plain("Monday")
    public let sunday = plain("Sunday")
    public let couldntSave = plain(
      "Couldn't save that change. Check your connection and try again.")
    public let couldntLoad = plain("Couldn't load the week.")
    public let retry = plain("Try again")
    public let slotFull = plain("That meal is full. Remove something first.")
    public let moveUp = plain("Move up")
    public let moveDown = plain("Move down")
    public let meal = plain("Meal")
    /// The running tally of calories and macros: all plain, they're numbers.
    public let tally = Tally()
    /// Spreading one recipe's servings over the days that will eat them.
    public let spread = Spread()

    public init() {}

    public func clearConfirm(_ range: String) -> CopyString {
      plain("Clear every meal planned for \(range)? This can't be undone.")
    }
    public func stirInto(_ day: String, _ slot: String) -> CopyString {
      voice("Stir into \(day), \(slot.lowercased())")
    }
    public func stirred(_ day: String) -> CopyString { voice("Stirred into \(day).") }
    public func sameServings(_ n: Int?) -> CopyString {
      guard let n else { return plain("As the recipe") }
      return plain("As the recipe (\(n))")
    }
    public func edit(_ title: String) -> CopyString { plain("Change \(title)") }
    public func removed(_ title: String) -> CopyString { plain("Removed \(title).") }

    public struct Slots: Sendable {
      public let breakfast = plain("Breakfast")
      public let lunch = plain("Lunch")
      public let dinner = plain("Dinner")
      public let snack = plain("Snack")

      public init() {}

      /// The label for a meal slot.
      public subscript(slot: MealSlot) -> CopyString {
        switch slot {
        case .breakfast: breakfast
        case .lunch: lunch
        case .dinner: dinner
        case .snack: snack
        }
      }
    }

    public struct Tally: Sendable {
      public let label = plain("Calories and macros")
      public let week = plain("Week")
      public let perDay = plain("a day")
      public let macros = Macros()
      public let none = plain("Add calories and macros to your recipes to see totals here.")
      public let clearDay = plain("Back to the week")

      public init() {}

      public func gaps(_ n: Int) -> CopyString {
        plain(
          n == 1
            ? "1 meal has no calories or macros, so it isn't fully counted."
            : "\(n) meals have no calories or macros, so they aren't fully counted.")
      }
      public func showDay(_ day: String) -> CopyString { plain("Show \(day)") }

      public struct Macros: Sendable {
        public let calories = plain("kcal")
        public let protein = plain("protein")
        public let carbs = plain("carbs")
        public let fat = plain("fat")

        public init() {}
      }
    }

    public struct Spread: Sendable {
      public let days = plain("Days")
      public let hint = plain(
        "Pick the days this batch feeds. Each day gets one serving unless you change it.")
      public let oneADay = plain("One a day")
      public let pickADay = plain("Pick at least one day.")

      public init() {}

      public func planned(_ n: Int, _ of: Int?) -> CopyString {
        guard let of else { return plain("\(n) \(n == 1 ? "serving" : "servings") planned") }
        return plain("\(n) of \(of) servings planned")
      }
      public func allOn(_ day: String) -> CopyString { plain("All on \(day)") }
      public func fewer(_ day: String) -> CopyString { plain("Fewer servings on \(day)") }
      public func more(_ day: String) -> CopyString { plain("More servings on \(day)") }
      public func servingsOn(_ n: Int) -> CopyString {
        plain("\(n) \(n == 1 ? "serving" : "servings")")
      }
      public func stir(_ n: Int) -> CopyString {
        voice(n == 1 ? "Stir into 1 day" : "Stir into \(n) days")
      }
      public func stirred(_ n: Int) -> CopyString {
        voice(n == 1 ? "Stirred into 1 day." : "Stirred into \(n) days.")
      }
    }
  }

  /// The Gather list. Gather is voice; aisles, items, amounts and controls are plain.
  public struct Gather: Sendable {
    public let title = voice("Gather list")
    public let empty = voice(
      "Nothing to gather yet. Stir recipes into the week and the list fills itself.")
    public let gather = voice("Gather")
    public let aisles = Aisles()
    public let addItem = plain("Add an item")
    public let addPlaceholder = plain("2 lemons, oat milk…")
    public let add = plain("Add")
    public let hideChecked = plain("Hide checked")
    public let addedByHand = plain("Added by you")
    public let inPantry = plain("In the pantry")
    public let allChecked = voice("Everything's gathered. Time to brew.")
    public let couldntSave = plain(
      "Couldn't save that change. Check your connection and try again.")
    public let couldntLoad = plain("Couldn't load the Gather list.")
    public let retry = plain("Try again")

    public init() {}

    public func checked(_ n: Int, _ of: Int) -> CopyString { plain("\(n) of \(of) gathered") }
    public func forRecipes(_ titles: String) -> CopyString { plain("For \(titles)") }
    public func markInPantry(_ item: String) -> CopyString { plain("\(item) is in the pantry") }
    public func remove(_ item: String) -> CopyString { plain("Remove \(item)") }
    public func summary(_ items: Int, _ recipes: Int) -> CopyString {
      let ingredients = items == 1 ? "1 ingredient" : "\(items) ingredients"
      let recipeCount = recipes == 1 ? "1 recipe" : "\(recipes) recipes"
      return plain("\(ingredients) across \(recipeCount).")
    }
    public func inPantryCount(_ n: Int) -> CopyString {
      plain(n == 1 ? "1 is already in the pantry." : "\(n) are already in the pantry.")
    }

    public struct Aisles: Sendable {
      public let produce = plain("Produce")
      public let meat = plain("Meat and fish")
      public let dairy = plain("Dairy and eggs")
      public let bakery = plain("Bakery")
      public let pantry = plain("Pantry")
      public let spices = plain("Spices")
      public let frozen = plain("Frozen")
      public let drinks = plain("Drinks")
      public let other = plain("Other")

      public init() {}

      /// The label for an aisle.
      public subscript(aisle: Aisle) -> CopyString {
        switch aisle {
        case .produce: produce
        case .meat: meat
        case .dairy: dairy
        case .bakery: bakery
        case .pantry: pantry
        case .spices: spices
        case .frozen: frozen
        case .drinks: drinks
        case .other: other
        }
      }
    }
  }
}
