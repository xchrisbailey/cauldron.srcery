extension Copy {
  /// The brand voice: magic verbs with plain nouns. Recipes, ingredients, meals and days
  /// keep their real names.
  public struct Recipes: Sendable {
    public let conjure = voice("Conjure a recipe")
    public let distillFromLink = voice("Distill from a link")
    public let distill = voice("Distill")
    public let summon = voice("Summon a recipe")
    public let startBrewing = voice("Start brewing")
    public let brewed = voice("Brewed")
    public let saving = voice("Simmering…")
    public let saved = voice("Set")
    public let empty = voice("No recipes yet. Conjure one, or distill it from a link.")
    public let tagNameTaken = plain("You already have a tag with that name.")
    /// Under the search field.
    public let summonHint = plain("Search by recipe name, ingredient or tag.")

    public init() {}

    public func stirInto(_ day: String) -> CopyString { voice("Stir into \(day)") }

    /// "Banish" is the voice; the rest is the literal, plain confirmation.
    public func banishConfirm(_ title: String) -> BanishConfirmation {
      BanishConfirmation(
        verb: voice("Banish"),
        confirm: plain("Banish \(title)? You can undo it straight after."))
    }

    /// Title of a duplicated recipe.
    public func copyOf(_ title: String) -> CopyString { plain("\(title) (copy)") }
  }

  public struct BanishConfirmation: Sendable, Hashable {
    public let verb: CopyString
    public let confirm: CopyString
  }

  /// Messages for recipe fields that fail validation. They are plain and say how to fix it.
  public struct Validation: Sendable {
    public let required = plain("Fill this in.")
    public let link = plain("Enter a link starting with https://")
    public let date = plain("Use a real date, like 2026-10-01.")
    public let quantity = plain("Use an amount from 0 up to 99,999,999.")
    public let range = plain("The second amount in a range can't be smaller than the first.")

    public init() {}

    public func tooLong(_ max: Int) -> CopyString {
      plain("Keep it to \(max) characters or fewer.")
    }
    public func tooMany(_ max: Int) -> CopyString { plain("Use \(max) or fewer.") }
    public func wholeNumber(_ min: Int, _ max: Int) -> CopyString {
      plain("Use a whole number from \(min) to \(max).")
    }
    public func numberBetween(_ min: Double, _ max: Double) -> CopyString {
      plain("Use a number from \(number(min)) to \(number(max)).")
    }
  }

  /// The recipe editor. Field labels and errors are plain; the save states ("Simmering…",
  /// "Set") live in `Recipes`.
  public struct Editor: Sendable {
    public let newTitle = voice("Conjure a recipe")
    public let editTitle = plain("Edit recipe")
    public let save = plain("Save recipe")
    public let done = plain("Done")
    public let startOver = plain("Start over")
    public let startOverConfirm = plain("Clear this draft and start over?")
    public let draftKept = plain("Draft kept on this device")
    public let couldntSave = plain("Couldn't save. Check your connection and try again.")
    public let leaveTitle = plain("Leave without saving?")
    public let leaveBody = plain("Your latest changes haven't been saved yet.")
    public let leave = plain("Leave")
    public let stay = plain("Keep editing")
    public let title = plain("Title")
    public let description = plain("Description")
    public let servings = plain("Serves")
    public let prepMinutes = plain("Prep (min)")
    public let cookMinutes = plain("Cook (min)")
    public let totalMinutes = plain("Total (min)")
    public let macros = plain("Per serving")
    public let macrosHint = plain("Optional. The week adds these up for each day.")
    /// Asks the model to estimate the macros from the ingredients.
    public let divineMacros = voice("Divine from ingredients")
    public let divining = voice("Divining…")
    public let divined = plain("Estimated from the ingredients. Check them before you save.")
    public let divineNeedsIngredients = plain("Add some ingredients first.")
    public let divineUnavailable = plain("Estimating needs an AI model, and none is set up.")
    public let divineFailed = plain(
      "Couldn't estimate the macros. Try again, or fill them in yourself.")
    public let macroFields = MacroFields()
    public let sourceUrl = plain("Source link")
    public let tags = plain("Tags")
    public let tagsHint = plain("Press Enter or comma to add a tag.")
    public let notes = plain("Notes")
    public let ingredients = plain("Ingredients")
    public let ingredientsHint = plain(
      "One ingredient per line, like \"1 1/2 cups flour, sifted\". Paste a whole list to split it. A line like \"For the sauce:\" starts a section."
    )
    public let addIngredient = plain("Add ingredient")
    public let addHeading = plain("Add section")
    public let steps = plain("Method")
    public let stepsHint = plain(
      "Enter starts a new step and Shift+Enter a new line. Times like \"bake 25 minutes\" become timers."
    )
    public let addStep = plain("Add step")
    public let remove = plain("Remove")
    public let move = plain("Move")
    public let moveHint = plain(
      "Drag, or press the arrow keys, to reorder. Alt plus an arrow key moves a row from its field."
    )
    public let fix = plain("Fix")
    public let resetLine = plain("Read it from the line again")
    public let quantity = plain("Quantity")
    public let unit = plain("Unit")
    public let noUnit = plain("No unit")
    public let item = plain("Ingredient")
    public let note = plain("Note")
    public let optional = plain("Optional")
    public let addTimer = plain("Add timer")
    public let changeTimer = plain("Change timer")
    public let timerMinutes = plain("Timer (min)")
    public let clearTimer = plain("Remove timer")
    public let needsALook = plain("Check this")
    public let fixErrors = plain("Some fields need a fix before this can be saved.")
    /// For a quantity typed into the correction fields.
    public let badQuantity = plain("Use a number, a fraction like 1 1/2, or a range like 2-3.")

    public init() {}

    public struct MacroFields: Sendable {
      public let calories = plain("Calories")
      public let protein = plain("Protein (g)")
      public let carbs = plain("Carbs (g)")
      public let fat = plain("Fat (g)")

      public init() {}
    }

    public func removeTag(_ name: String) -> CopyString { plain("Remove tag \(name)") }
    public func ingredientLine(_ n: Int) -> CopyString { plain("Ingredient \(n)") }
    public func heading(_ n: Int) -> CopyString { plain("Section heading \(n)") }
    public func step(_ n: Int) -> CopyString { plain("Step \(n)") }
    public func moved(_ n: Int, _ of: Int) -> CopyString {
      plain("Moved to position \(n) of \(of).")
    }
    public func fixLine(_ line: String) -> CopyString { plain("Fix how \"\(line)\" was read") }
  }

  /// The recipe page. Quantities, steps and controls are plain.
  public struct RecipeView: Sendable {
    public let ingredients = plain("Ingredients")
    public let method = plain("Method")
    public let fewer = plain("Fewer servings")
    public let more = plain("More servings")
    public let servingsFor = plain("Servings")
    public let units = plain("Units")
    public let asWritten = plain("As written")
    public let metric = plain("Metric")
    public let us = plain("US")
    public let total = plain("total")
    public let prep = plain("prep")
    public let cook = plain("cook")
    public let edit = plain("Edit")
    public let duplicate = plain("Duplicate")
    public let duplicated = plain("Copy made. You're editing it now.")
    public let print = plain("Print")
    public let markBrewed = voice("Brewed it today")
    public let brewedToday = voice("Brewed. Marked as cooked today.")
    public let optional = plain("optional")
    public let undo = plain("Undo")
    public let restored = plain("Restored.")
    public let cancel = plain("Cancel")
    public let notFound = plain("We couldn't find that recipe. It may have been banished.")
    public let backToRecipes = plain("Back to recipes")

    public init() {}

    public func checked(_ n: Int, _ of: Int) -> CopyString { plain("\(n) of \(of)") }
    public func serves(_ n: Int) -> CopyString { plain("serves \(n)") }
    public func scale(_ factor: String) -> CopyString { plain("×\(factor)") }
    public func from(_ source: String) -> CopyString { plain("From \(source)") }
    public func by(_ author: String) -> CopyString { plain("by \(author)") }
    public func lastCooked(_ date: String) -> CopyString { plain("Last cooked \(date)") }
    public func banished(_ title: String) -> CopyString { plain("Banished \(title).") }
  }

  /// The recipe library. Controls and counts are plain.
  public struct Library: Sendable {
    public let search = plain("Search recipes")
    public let searchPlaceholder = plain("Name, ingredient or tag")
    public let sort = plain("Sort")
    public let sortRecent = plain("Newest")
    public let sortTitle = plain("A to Z")
    public let sortLastCooked = plain("Last cooked")
    public let tag = plain("Tag")
    public let allTags = plain("All tags")
    public let view = plain("View")
    public let grid = plain("Grid")
    public let list = plain("List")
    public let noMatches = plain("No recipes match that. Try another word, or clear the filters.")
    public let clearFilters = plain("Clear filters")
    public let loadingMore = plain("Loading more recipes")
    public let couldntLoadMore = plain("Couldn't load more recipes.")
    public let retry = plain("Try again")
    public let results = plain("Recipes")
    public let actions = plain("Jump to")
    public let openWeek = plain("Open the week")
    public let noResults = plain("Nothing matches. Try another word.")
    public let summonHelp = plain("Use the arrow keys to choose and Enter to open.")
    /// The compact per-serving line on a card, and what it reads aloud. Plain: quantities.
    public let macroLine = MacroLine()

    public init() {}

    public func tagOption(_ name: String, _ n: Int) -> CopyString { plain("\(name) (\(n))") }
    public func count(_ n: Int) -> CopyString { plain(n == 1 ? "1 recipe" : "\(n) recipes") }

    public struct MacroLine: Sendable {
      public let spoken = Spoken()

      public init() {}

      public func calories(_ n: String) -> CopyString { plain("\(n) kcal") }
      public func protein(_ g: String) -> CopyString { plain("\(g)P") }
      public func fat(_ g: String) -> CopyString { plain("\(g)F") }
      public func carbs(_ g: String) -> CopyString { plain("\(g)C") }

      public struct Spoken: Sendable {
        public init() {}

        public func calories(_ n: String) -> CopyString { plain("\(n) kcal") }
        public func protein(_ g: String) -> CopyString { plain("\(g) g protein") }
        public func fat(_ g: String) -> CopyString { plain("\(g) g fat") }
        public func carbs(_ g: String) -> CopyString { plain("\(g) g carbs") }
        public func label(_ parts: String) -> CopyString { plain("Per serving: \(parts)") }
      }
    }
  }

  /// Recipe photos. Plain, since they're controls and errors.
  public struct Photos: Sendable {
    public let add = plain("Add a photo")
    public let replace = plain("Replace photo")
    public let remove = plain("Remove photo")
    public let uploading = plain("Uploading photo…")
    public let unsupported = plain("Use a JPEG, PNG, WebP or AVIF photo.")
    public let tooLarge = plain("That photo is over 15 MB. Try a smaller one.")
    public let tooBig = plain("That photo is too large to process. Try a smaller one.")
    public let couldntRead = plain("We couldn't read that photo. Try another one.")
    public let couldntFetch = plain("We couldn't fetch a photo from that link.")
    public let uploadExpired = plain("That upload has expired. Choose the photo again.")
    public let storageFull = plain(
      "Your photo storage is full. Take photos off recipes you no longer need; the space comes back within a day."
    )

    public init() {}

    public func alt(_ title: String) -> CopyString { plain("Photo of \(title)") }
  }
}
