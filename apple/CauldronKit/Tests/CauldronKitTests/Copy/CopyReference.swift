// Every string of packages/shared/src/copy.ts (the TypeScript reference), dumped once as the
// fixture the Swift copy module is compared against. Sign-in and account strings are left
// out. It is data: don't edit it by hand, and regenerate it only from the reference.

import CauldronKit

struct CopyReferenceString: Sendable {
  let path: String
  let tone: Tone
  let text: String
}

struct CopyReferenceCall: Sendable {
  let call: String
  let actual: CopyString
  let tone: Tone
  let text: String
}

enum CopyReference {
  /// Every string without arguments, by dotted path.
  static let strings: [CopyReferenceString] = [
    .init(path: "brewing.nextStep", tone: .plain, text: "Next step"),
    .init(path: "brewing.previousStep", tone: .plain, text: "Previous step"),
    .init(path: "brewing.leave", tone: .plain, text: "Back to the recipe"),
    .init(path: "brewing.forThisStep", tone: .plain, text: "For this step"),
    .init(path: "brewing.startTimer", tone: .plain, text: "Start timer"),
    .init(path: "brewing.pause", tone: .plain, text: "Pause"),
    .init(path: "brewing.resume", tone: .plain, text: "Resume"),
    .init(path: "brewing.reset", tone: .plain, text: "Reset"),
    .init(path: "brewing.timeUp", tone: .plain, text: "Time's up"),
    .init(path: "brewing.timers", tone: .plain, text: "Timers"),
    .init(path: "brewing.wakeOn", tone: .plain, text: "Screen stays on while you brew"),
    .init(
      path: "brewing.wakeOff", tone: .plain,
      text: "This browser can't keep the screen on, so it may sleep."),
    .init(
      path: "brewing.wakeRefused", tone: .plain,
      text: "The browser wouldn't keep the screen on just now, so it may sleep."),
    .init(
      path: "brewing.keys", tone: .plain,
      text: "Arrow keys move between steps. Space starts or pauses the timer."),
    .init(
      path: "brewing.noSteps", tone: .plain,
      text: "This recipe has no method steps yet. Add some, then start brewing."),
    .init(path: "brewing.editRecipe", tone: .plain, text: "Edit recipe"),
    .init(path: "brewing.brewed", tone: .voice, text: "Brewed"),
    .init(
      path: "brewing.couldntSave", tone: .plain,
      text: "Couldn't mark it cooked. Check your connection and try again."),
    .init(path: "editor.newTitle", tone: .voice, text: "Conjure a recipe"),
    .init(path: "editor.editTitle", tone: .plain, text: "Edit recipe"),
    .init(path: "editor.save", tone: .plain, text: "Save recipe"),
    .init(path: "editor.done", tone: .plain, text: "Done"),
    .init(path: "editor.startOver", tone: .plain, text: "Start over"),
    .init(path: "editor.startOverConfirm", tone: .plain, text: "Clear this draft and start over?"),
    .init(path: "editor.draftKept", tone: .plain, text: "Draft kept on this device"),
    .init(
      path: "editor.couldntSave", tone: .plain,
      text: "Couldn't save. Check your connection and try again."),
    .init(path: "editor.leaveTitle", tone: .plain, text: "Leave without saving?"),
    .init(
      path: "editor.leaveBody", tone: .plain, text: "Your latest changes haven't been saved yet."),
    .init(path: "editor.leave", tone: .plain, text: "Leave"),
    .init(path: "editor.stay", tone: .plain, text: "Keep editing"),
    .init(path: "editor.title", tone: .plain, text: "Title"),
    .init(path: "editor.description", tone: .plain, text: "Description"),
    .init(path: "editor.servings", tone: .plain, text: "Serves"),
    .init(path: "editor.prepMinutes", tone: .plain, text: "Prep (min)"),
    .init(path: "editor.cookMinutes", tone: .plain, text: "Cook (min)"),
    .init(path: "editor.totalMinutes", tone: .plain, text: "Total (min)"),
    .init(path: "editor.macros", tone: .plain, text: "Per serving"),
    .init(
      path: "editor.macrosHint", tone: .plain,
      text: "Optional. The week adds these up for each day."),
    .init(path: "editor.divineMacros", tone: .voice, text: "Divine from ingredients"),
    .init(path: "editor.divining", tone: .voice, text: "Divining…"),
    .init(
      path: "editor.divined", tone: .plain,
      text: "Estimated from the ingredients. Check them before you save."),
    .init(path: "editor.divineNeedsIngredients", tone: .plain, text: "Add some ingredients first."),
    .init(
      path: "editor.divineUnavailable", tone: .plain,
      text: "Estimating needs an AI model, and none is set up."),
    .init(
      path: "editor.divineFailed", tone: .plain,
      text: "Couldn't estimate the macros. Try again, or fill them in yourself."),
    .init(path: "editor.macroFields.calories", tone: .plain, text: "Calories"),
    .init(path: "editor.macroFields.protein", tone: .plain, text: "Protein (g)"),
    .init(path: "editor.macroFields.carbs", tone: .plain, text: "Carbs (g)"),
    .init(path: "editor.macroFields.fat", tone: .plain, text: "Fat (g)"),
    .init(path: "editor.sourceUrl", tone: .plain, text: "Source link"),
    .init(path: "editor.tags", tone: .plain, text: "Tags"),
    .init(path: "editor.tagsHint", tone: .plain, text: "Press Enter or comma to add a tag."),
    .init(path: "editor.notes", tone: .plain, text: "Notes"),
    .init(path: "editor.ingredients", tone: .plain, text: "Ingredients"),
    .init(
      path: "editor.ingredientsHint", tone: .plain,
      text:
        "One ingredient per line, like \"1 1/2 cups flour, sifted\". Paste a whole list to split it. A line like \"For the sauce:\" starts a section."
    ),
    .init(path: "editor.addIngredient", tone: .plain, text: "Add ingredient"),
    .init(path: "editor.addHeading", tone: .plain, text: "Add section"),
    .init(path: "editor.steps", tone: .plain, text: "Method"),
    .init(
      path: "editor.stepsHint", tone: .plain,
      text:
        "Enter starts a new step and Shift+Enter a new line. Times like \"bake 25 minutes\" become timers."
    ),
    .init(path: "editor.addStep", tone: .plain, text: "Add step"),
    .init(path: "editor.remove", tone: .plain, text: "Remove"),
    .init(path: "editor.move", tone: .plain, text: "Move"),
    .init(
      path: "editor.moveHint", tone: .plain,
      text:
        "Drag, or press the arrow keys, to reorder. Alt plus an arrow key moves a row from its field."
    ),
    .init(path: "editor.fix", tone: .plain, text: "Fix"),
    .init(path: "editor.resetLine", tone: .plain, text: "Read it from the line again"),
    .init(path: "editor.quantity", tone: .plain, text: "Quantity"),
    .init(path: "editor.unit", tone: .plain, text: "Unit"),
    .init(path: "editor.noUnit", tone: .plain, text: "No unit"),
    .init(path: "editor.item", tone: .plain, text: "Ingredient"),
    .init(path: "editor.note", tone: .plain, text: "Note"),
    .init(path: "editor.optional", tone: .plain, text: "Optional"),
    .init(path: "editor.addTimer", tone: .plain, text: "Add timer"),
    .init(path: "editor.changeTimer", tone: .plain, text: "Change timer"),
    .init(path: "editor.timerMinutes", tone: .plain, text: "Timer (min)"),
    .init(path: "editor.clearTimer", tone: .plain, text: "Remove timer"),
    .init(path: "editor.needsALook", tone: .plain, text: "Check this"),
    .init(
      path: "editor.fixErrors", tone: .plain,
      text: "Some fields need a fix before this can be saved."),
    .init(
      path: "editor.badQuantity", tone: .plain,
      text: "Use a number, a fraction like 1 1/2, or a range like 2-3."),
    .init(path: "errors.forbidden", tone: .plain, text: "You don't have access to that."),
    .init(path: "errors.notFound", tone: .plain, text: "We couldn't find that."),
    .init(
      path: "errors.invalidRequest", tone: .plain,
      text: "Something in that request wasn't right. Check it and try again."),
    .init(
      path: "errors.tooManyRequests", tone: .plain,
      text: "That's a lot of requests at once. Wait a moment and try again."),
    .init(
      path: "errors.internal", tone: .plain,
      text: "Something went wrong on our side. Try again in a moment."),
    .init(
      path: "errors.unavailable", tone: .plain,
      text: "Cauldron can't reach its database right now. Try again in a moment."),
    .init(
      path: "errors.crossSite", tone: .plain,
      text: "That request came from another site, so we didn't run it."),
    .init(path: "gather.title", tone: .voice, text: "Gather list"),
    .init(
      path: "gather.empty", tone: .voice,
      text: "Nothing to gather yet. Stir recipes into the week and the list fills itself."),
    .init(path: "gather.gather", tone: .voice, text: "Gather"),
    .init(path: "gather.aisles.produce", tone: .plain, text: "Produce"),
    .init(path: "gather.aisles.meat", tone: .plain, text: "Meat and fish"),
    .init(path: "gather.aisles.dairy", tone: .plain, text: "Dairy and eggs"),
    .init(path: "gather.aisles.bakery", tone: .plain, text: "Bakery"),
    .init(path: "gather.aisles.pantry", tone: .plain, text: "Pantry"),
    .init(path: "gather.aisles.spices", tone: .plain, text: "Spices"),
    .init(path: "gather.aisles.frozen", tone: .plain, text: "Frozen"),
    .init(path: "gather.aisles.drinks", tone: .plain, text: "Drinks"),
    .init(path: "gather.aisles.other", tone: .plain, text: "Other"),
    .init(path: "gather.addItem", tone: .plain, text: "Add an item"),
    .init(path: "gather.addPlaceholder", tone: .plain, text: "2 lemons, oat milk…"),
    .init(path: "gather.add", tone: .plain, text: "Add"),
    .init(path: "gather.hideChecked", tone: .plain, text: "Hide checked"),
    .init(path: "gather.addedByHand", tone: .plain, text: "Added by you"),
    .init(path: "gather.inPantry", tone: .plain, text: "In the pantry"),
    .init(path: "gather.allChecked", tone: .voice, text: "Everything's gathered. Time to brew."),
    .init(
      path: "gather.couldntSave", tone: .plain,
      text: "Couldn't save that change. Check your connection and try again."),
    .init(path: "gather.couldntLoad", tone: .plain, text: "Couldn't load the Gather list."),
    .init(path: "gather.retry", tone: .plain, text: "Try again"),
    .init(path: "imports.title", tone: .voice, text: "Distill a recipe"),
    .init(path: "imports.distill", tone: .voice, text: "Distill"),
    .init(path: "imports.distilling", tone: .voice, text: "Distilling…"),
    .init(path: "imports.link", tone: .plain, text: "Link"),
    .init(path: "imports.linkPlaceholder", tone: .plain, text: "https://"),
    .init(
      path: "imports.linkHint", tone: .plain, text: "A recipe page, or an Instagram or TikTok post."
    ),
    .init(path: "imports.orPaste", tone: .plain, text: "Or paste the recipe"),
    .init(
      path: "imports.pasteHint", tone: .plain,
      text: "Paste it from anywhere: a notes app, an email, a caption."),
    .init(path: "imports.pastePlaceholder", tone: .plain, text: "Title, ingredients and method"),
    .init(path: "imports.stop", tone: .plain, text: "Stop"),
    .init(path: "imports.stopped", tone: .plain, text: "Stopped."),
    .init(path: "imports.another", tone: .voice, text: "Distill another"),
    .init(path: "imports.review", tone: .plain, text: "Check the highlighted fields, then save."),
    .init(path: "imports.unsureLine", tone: .plain, text: "we may have misread it"),
    .init(path: "imports.source", tone: .plain, text: "Source"),
    .init(path: "imports.pasted", tone: .plain, text: "Pasted text"),
    .init(path: "imports.openDuplicate", tone: .plain, text: "Open it"),
    .init(path: "imports.saveAnyway", tone: .plain, text: "Saving makes a second copy."),
    .init(path: "imports.pasteInstead", tone: .plain, text: "Paste the text instead"),
    .init(path: "imports.tryAgain", tone: .plain, text: "Try again"),
    .init(
      path: "imports.couldntStart", tone: .plain,
      text: "Couldn't start distilling. Check your connection and try again."),
    .init(path: "imports.alreadySaved", tone: .plain, text: "That draft is already saved."),
    .init(path: "imports.notReady", tone: .plain, text: "That draft isn't ready to save."),
    .init(
      path: "imports.couldntRead", tone: .plain,
      text: "Couldn't read that page. Paste the recipe text instead."),
    .init(
      path: "imports.noRecipe", tone: .plain,
      text: "We couldn't find a recipe there. Paste the recipe text instead."),
    .init(
      path: "imports.noRecipeInText", tone: .plain,
      text: "We couldn't find a recipe in that text. Check it has the ingredients and the method."),
    .init(
      path: "imports.spokenOnly", tone: .plain,
      text:
        "That post's caption doesn't have the recipe. It may only be spoken in the video, so paste the recipe text instead."
    ),
    .init(
      path: "imports.tooLarge", tone: .plain,
      text: "That page is too large to read. Paste the recipe text instead."),
    .init(
      path: "imports.blocked", tone: .plain,
      text: "We can't open that link. Paste the recipe text instead."),
    .init(
      path: "imports.timeout", tone: .plain,
      text: "That took too long. Try again, or paste the recipe text instead."),
    .init(
      path: "imports.unavailable", tone: .plain,
      text:
        "Distilling isn't available right now. Try again in a moment, or conjure the recipe by hand."
    ),
    .init(
      path: "imports.dailyLimit", tone: .plain,
      text:
        "That's a lot of distilling for one day. Try again tomorrow, or conjure the recipe by hand."
    ),
    .init(path: "library.search", tone: .plain, text: "Search recipes"),
    .init(path: "library.searchPlaceholder", tone: .plain, text: "Name, ingredient or tag"),
    .init(path: "library.sort", tone: .plain, text: "Sort"),
    .init(path: "library.sortRecent", tone: .plain, text: "Newest"),
    .init(path: "library.sortTitle", tone: .plain, text: "A to Z"),
    .init(path: "library.sortLastCooked", tone: .plain, text: "Last cooked"),
    .init(path: "library.tag", tone: .plain, text: "Tag"),
    .init(path: "library.allTags", tone: .plain, text: "All tags"),
    .init(path: "library.view", tone: .plain, text: "View"),
    .init(path: "library.grid", tone: .plain, text: "Grid"),
    .init(path: "library.list", tone: .plain, text: "List"),
    .init(
      path: "library.noMatches", tone: .plain,
      text: "No recipes match that. Try another word, or clear the filters."),
    .init(path: "library.clearFilters", tone: .plain, text: "Clear filters"),
    .init(path: "library.loadingMore", tone: .plain, text: "Loading more recipes"),
    .init(path: "library.couldntLoadMore", tone: .plain, text: "Couldn't load more recipes."),
    .init(path: "library.retry", tone: .plain, text: "Try again"),
    .init(path: "library.results", tone: .plain, text: "Recipes"),
    .init(path: "library.actions", tone: .plain, text: "Jump to"),
    .init(path: "library.openWeek", tone: .plain, text: "Open the week"),
    .init(path: "library.noResults", tone: .plain, text: "Nothing matches. Try another word."),
    .init(
      path: "library.summonHelp", tone: .plain,
      text: "Use the arrow keys to choose and Enter to open."),
    .init(path: "nav.recipes", tone: .plain, text: "Recipes"),
    .init(path: "nav.week", tone: .plain, text: "The week"),
    .init(path: "nav.gather", tone: .voice, text: "Gather list"),
    .init(path: "nav.tracker", tone: .plain, text: "Tracker"),
    .init(path: "pageTitles.recipe", tone: .plain, text: "Recipe"),
    .init(path: "pageTitles.brew", tone: .plain, text: "Brew"),
    .init(path: "photos.add", tone: .plain, text: "Add a photo"),
    .init(path: "photos.replace", tone: .plain, text: "Replace photo"),
    .init(path: "photos.remove", tone: .plain, text: "Remove photo"),
    .init(path: "photos.uploading", tone: .plain, text: "Uploading photo…"),
    .init(path: "photos.unsupported", tone: .plain, text: "Use a JPEG, PNG, WebP or AVIF photo."),
    .init(
      path: "photos.tooLarge", tone: .plain, text: "That photo is over 15 MB. Try a smaller one."),
    .init(
      path: "photos.tooBig", tone: .plain,
      text: "That photo is too large to process. Try a smaller one."),
    .init(
      path: "photos.couldntRead", tone: .plain,
      text: "We couldn't read that photo. Try another one."),
    .init(
      path: "photos.couldntFetch", tone: .plain, text: "We couldn't fetch a photo from that link."),
    .init(
      path: "photos.uploadExpired", tone: .plain,
      text: "That upload has expired. Choose the photo again."),
    .init(
      path: "photos.storageFull", tone: .plain,
      text:
        "Your photo storage is full. Take photos off recipes you no longer need; the space comes back within a day."
    ),
    .init(path: "quantities.pinch", tone: .plain, text: "pinch"),
    .init(path: "recipeView.ingredients", tone: .plain, text: "Ingredients"),
    .init(path: "recipeView.method", tone: .plain, text: "Method"),
    .init(path: "recipeView.fewer", tone: .plain, text: "Fewer servings"),
    .init(path: "recipeView.more", tone: .plain, text: "More servings"),
    .init(path: "recipeView.servingsFor", tone: .plain, text: "Servings"),
    .init(path: "recipeView.units", tone: .plain, text: "Units"),
    .init(path: "recipeView.asWritten", tone: .plain, text: "As written"),
    .init(path: "recipeView.metric", tone: .plain, text: "Metric"),
    .init(path: "recipeView.us", tone: .plain, text: "US"),
    .init(path: "recipeView.total", tone: .plain, text: "total"),
    .init(path: "recipeView.prep", tone: .plain, text: "prep"),
    .init(path: "recipeView.cook", tone: .plain, text: "cook"),
    .init(path: "recipeView.edit", tone: .plain, text: "Edit"),
    .init(path: "recipeView.duplicate", tone: .plain, text: "Duplicate"),
    .init(path: "recipeView.duplicated", tone: .plain, text: "Copy made. You're editing it now."),
    .init(path: "recipeView.print", tone: .plain, text: "Print"),
    .init(path: "recipeView.markBrewed", tone: .voice, text: "Brewed it today"),
    .init(path: "recipeView.brewedToday", tone: .voice, text: "Brewed. Marked as cooked today."),
    .init(path: "recipeView.optional", tone: .plain, text: "optional"),
    .init(path: "recipeView.undo", tone: .plain, text: "Undo"),
    .init(path: "recipeView.restored", tone: .plain, text: "Restored."),
    .init(path: "recipeView.cancel", tone: .plain, text: "Cancel"),
    .init(
      path: "recipeView.notFound", tone: .plain,
      text: "We couldn't find that recipe. It may have been banished."),
    .init(path: "recipeView.backToRecipes", tone: .plain, text: "Back to recipes"),
    .init(path: "recipes.conjure", tone: .voice, text: "Conjure a recipe"),
    .init(path: "recipes.distillFromLink", tone: .voice, text: "Distill from a link"),
    .init(path: "recipes.distill", tone: .voice, text: "Distill"),
    .init(path: "recipes.summon", tone: .voice, text: "Summon a recipe"),
    .init(path: "recipes.startBrewing", tone: .voice, text: "Start brewing"),
    .init(path: "recipes.brewed", tone: .voice, text: "Brewed"),
    .init(path: "recipes.saving", tone: .voice, text: "Simmering…"),
    .init(path: "recipes.saved", tone: .voice, text: "Set"),
    .init(
      path: "recipes.empty", tone: .voice,
      text: "No recipes yet. Conjure one, or distill it from a link."),
    .init(
      path: "recipes.tagNameTaken", tone: .plain, text: "You already have a tag with that name."),
    .init(
      path: "recipes.summonHint", tone: .plain, text: "Search by recipe name, ingredient or tag."),
    .init(path: "tracker.title", tone: .plain, text: "Tracker"),
    .init(path: "tracker.dayFull", tone: .plain, text: "That day is full. Remove something first."),
    .init(path: "tracker.targets.title", tone: .voice, text: "Set your targets"),
    .init(path: "tracker.targets.pageTitle", tone: .plain, text: "Targets"),
    .init(path: "tracker.targets.steps.about", tone: .plain, text: "About you"),
    .init(path: "tracker.targets.steps.activity", tone: .plain, text: "Activity and goal"),
    .init(path: "tracker.targets.steps.targets", tone: .plain, text: "Your targets"),
    .init(path: "tracker.targets.sex", tone: .plain, text: "Sex"),
    .init(path: "tracker.targets.sexes.female", tone: .plain, text: "Female"),
    .init(path: "tracker.targets.sexes.male", tone: .plain, text: "Male"),
    .init(path: "tracker.targets.sexes.unspecified", tone: .plain, text: "Prefer not to say"),
    .init(
      path: "tracker.targets.sexHint", tone: .plain,
      text: "Used only for the resting energy formula."),
    .init(path: "tracker.targets.birthDate", tone: .plain, text: "Birth date"),
    .init(path: "tracker.targets.height", tone: .plain, text: "Height"),
    .init(path: "tracker.targets.heightUnits.cm", tone: .plain, text: "cm"),
    .init(path: "tracker.targets.heightUnits.ftin", tone: .plain, text: "ft/in"),
    .init(path: "tracker.targets.feet", tone: .plain, text: "ft"),
    .init(path: "tracker.targets.inches", tone: .plain, text: "in"),
    .init(path: "tracker.targets.weight", tone: .plain, text: "Current weight"),
    .init(path: "tracker.targets.weightUnits.kg", tone: .plain, text: "kg"),
    .init(path: "tracker.targets.weightUnits.lb", tone: .plain, text: "lb"),
    .init(path: "tracker.targets.activity", tone: .plain, text: "How active are you?"),
    .init(path: "tracker.targets.activityLevels.sedentary.label", tone: .plain, text: "Sedentary"),
    .init(
      path: "tracker.targets.activityLevels.sedentary.hint", tone: .plain,
      text: "Desk job, little exercise."),
    .init(path: "tracker.targets.activityLevels.light.label", tone: .plain, text: "Lightly active"),
    .init(
      path: "tracker.targets.activityLevels.light.hint", tone: .plain,
      text: "Exercise 1 to 3 days a week."),
    .init(
      path: "tracker.targets.activityLevels.moderate.label", tone: .plain, text: "Moderately active"
    ),
    .init(
      path: "tracker.targets.activityLevels.moderate.hint", tone: .plain,
      text: "Exercise 3 to 5 days a week."),
    .init(path: "tracker.targets.activityLevels.active.label", tone: .plain, text: "Very active"),
    .init(
      path: "tracker.targets.activityLevels.active.hint", tone: .plain,
      text: "Hard exercise 6 to 7 days a week."),
    .init(
      path: "tracker.targets.activityLevels.veryActive.label", tone: .plain,
      text: "Extremely active"),
    .init(
      path: "tracker.targets.activityLevels.veryActive.hint", tone: .plain,
      text: "Physical job plus hard training."),
    .init(path: "tracker.targets.goal", tone: .plain, text: "What's your goal?"),
    .init(path: "tracker.targets.goals.lose", tone: .plain, text: "Lose weight"),
    .init(path: "tracker.targets.goals.maintain", tone: .plain, text: "Maintain"),
    .init(path: "tracker.targets.goals.gain", tone: .plain, text: "Gain weight"),
    .init(path: "tracker.targets.rate", tone: .plain, text: "How fast?"),
    .init(path: "tracker.targets.continue", tone: .plain, text: "Continue"),
    .init(path: "tracker.targets.back", tone: .plain, text: "Back"),
    .init(path: "tracker.targets.edit", tone: .plain, text: "Edit"),
    .init(path: "tracker.targets.macroLabels.calories", tone: .plain, text: "Calories"),
    .init(path: "tracker.targets.macroLabels.protein", tone: .plain, text: "Protein"),
    .init(path: "tracker.targets.macroLabels.carbs", tone: .plain, text: "Carbs"),
    .init(path: "tracker.targets.macroLabels.fat", tone: .plain, text: "Fat"),
    .init(path: "tracker.targets.unitKcal", tone: .plain, text: "kcal"),
    .init(path: "tracker.targets.unitGrams", tone: .plain, text: "g"),
    .init(path: "tracker.targets.calculated", tone: .plain, text: "calculated"),
    .init(path: "tracker.targets.setByYou", tone: .plain, text: "set by you"),
    .init(path: "tracker.targets.reset", tone: .plain, text: "Reset"),
    .init(path: "tracker.targets.adjust", tone: .plain, text: "Adjust"),
    .init(
      path: "tracker.targets.proteinPerKg", tone: .plain, text: "Protein per kg of bodyweight (g)"),
    .init(path: "tracker.targets.fatShare", tone: .plain, text: "Fat share of calories (%)"),
    .init(path: "tracker.targets.save", tone: .voice, text: "Set my targets"),
    .init(path: "tracker.targets.saving", tone: .voice, text: "Setting…"),
    .init(path: "tracker.targets.saved", tone: .voice, text: "Targets set"),
    .init(
      path: "tracker.targets.settled", tone: .plain,
      text: "These are your daily targets. Change any of them, or run the calculator again."),
    .init(
      path: "tracker.targets.couldntSave", tone: .plain,
      text: "Couldn't save your targets. Check your connection and try again."),
    .init(
      path: "tracker.targets.couldntLoad", tone: .plain,
      text: "Couldn't load your details. Try again."),
    .init(path: "tracker.targets.fixThese", tone: .plain, text: "Check the highlighted fields."),
    .init(path: "tracker.checkIn.pageTitle", tone: .plain, text: "Check-in"),
    .init(path: "tracker.checkIn.title", tone: .voice, text: "This week's check-in"),
    .init(
      path: "tracker.checkIn.banner", tone: .plain,
      text: "A week of food and weigh-ins is in. Time to see how your targets are doing."),
    .init(path: "tracker.checkIn.bannerAction", tone: .voice, text: "Divine this week's check-in"),
    .init(path: "tracker.checkIn.expenditure", tone: .plain, text: "Estimated daily burn"),
    .init(path: "tracker.checkIn.perDay", tone: .plain, text: "kcal a day"),
    .init(
      path: "tracker.checkIn.thin", tone: .plain,
      text: "There isn't enough yet to measure, so this leans on the calculator."),
    .init(
      path: "tracker.checkIn.leans", tone: .plain,
      text: "There's still little to go on, so this leans on the calculator."),
    .init(path: "tracker.checkIn.progress", tone: .plain, text: "Progress"),
    .init(path: "tracker.checkIn.expected", tone: .plain, text: "Goal"),
    .init(path: "tracker.checkIn.actual", tone: .plain, text: "Trend"),
    .init(path: "tracker.checkIn.noTrend", tone: .plain, text: "Not enough weigh-ins yet"),
    .init(path: "tracker.checkIn.targets", tone: .plain, text: "Targets"),
    .init(path: "tracker.checkIn.now", tone: .plain, text: "Now"),
    .init(path: "tracker.checkIn.proposed", tone: .plain, text: "Proposed"),
    .init(path: "tracker.checkIn.keepHandSet", tone: .plain, text: "Keep my hand-set targets"),
    .init(
      path: "tracker.checkIn.keepHandSetHint", tone: .plain,
      text: "Targets you typed in yourself stay as they are."),
    .init(
      path: "tracker.checkIn.floored", tone: .plain,
      text: "Held at the calorie floor so the target isn't too low."),
    .init(
      path: "tracker.checkIn.unchanged", tone: .plain,
      text: "The proposed targets match your current ones."),
    .init(path: "tracker.checkIn.accept", tone: .voice, text: "Accept these targets"),
    .init(path: "tracker.checkIn.accepting", tone: .voice, text: "Setting…"),
    .init(path: "tracker.checkIn.notNow", tone: .plain, text: "Not now"),
    .init(path: "tracker.checkIn.accepted", tone: .voice, text: "Targets set"),
    .init(path: "tracker.checkIn.deferred", tone: .plain, text: "Okay, we'll ask again next week."),
    .init(
      path: "tracker.checkIn.couldntSave", tone: .plain,
      text: "Couldn't save that. Check your connection and try again."),
    .init(
      path: "tracker.checkIn.couldntLoad", tone: .plain,
      text: "Couldn't load your check-in. Try again."),
    .init(path: "tracker.checkIn.retry", tone: .plain, text: "Try again"),
    .init(
      path: "tracker.checkIn.needTargets", tone: .plain,
      text: "Set your daily targets first, then check in once a week."),
    .init(path: "tracker.diary.previousDay", tone: .plain, text: "Previous day"),
    .init(path: "tracker.diary.nextDay", tone: .plain, text: "Next day"),
    .init(path: "tracker.diary.today", tone: .plain, text: "Today"),
    .init(path: "tracker.diary.yesterday", tone: .plain, text: "Yesterday"),
    .init(path: "tracker.diary.tomorrow", tone: .plain, text: "Tomorrow"),
    .init(path: "tracker.diary.pickDay", tone: .plain, text: "Pick a day"),
    .init(path: "tracker.diary.couldntLoad", tone: .plain, text: "Couldn't load the day."),
    .init(
      path: "tracker.diary.couldntSave", tone: .plain,
      text: "Couldn't save that change. Check your connection and try again."),
    .init(path: "tracker.diary.retry", tone: .plain, text: "Try again"),
    .init(
      path: "tracker.diary.empty", tone: .voice,
      text: "Nothing logged yet. Add what you've eaten as the day goes."),
    .init(path: "tracker.diary.add", tone: .plain, text: "Add"),
    .init(path: "tracker.diary.undo", tone: .plain, text: "Undo"),
    .init(path: "tracker.diary.estimate", tone: .plain, text: "estimate"),
    .init(path: "tracker.diary.gaps", tone: .plain, text: "Some numbers missing"),
    .init(path: "tracker.header.label", tone: .plain, text: "Eaten against target"),
    .init(path: "tracker.header.eaten", tone: .plain, text: "eaten"),
    .init(path: "tracker.header.of", tone: .plain, text: "of"),
    .init(
      path: "tracker.header.noTargets", tone: .plain,
      text: "Set daily targets to see how the day measures up."),
    .init(path: "tracker.header.setTargets", tone: .voice, text: "Divine your targets"),
    .init(path: "tracker.header.targets", tone: .plain, text: "Targets"),
    .init(path: "tracker.macros.calories", tone: .plain, text: "kcal"),
    .init(path: "tracker.macros.protein", tone: .plain, text: "protein"),
    .init(path: "tracker.macros.carbs", tone: .plain, text: "carbs"),
    .init(path: "tracker.macros.fat", tone: .plain, text: "fat"),
    .init(path: "tracker.macros.grams", tone: .plain, text: "g"),
    .init(path: "tracker.macroNames.calories", tone: .plain, text: "Calories"),
    .init(path: "tracker.macroNames.protein", tone: .plain, text: "Protein"),
    .init(path: "tracker.macroNames.carbs", tone: .plain, text: "Carbs"),
    .init(path: "tracker.macroNames.fat", tone: .plain, text: "Fat"),
    .init(path: "tracker.describe.heading", tone: .plain, text: "Describe it"),
    .init(
      path: "tracker.describe.hint", tone: .plain,
      text: "Say what you ate, with amounts if you know them."),
    .init(path: "tracker.describe.label", tone: .plain, text: "What you ate"),
    .init(
      path: "tracker.describe.placeholder", tone: .plain,
      text: "2 eggs, a slice of sourdough with butter, black coffee"),
    .init(path: "tracker.describe.divine", tone: .voice, text: "Divine it"),
    .init(path: "tracker.describe.divining", tone: .voice, text: "Divining…"),
    .init(
      path: "tracker.describe.review", tone: .plain,
      text: "Check these before logging. The numbers are estimates."),
    .init(path: "tracker.describe.notFood", tone: .plain, text: "Not something we could estimate"),
    .init(path: "tracker.describe.total", tone: .plain, text: "Total"),
    .init(path: "tracker.describe.startOver", tone: .plain, text: "Start over"),
    .init(
      path: "tracker.describe.unavailable", tone: .plain,
      text: "Describing needs an AI model, and none is set up. Use quick add instead."),
    .init(
      path: "tracker.describe.failed", tone: .plain,
      text: "Couldn't estimate that just now. Try again, or use quick add."),
    .init(
      path: "tracker.describe.unreadable", tone: .plain,
      text: "Couldn't find any food in that. Try naming what you ate."),
    .init(path: "tracker.describe.nothingLeft", tone: .plain, text: "Nothing left to log."),
    .init(path: "tracker.logRecipe.title", tone: .plain, text: "Log it"),
    .init(path: "tracker.logRecipe.search", tone: .plain, text: "Search your recipes"),
    .init(path: "tracker.logRecipe.noNumbers", tone: .plain, text: "No calories yet"),
    .init(path: "tracker.logRecipe.aServing", tone: .plain, text: "a serving"),
    .init(path: "tracker.logRecipe.change", tone: .plain, text: "Change recipe"),
    .init(
      path: "tracker.logRecipe.gaps", tone: .plain,
      text:
        "This recipe is missing some numbers. Divine them from the ingredients, or log what's known."
    ),
    .init(path: "tracker.quick.favourites", tone: .plain, text: "Favourites"),
    .init(path: "tracker.quick.recents", tone: .plain, text: "Recent"),
    .init(
      path: "tracker.quick.empty", tone: .voice,
      text: "Nothing logged lately. Describe a meal and it'll be here next time."),
    .init(path: "tracker.quick.favourite", tone: .plain, text: "Favourite"),
    .init(path: "tracker.quick.unfavourite", tone: .plain, text: "Unfavourite"),
    .init(
      path: "tracker.quick.couldntLoad", tone: .plain, text: "Couldn't load your recent foods."),
    .init(path: "tracker.copyDay.open", tone: .plain, text: "Copy a day"),
    .init(path: "tracker.copyDay.copyYesterday", tone: .plain, text: "Copy yesterday"),
    .init(path: "tracker.copyDay.from", tone: .plain, text: "From"),
    .init(path: "tracker.copyDay.meal", tone: .plain, text: "Meal"),
    .init(path: "tracker.copyDay.wholeDay", tone: .plain, text: "The whole day"),
    .init(path: "tracker.copyDay.copy", tone: .plain, text: "Copy"),
    .init(path: "tracker.copyDay.nothing", tone: .plain, text: "Nothing logged there to copy."),
    .init(
      path: "tracker.copyDay.sameDay", tone: .plain, text: "Pick a different day to copy from."),
    .init(path: "tracker.addTabs.label", tone: .plain, text: "How to add"),
    .init(path: "tracker.addTabs.recents", tone: .plain, text: "Recent"),
    .init(path: "tracker.addTabs.describe", tone: .plain, text: "Describe"),
    .init(path: "tracker.addTabs.recipe", tone: .plain, text: "Recipe"),
    .init(path: "tracker.addTabs.quick", tone: .plain, text: "Quick add"),
    .init(path: "tracker.weight.pageTitle", tone: .plain, text: "Weight"),
    .init(path: "tracker.weight.link", tone: .plain, text: "Weight"),
    .init(path: "tracker.weight.logWeight", tone: .plain, text: "Log weight"),
    .init(path: "tracker.weight.logTitle", tone: .plain, text: "Weigh-in"),
    .init(path: "tracker.weight.seeTrend", tone: .plain, text: "See the trend"),
    .init(path: "tracker.weight.day", tone: .plain, text: "Day"),
    .init(path: "tracker.weight.save", tone: .plain, text: "Save"),
    .init(path: "tracker.weight.saving", tone: .plain, text: "Saving…"),
    .init(path: "tracker.weight.remove", tone: .plain, text: "Remove"),
    .init(path: "tracker.weight.cancel", tone: .plain, text: "Cancel"),
    .init(
      path: "tracker.weight.needDay", tone: .plain, text: "Pick a day that isn't in the future."),
    .init(
      path: "tracker.weight.couldntSave", tone: .plain,
      text: "Couldn't save that weight. Check your connection and try again."),
    .init(
      path: "tracker.weight.couldntRemove", tone: .plain,
      text: "Couldn't remove that weigh-in. Check your connection and try again."),
    .init(path: "tracker.weight.couldntLoad", tone: .plain, text: "Couldn't load your weight."),
    .init(path: "tracker.weight.retry", tone: .plain, text: "Try again"),
    .init(path: "tracker.weight.ranges.oneMonth", tone: .plain, text: "1M"),
    .init(path: "tracker.weight.ranges.threeMonths", tone: .plain, text: "3M"),
    .init(path: "tracker.weight.ranges.oneYear", tone: .plain, text: "1Y"),
    .init(path: "tracker.weight.ranges.all", tone: .plain, text: "All"),
    .init(path: "tracker.weight.rangeLabel", tone: .plain, text: "Time range"),
    .init(path: "tracker.weight.chartLabel", tone: .plain, text: "Weight over time"),
    .init(path: "tracker.weight.legendScale", tone: .plain, text: "Weigh-in"),
    .init(path: "tracker.weight.legendTrend", tone: .plain, text: "Trend"),
    .init(path: "tracker.weight.trendNow", tone: .plain, text: "Trend weight"),
    .init(path: "tracker.weight.lastWeek", tone: .plain, text: "Last 7 days"),
    .init(path: "tracker.weight.lastMonth", tone: .plain, text: "Last 30 days"),
    .init(path: "tracker.weight.notEnough", tone: .plain, text: "Not enough yet"),
    .init(path: "tracker.weight.intakeTitle", tone: .plain, text: "Average intake"),
    .init(path: "tracker.weight.intakeNone", tone: .plain, text: "No food logged in this range."),
    .init(path: "tracker.weight.listTitle", tone: .plain, text: "Weigh-ins"),
    .init(path: "tracker.weight.add", tone: .plain, text: "Log a past day"),
    .init(
      path: "tracker.weight.empty", tone: .voice,
      text: "No weigh-ins yet. Log one and the trend starts to show."),
    .init(path: "tracker.entry.quickAdd", tone: .plain, text: "Quick add"),
    .init(
      path: "tracker.entry.quickAddHint", tone: .plain, text: "Type in a name and its numbers."),
    .init(path: "tracker.entry.name", tone: .plain, text: "Name"),
    .init(path: "tracker.entry.namePlaceholder", tone: .plain, text: "Flat white, apple…"),
    .init(path: "tracker.entry.amount", tone: .plain, text: "Amount"),
    .init(path: "tracker.entry.amountPlaceholder", tone: .plain, text: "1 cup, 2 slices…"),
    .init(path: "tracker.entry.servings", tone: .plain, text: "Servings"),
    .init(path: "tracker.entry.fewer", tone: .plain, text: "Fewer servings"),
    .init(path: "tracker.entry.more", tone: .plain, text: "More servings"),
    .init(path: "tracker.entry.perServing", tone: .plain, text: "Per serving"),
    .init(path: "tracker.entry.meal", tone: .plain, text: "Meal"),
    .init(path: "tracker.entry.day", tone: .plain, text: "Day"),
    .init(path: "tracker.entry.log", tone: .plain, text: "Log it"),
    .init(path: "tracker.entry.save", tone: .plain, text: "Save"),
    .init(path: "tracker.entry.remove", tone: .plain, text: "Remove"),
    .init(path: "tracker.entry.cancel", tone: .plain, text: "Cancel"),
    .init(path: "tracker.entry.fromRecipe", tone: .plain, text: "From a recipe"),
    .init(path: "tracker.entry.described", tone: .plain, text: "Described"),
    .init(path: "tracker.entry.byHand", tone: .plain, text: "Typed in"),
    .init(path: "tracker.entry.total", tone: .plain, text: "Total"),
    .init(path: "ui.appName", tone: .plain, text: "Cauldron"),
    .init(path: "ui.byline", tone: .plain, text: "by srcery"),
    .init(path: "ui.footer", tone: .voice, text: "Cauldron, stirred at srcery.computer"),
    .init(path: "ui.wordmark", tone: .plain, text: "cauldron"),
    .init(
      path: "ui.tagline", tone: .voice,
      text:
        "A recipe box and weekly meal planner. Conjure recipes, distill them from a link, and stir them into the week."
    ),
    .init(path: "ui.menu", tone: .plain, text: "Menu"),
    .init(path: "ui.close", tone: .plain, text: "Close"),
    .init(path: "ui.loading", tone: .plain, text: "Loading"),
    .init(path: "ui.tryAgain", tone: .plain, text: "Try again"),
    .init(path: "ui.skipToContent", tone: .plain, text: "Skip to content"),
    .init(path: "ui.mainNav", tone: .plain, text: "Main"),
    .init(path: "ui.goHome", tone: .plain, text: "Back to Cauldron"),
    .init(path: "ui.switchToLight", tone: .plain, text: "Switch to light theme"),
    .init(path: "ui.switchToDark", tone: .plain, text: "Switch to dark theme"),
    .init(path: "validation.required", tone: .plain, text: "Fill this in."),
    .init(path: "validation.link", tone: .plain, text: "Enter a link starting with https://"),
    .init(path: "validation.date", tone: .plain, text: "Use a real date, like 2026-10-01."),
    .init(
      path: "validation.quantity", tone: .plain, text: "Use an amount from 0 up to 99,999,999."),
    .init(
      path: "validation.range", tone: .plain,
      text: "The second amount in a range can't be smaller than the first."),
    .init(path: "week.title", tone: .plain, text: "The week"),
    .init(
      path: "week.empty", tone: .voice,
      text: "The cauldron's cold. Stir in a recipe to start the week."),
    .init(path: "week.slots.breakfast", tone: .plain, text: "Breakfast"),
    .init(path: "week.slots.lunch", tone: .plain, text: "Lunch"),
    .init(path: "week.slots.dinner", tone: .plain, text: "Dinner"),
    .init(path: "week.slots.snack", tone: .plain, text: "Snack"),
    .init(path: "week.previousWeek", tone: .plain, text: "Previous week"),
    .init(path: "week.nextWeek", tone: .plain, text: "Next week"),
    .init(path: "week.thisWeek", tone: .plain, text: "This week"),
    .init(path: "week.today", tone: .plain, text: "today"),
    .init(path: "week.days", tone: .plain, text: "Days"),
    .init(path: "week.copyLastWeek", tone: .plain, text: "Copy last week"),
    .init(path: "week.copiedLastWeek", tone: .plain, text: "Copied last week's meals."),
    .init(path: "week.nothingToCopy", tone: .plain, text: "Last week has nothing planned."),
    .init(path: "week.clearWeek", tone: .plain, text: "Clear week"),
    .init(path: "week.cleared", tone: .plain, text: "Cleared the week."),
    .init(path: "week.cancel", tone: .plain, text: "Cancel"),
    .init(path: "week.stirIn", tone: .voice, text: "Stir in"),
    .init(path: "week.stirIntoWeek", tone: .voice, text: "Stir into the week"),
    .init(path: "week.searchRecipes", tone: .plain, text: "Search your recipes"),
    .init(path: "week.noMatches", tone: .plain, text: "No recipes match that."),
    .init(path: "week.orWrite", tone: .plain, text: "Or write a meal"),
    .init(path: "week.writePlaceholder", tone: .plain, text: "Leftovers, eating out…"),
    .init(path: "week.add", tone: .plain, text: "Add"),
    .init(path: "week.day", tone: .plain, text: "Day"),
    .init(path: "week.slot", tone: .plain, text: "Meal"),
    .init(path: "week.servings", tone: .plain, text: "Servings"),
    .init(path: "week.open", tone: .plain, text: "Open recipe"),
    .init(path: "week.remove", tone: .plain, text: "Remove"),
    .init(path: "week.undo", tone: .plain, text: "Undo"),
    .init(path: "week.save", tone: .plain, text: "Save"),
    .init(path: "week.brewed", tone: .voice, text: "✓ brewed"),
    .init(path: "week.leftovers", tone: .plain, text: "not a recipe"),
    .init(path: "week.recipesPanel", tone: .plain, text: "Recipes"),
    .init(
      path: "week.dragHint", tone: .plain,
      text: "Drag a recipe onto a meal, or press + on a meal to stir one in."),
    .init(path: "week.moveHint", tone: .plain, text: "Drag a meal to move it to another day."),
    .init(path: "week.weekStarts", tone: .plain, text: "Week starts on"),
    .init(path: "week.monday", tone: .plain, text: "Monday"),
    .init(path: "week.sunday", tone: .plain, text: "Sunday"),
    .init(
      path: "week.couldntSave", tone: .plain,
      text: "Couldn't save that change. Check your connection and try again."),
    .init(path: "week.couldntLoad", tone: .plain, text: "Couldn't load the week."),
    .init(path: "week.retry", tone: .plain, text: "Try again"),
    .init(path: "week.slotFull", tone: .plain, text: "That meal is full. Remove something first."),
    .init(path: "week.moveUp", tone: .plain, text: "Move up"),
    .init(path: "week.moveDown", tone: .plain, text: "Move down"),
    .init(path: "week.meal", tone: .plain, text: "Meal"),
    .init(path: "week.tally.label", tone: .plain, text: "Calories and macros"),
    .init(path: "week.tally.week", tone: .plain, text: "Week"),
    .init(path: "week.tally.perDay", tone: .plain, text: "a day"),
    .init(path: "week.tally.macros.calories", tone: .plain, text: "kcal"),
    .init(path: "week.tally.macros.protein", tone: .plain, text: "protein"),
    .init(path: "week.tally.macros.carbs", tone: .plain, text: "carbs"),
    .init(path: "week.tally.macros.fat", tone: .plain, text: "fat"),
    .init(
      path: "week.tally.none", tone: .plain,
      text: "Add calories and macros to your recipes to see totals here."),
    .init(path: "week.tally.clearDay", tone: .plain, text: "Back to the week"),
    .init(
      path: "week.tally.plannedAgainstTarget", tone: .plain, text: "Planned against weekly target"),
    .init(path: "week.tally.grams", tone: .plain, text: "g"),
    .init(path: "week.tally.lessThanTenth", tone: .plain, text: "<0.1"),
    .init(
      path: "week.tally.incomplete", tone: .plain,
      text: "Incomplete comparison: some planned meals are not fully counted."),
    .init(
      path: "week.tally.noTargets", tone: .plain,
      text: "Set targets to compare this plan with your weekly goals."),
    .init(path: "week.tally.setTargets", tone: .plain, text: "Set targets"),
    .init(path: "week.spread.days", tone: .plain, text: "Days"),
    .init(
      path: "week.spread.hint", tone: .plain,
      text: "Pick the days this batch feeds. Each day gets one serving unless you change it."),
    .init(path: "week.spread.oneADay", tone: .plain, text: "One a day"),
    .init(path: "week.spread.pickADay", tone: .plain, text: "Pick at least one day."),
  ]

  /// Every string that takes arguments, called with samples that reach each branch.
  static let calls: [CopyReferenceCall] = [
    .init(
      call: "Copy.brewing.stepOf(2, 5)", actual: Copy.brewing.stepOf(2, 5), tone: .plain,
      text: "2 of 5"),
    .init(
      call: "Copy.brewing.timerFor(3)", actual: Copy.brewing.timerFor(3), tone: .plain,
      text: "Step 3"),
    .init(
      call: "Copy.brewing.timerDone(\"Dal\", 3)", actual: Copy.brewing.timerDone("Dal", 3),
      tone: .plain, text: "Dal: the step 3 timer is done."),
    .init(
      call: "Copy.editor.removeTag(\"vegan\")", actual: Copy.editor.removeTag("vegan"),
      tone: .plain, text: "Remove tag vegan"),
    .init(
      call: "Copy.editor.ingredientLine(3)", actual: Copy.editor.ingredientLine(3), tone: .plain,
      text: "Ingredient 3"),
    .init(
      call: "Copy.editor.heading(2)", actual: Copy.editor.heading(2), tone: .plain,
      text: "Section heading 2"),
    .init(call: "Copy.editor.step(4)", actual: Copy.editor.step(4), tone: .plain, text: "Step 4"),
    .init(
      call: "Copy.editor.moved(2, 5)", actual: Copy.editor.moved(2, 5), tone: .plain,
      text: "Moved to position 2 of 5."),
    .init(
      call: "Copy.editor.fixLine(\"1 cup milk\")", actual: Copy.editor.fixLine("1 cup milk"),
      tone: .plain, text: "Fix how \"1 cup milk\" was read"),
    .init(
      call: "Copy.gather.checked(2, 5)", actual: Copy.gather.checked(2, 5), tone: .plain,
      text: "2 of 5 gathered"),
    .init(
      call: "Copy.gather.forRecipes(\"Dal and Soup\")",
      actual: Copy.gather.forRecipes("Dal and Soup"), tone: .plain, text: "For Dal and Soup"),
    .init(
      call: "Copy.gather.markInPantry(\"salt\")", actual: Copy.gather.markInPantry("salt"),
      tone: .plain, text: "salt is in the pantry"),
    .init(
      call: "Copy.gather.remove(\"salt\")", actual: Copy.gather.remove("salt"), tone: .plain,
      text: "Remove salt"),
    .init(
      call: "Copy.gather.summary(1, 1)", actual: Copy.gather.summary(1, 1), tone: .plain,
      text: "1 ingredient across 1 recipe."),
    .init(
      call: "Copy.gather.summary(5, 1)", actual: Copy.gather.summary(5, 1), tone: .plain,
      text: "5 ingredients across 1 recipe."),
    .init(
      call: "Copy.gather.summary(1, 3)", actual: Copy.gather.summary(1, 3), tone: .plain,
      text: "1 ingredient across 3 recipes."),
    .init(
      call: "Copy.gather.summary(0, 0)", actual: Copy.gather.summary(0, 0), tone: .plain,
      text: "0 ingredients across 0 recipes."),
    .init(
      call: "Copy.gather.inPantryCount(1)", actual: Copy.gather.inPantryCount(1), tone: .plain,
      text: "1 is already in the pantry."),
    .init(
      call: "Copy.gather.inPantryCount(4)", actual: Copy.gather.inPantryCount(4), tone: .plain,
      text: "4 are already in the pantry."),
    .init(
      call: "Copy.imports.duplicate(\"Dal\")", actual: Copy.imports.duplicate("Dal"), tone: .plain,
      text: "You already have a recipe from this link: Dal."),
    .init(
      call: "Copy.library.tagOption(\"Indian\", 3)", actual: Copy.library.tagOption("Indian", 3),
      tone: .plain, text: "Indian (3)"),
    .init(
      call: "Copy.library.count(0)", actual: Copy.library.count(0), tone: .plain, text: "0 recipes"),
    .init(
      call: "Copy.library.count(1)", actual: Copy.library.count(1), tone: .plain, text: "1 recipe"),
    .init(
      call: "Copy.library.count(12)", actual: Copy.library.count(12), tone: .plain,
      text: "12 recipes"),
    .init(
      call: "Copy.library.macroLine.calories(\"520\")",
      actual: Copy.library.macroLine.calories("520"), tone: .plain, text: "520 kcal"),
    .init(
      call: "Copy.library.macroLine.protein(\"31\")", actual: Copy.library.macroLine.protein("31"),
      tone: .plain, text: "31P"),
    .init(
      call: "Copy.library.macroLine.fat(\"12\")", actual: Copy.library.macroLine.fat("12"),
      tone: .plain, text: "12F"),
    .init(
      call: "Copy.library.macroLine.carbs(\"60\")", actual: Copy.library.macroLine.carbs("60"),
      tone: .plain, text: "60C"),
    .init(
      call: "Copy.library.macroLine.spoken.calories(\"520\")",
      actual: Copy.library.macroLine.spoken.calories("520"), tone: .plain, text: "520 kcal"),
    .init(
      call: "Copy.library.macroLine.spoken.protein(\"31\")",
      actual: Copy.library.macroLine.spoken.protein("31"), tone: .plain, text: "31 g protein"),
    .init(
      call: "Copy.library.macroLine.spoken.fat(\"12\")",
      actual: Copy.library.macroLine.spoken.fat("12"), tone: .plain, text: "12 g fat"),
    .init(
      call: "Copy.library.macroLine.spoken.carbs(\"60\")",
      actual: Copy.library.macroLine.spoken.carbs("60"), tone: .plain, text: "60 g carbs"),
    .init(
      call: "Copy.library.macroLine.spoken.label(\"520 kcal, 31 g protein\")",
      actual: Copy.library.macroLine.spoken.label("520 kcal, 31 g protein"), tone: .plain,
      text: "Per serving: 520 kcal, 31 g protein"),
    .init(
      call: "Copy.photos.alt(\"Dal\")", actual: Copy.photos.alt("Dal"), tone: .plain,
      text: "Photo of Dal"),
    .init(
      call: "Copy.recipeView.checked(2, 7)", actual: Copy.recipeView.checked(2, 7), tone: .plain,
      text: "2 of 7"),
    .init(
      call: "Copy.recipeView.serves(4)", actual: Copy.recipeView.serves(4), tone: .plain,
      text: "serves 4"),
    .init(
      call: "Copy.recipeView.scale(\"1.5\")", actual: Copy.recipeView.scale("1.5"), tone: .plain,
      text: "×1.5"),
    .init(
      call: "Copy.recipeView.from(\"Example Kitchen\")",
      actual: Copy.recipeView.from("Example Kitchen"), tone: .plain, text: "From Example Kitchen"),
    .init(
      call: "Copy.recipeView.by(\"Sam\")", actual: Copy.recipeView.by("Sam"), tone: .plain,
      text: "by Sam"),
    .init(
      call: "Copy.recipeView.lastCooked(\"2026-10-01\")",
      actual: Copy.recipeView.lastCooked("2026-10-01"), tone: .plain, text: "Last cooked 2026-10-01"
    ),
    .init(
      call: "Copy.recipeView.banished(\"Dal\")", actual: Copy.recipeView.banished("Dal"),
      tone: .plain, text: "Banished Dal."),
    .init(
      call: "Copy.recipes.stirInto(\"Monday\")", actual: Copy.recipes.stirInto("Monday"),
      tone: .voice, text: "Stir into Monday"),
    .init(
      call: "Copy.recipes.banishConfirm(\"Dal\").verb",
      actual: Copy.recipes.banishConfirm("Dal").verb, tone: .voice, text: "Banish"),
    .init(
      call: "Copy.recipes.banishConfirm(\"Dal\").confirm",
      actual: Copy.recipes.banishConfirm("Dal").confirm, tone: .plain,
      text: "Banish Dal? You can undo it straight after."),
    .init(
      call: "Copy.recipes.copyOf(\"Dal\")", actual: Copy.recipes.copyOf("Dal"), tone: .plain,
      text: "Dal (copy)"),
    .init(
      call: "Copy.tracker.targets.step(2, 3)", actual: Copy.tracker.targets.step(2, 3),
      tone: .plain, text: "Step 2 of 3"),
    .init(
      call: "Copy.tracker.targets.unitSwitch(\"Weight\")",
      actual: Copy.tracker.targets.unitSwitch("Weight"), tone: .plain, text: "Weight unit"),
    .init(
      call: "Copy.tracker.targets.perWeek(\"0.5\", \"kg\")",
      actual: Copy.tracker.targets.perWeek("0.5", "kg"), tone: .plain, text: "0.5 kg a week"),
    .init(
      call: "Copy.tracker.targets.summaryAge(34)", actual: Copy.tracker.targets.summaryAge(34),
      tone: .plain, text: "34 years"),
    .init(
      call: "Copy.tracker.targets.headline(.lose, \"2000\", \"0.5\", \"kg\")",
      actual: Copy.tracker.targets.headline(.lose, "2000", "0.5", "kg"), tone: .plain,
      text: "About 2000 kcal a day to lose 0.5 kg a week."),
    .init(
      call: "Copy.tracker.targets.headline(.maintain, \"2200\", \"0\", \"kg\")",
      actual: Copy.tracker.targets.headline(.maintain, "2200", "0", "kg"), tone: .plain,
      text: "About 2200 kcal a day to stay where you are."),
    .init(
      call: "Copy.tracker.targets.headline(.gain, \"2600\", \"0.25\", \"lb\")",
      actual: Copy.tracker.targets.headline(.gain, "2600", "0.25", "lb"), tone: .plain,
      text: "About 2600 kcal a day to gain 0.25 lb a week."),
    .init(
      call: "Copy.tracker.targets.breakdown(\"1700\", \"1.55\", \"2635\")",
      actual: Copy.tracker.targets.breakdown("1700", "1.55", "2635"), tone: .plain,
      text: "Resting energy 1700 kcal x 1.55 for activity = 2635 kcal burned a day."),
    .init(
      call: "Copy.tracker.targets.adjustLose(\"500\")",
      actual: Copy.tracker.targets.adjustLose("500"), tone: .plain,
      text: "Minus 500 kcal a day for your goal."),
    .init(
      call: "Copy.tracker.targets.adjustGain(\"300\")",
      actual: Copy.tracker.targets.adjustGain("300"), tone: .plain,
      text: "Plus 300 kcal a day for your goal."),
    .init(
      call: "Copy.tracker.targets.floor(\"1500\")", actual: Copy.tracker.targets.floor("1500"),
      tone: .plain, text: "That went below the safety floor, so it was raised to 1500 kcal."),
    .init(
      call: "Copy.tracker.targets.resetLabel(\"calories\")",
      actual: Copy.tracker.targets.resetLabel("calories"), tone: .plain,
      text: "Reset calories to the calculated value"),
    .init(
      call: "Copy.tracker.checkIn.basedOn(1, 1, 1)", actual: Copy.tracker.checkIn.basedOn(1, 1, 1),
      tone: .plain, text: "Based on 1 logged day and 1 weigh-in over the last 1 week."),
    .init(
      call: "Copy.tracker.checkIn.basedOn(5, 3, 2)", actual: Copy.tracker.checkIn.basedOn(5, 3, 2),
      tone: .plain, text: "Based on 5 logged days and 3 weigh-ins over the last 2 weeks."),
    .init(
      call: "Copy.tracker.checkIn.basedOn(0, 0, 0)", actual: Copy.tracker.checkIn.basedOn(0, 0, 0),
      tone: .plain, text: "Based on 0 logged days and 0 weigh-ins over the last 0 weeks."),
    .init(
      call: "Copy.tracker.checkIn.perWeek(\"0.5\", \"kg\")",
      actual: Copy.tracker.checkIn.perWeek("0.5", "kg"), tone: .plain, text: "0.5 kg a week"),
    .init(
      call: "Copy.tracker.diary.addTo(\"Dinner\")", actual: Copy.tracker.diary.addTo("Dinner"),
      tone: .plain, text: "Add to dinner"),
    .init(
      call: "Copy.tracker.diary.logged(\"Eggs\")", actual: Copy.tracker.diary.logged("Eggs"),
      tone: .plain, text: "Logged Eggs."),
    .init(
      call: "Copy.tracker.diary.loggedMany(1)", actual: Copy.tracker.diary.loggedMany(1),
      tone: .plain, text: "Logged 1 item."),
    .init(
      call: "Copy.tracker.diary.loggedMany(3)", actual: Copy.tracker.diary.loggedMany(3),
      tone: .plain, text: "Logged 3 items."),
    .init(
      call: "Copy.tracker.diary.removed(\"Eggs\")", actual: Copy.tracker.diary.removed("Eggs"),
      tone: .plain, text: "Removed Eggs."),
    .init(
      call: "Copy.tracker.diary.edit(\"Eggs\")", actual: Copy.tracker.diary.edit("Eggs"),
      tone: .plain, text: "Change Eggs"),
    .init(
      call: "Copy.tracker.header.left(\"300\")", actual: Copy.tracker.header.left("300"),
      tone: .plain, text: "300 left"),
    .init(
      call: "Copy.tracker.header.over(\"120\")", actual: Copy.tracker.header.over("120"),
      tone: .plain, text: "120 over"),
    .init(
      call: "Copy.tracker.describe.remove(\"Eggs\")", actual: Copy.tracker.describe.remove("Eggs"),
      tone: .plain, text: "Remove Eggs"),
    .init(
      call: "Copy.tracker.describe.log(1)", actual: Copy.tracker.describe.log(1), tone: .plain,
      text: "Log 1 item"),
    .init(
      call: "Copy.tracker.describe.log(3)", actual: Copy.tracker.describe.log(3), tone: .plain,
      text: "Log 3 items"),
    .init(
      call: "Copy.tracker.quick.logAgain(\"Eggs\")", actual: Copy.tracker.quick.logAgain("Eggs"),
      tone: .plain, text: "Log Eggs again"),
    .init(
      call: "Copy.tracker.quick.star(\"Eggs\")", actual: Copy.tracker.quick.star("Eggs"),
      tone: .plain, text: "Add Eggs to favourites"),
    .init(
      call: "Copy.tracker.quick.unstar(\"Eggs\")", actual: Copy.tracker.quick.unstar("Eggs"),
      tone: .plain, text: "Remove Eggs from favourites"),
    .init(
      call: "Copy.tracker.quick.starred(\"Eggs\")", actual: Copy.tracker.quick.starred("Eggs"),
      tone: .plain, text: "Eggs is a favourite."),
    .init(
      call: "Copy.tracker.quick.times(3)", actual: Copy.tracker.quick.times(3), tone: .plain,
      text: "3×"),
    .init(
      call: "Copy.tracker.copyDay.title(\"Monday\")", actual: Copy.tracker.copyDay.title("Monday"),
      tone: .plain, text: "Copy into Monday"),
    .init(
      call: "Copy.tracker.copyDay.copied(1)", actual: Copy.tracker.copyDay.copied(1), tone: .plain,
      text: "Copied 1 item."),
    .init(
      call: "Copy.tracker.copyDay.copied(4)", actual: Copy.tracker.copyDay.copied(4), tone: .plain,
      text: "Copied 4 items."),
    .init(
      call: "Copy.tracker.weight.logFor(\"Monday\")", actual: Copy.tracker.weight.logFor("Monday"),
      tone: .plain, text: "Weigh-in for Monday"),
    .init(
      call: "Copy.tracker.weight.change(\"72.5 kg\")",
      actual: Copy.tracker.weight.change("72.5 kg"), tone: .plain,
      text: "Change weight, now 72.5 kg"),
    .init(
      call: "Copy.tracker.weight.label(\"kg\")", actual: Copy.tracker.weight.label("kg"),
      tone: .plain, text: "Weight (kg)"),
    .init(
      call: "Copy.tracker.weight.outOfRange(\"20\", \"400\", \"kg\")",
      actual: Copy.tracker.weight.outOfRange("20", "400", "kg"), tone: .plain,
      text: "Enter a weight between 20 and 400 kg."),
    .init(
      call: "Copy.tracker.weight.chartSummary(12, \"Sep 1\", \"Oct 1\")",
      actual: Copy.tracker.weight.chartSummary(12, "Sep 1", "Oct 1"), tone: .plain,
      text: "12 weigh-ins from Sep 1 to Oct 1, with the trend line."),
    .init(
      call: "Copy.tracker.weight.intakeAcross(1)", actual: Copy.tracker.weight.intakeAcross(1),
      tone: .plain, text: "across 1 logged day"),
    .init(
      call: "Copy.tracker.weight.intakeAcross(5)", actual: Copy.tracker.weight.intakeAcross(5),
      tone: .plain, text: "across 5 logged days"),
    .init(
      call: "Copy.tracker.weight.edit(\"Monday\")", actual: Copy.tracker.weight.edit("Monday"),
      tone: .plain, text: "Change the weigh-in for Monday"),
    .init(
      call: "Copy.tracker.weight.removeFor(\"Monday\")",
      actual: Copy.tracker.weight.removeFor("Monday"), tone: .plain,
      text: "Remove the weigh-in for Monday"),
    .init(
      call: "Copy.tracker.weight.removed(\"Monday\")",
      actual: Copy.tracker.weight.removed("Monday"), tone: .plain,
      text: "Removed the weigh-in for Monday."),
    .init(
      call: "Copy.tracker.entry.addTitle(\"Snack\")", actual: Copy.tracker.entry.addTitle("Snack"),
      tone: .plain, text: "Add to snack"),
    .init(
      call: "Copy.validation.tooLong(200)", actual: Copy.validation.tooLong(200), tone: .plain,
      text: "Keep it to 200 characters or fewer."),
    .init(
      call: "Copy.validation.tooMany(30)", actual: Copy.validation.tooMany(30), tone: .plain,
      text: "Use 30 or fewer."),
    .init(
      call: "Copy.validation.wholeNumber(1, 1000)", actual: Copy.validation.wholeNumber(1, 1000),
      tone: .plain, text: "Use a whole number from 1 to 1000."),
    .init(
      call: "Copy.validation.numberBetween(0, 2000)",
      actual: Copy.validation.numberBetween(0, 2000), tone: .plain,
      text: "Use a number from 0 to 2000."),
    .init(
      call: "Copy.week.clearConfirm(\"Oct 5 to Oct 11\")",
      actual: Copy.week.clearConfirm("Oct 5 to Oct 11"), tone: .plain,
      text: "Clear every meal planned for Oct 5 to Oct 11? This can't be undone."),
    .init(
      call: "Copy.week.stirInto(\"Monday\", \"Dinner\")",
      actual: Copy.week.stirInto("Monday", "Dinner"), tone: .voice, text: "Stir into Monday, dinner"
    ),
    .init(
      call: "Copy.week.stirred(\"Monday\")", actual: Copy.week.stirred("Monday"), tone: .voice,
      text: "Stirred into Monday."),
    .init(
      call: "Copy.week.sameServings(nil)", actual: Copy.week.sameServings(nil), tone: .plain,
      text: "As the recipe"),
    .init(
      call: "Copy.week.sameServings(4)", actual: Copy.week.sameServings(4), tone: .plain,
      text: "As the recipe (4)"),
    .init(
      call: "Copy.week.edit(\"Dal\")", actual: Copy.week.edit("Dal"), tone: .plain,
      text: "Change Dal"),
    .init(
      call: "Copy.week.removed(\"Dal\")", actual: Copy.week.removed("Dal"), tone: .plain,
      text: "Removed Dal."),
    .init(
      call: "Copy.week.tally.gaps(1)", actual: Copy.week.tally.gaps(1), tone: .plain,
      text: "1 planned meal isn't fully counted."),
    .init(
      call: "Copy.week.tally.gaps(3)", actual: Copy.week.tally.gaps(3), tone: .plain,
      text: "3 planned meals aren't fully counted."),
    .init(
      call: "Copy.week.tally.comparisonRow(calories, below)",
      actual: Copy.week.tally.comparisonRow(
        name: Copy.tracker.macroNames.calories.text, planned: "8,000", target: "14,000",
        unit: Copy.week.tally.macros.calories.text, difference: "6,000", isOver: false),
      tone: .plain,
      text: "Calories: 8,000 kcal planned, 14,000 kcal target, 6,000 kcal remaining"),
    .init(
      call: "Copy.week.tally.comparisonRow(protein, exact)",
      actual: Copy.week.tally.comparisonRow(
        name: Copy.tracker.macroNames.protein.text, planned: "700", target: "700",
        unit: Copy.week.tally.grams.text, difference: "0", isOver: false),
      tone: .plain, text: "Protein: 700 g planned, 700 g target, 0 g remaining"),
    .init(
      call: "Copy.week.tally.comparisonRow(carbs, over)",
      actual: Copy.week.tally.comparisonRow(
        name: Copy.tracker.macroNames.carbs.text, planned: "1,500", target: "1,400",
        unit: Copy.week.tally.grams.text, difference: "100", isOver: true),
      tone: .plain, text: "Carbs: 1,500 g planned, 1,400 g target, 100 g over target"),
    .init(
      call: "Copy.week.tally.comparisonRow(fat, under)",
      actual: Copy.week.tally.comparisonRow(
        name: Copy.tracker.macroNames.fat.text, planned: "400", target: "490",
        unit: Copy.week.tally.grams.text, difference: "90", isOver: false),
      tone: .plain, text: "Fat: 400 g planned, 490 g target, 90 g remaining"),
    .init(
      call: "Copy.week.tally.showDay(\"Monday\")", actual: Copy.week.tally.showDay("Monday"),
      tone: .plain, text: "Show Monday"),
    .init(
      call: "Copy.week.spread.planned(3, nil)", actual: Copy.week.spread.planned(3, nil),
      tone: .plain, text: "3 servings planned"),
    .init(
      call: "Copy.week.spread.planned(1, nil)", actual: Copy.week.spread.planned(1, nil),
      tone: .plain, text: "1 serving planned"),
    .init(
      call: "Copy.week.spread.planned(3, 6)", actual: Copy.week.spread.planned(3, 6), tone: .plain,
      text: "3 of 6 servings planned"),
    .init(
      call: "Copy.week.spread.allOn(\"Monday\")", actual: Copy.week.spread.allOn("Monday"),
      tone: .plain, text: "All on Monday"),
    .init(
      call: "Copy.week.spread.fewer(\"Monday\")", actual: Copy.week.spread.fewer("Monday"),
      tone: .plain, text: "Fewer servings on Monday"),
    .init(
      call: "Copy.week.spread.more(\"Monday\")", actual: Copy.week.spread.more("Monday"),
      tone: .plain, text: "More servings on Monday"),
    .init(
      call: "Copy.week.spread.servingsOn(1)", actual: Copy.week.spread.servingsOn(1), tone: .plain,
      text: "1 serving"),
    .init(
      call: "Copy.week.spread.servingsOn(2)", actual: Copy.week.spread.servingsOn(2), tone: .plain,
      text: "2 servings"),
    .init(
      call: "Copy.week.spread.stir(1)", actual: Copy.week.spread.stir(1), tone: .voice,
      text: "Stir into 1 day"),
    .init(
      call: "Copy.week.spread.stir(3)", actual: Copy.week.spread.stir(3), tone: .voice,
      text: "Stir into 3 days"),
    .init(
      call: "Copy.week.spread.stirred(1)", actual: Copy.week.spread.stirred(1), tone: .voice,
      text: "Stirred into 1 day."),
    .init(
      call: "Copy.week.spread.stirred(3)", actual: Copy.week.spread.stirred(3), tone: .voice,
      text: "Stirred into 3 days."),
  ]
}
