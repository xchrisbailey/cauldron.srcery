extension Copy {
  /// What the native Distill screens say beyond the web ones (`imports`). These have no
  /// counterpart in the web copy, so the reference fixture leaves them out. All plain: they are
  /// explanations of where a draft came from.
  public struct ImportNative: Sendable {
    /// The share extension's confirmation heading: what was shared is in the app's inbox.
    public let sentToCauldron = plain("Sent to Cauldron")
    /// Under the heading. A share extension can't open the app, so it says when the draft comes.
    public let opensAsDraft = plain("It opens as a draft the next time you open Cauldron.")
    /// The share extension found neither a link nor any text in what was shared.
    public let nothingToSend = plain("There's no link or text here for Cauldron to read.")
    /// The share extension had something to send but couldn't leave it for the app.
    public let couldntSend = plain("Cauldron couldn't keep that. Try sharing it again.")
    /// The share sheet while it reads the shared page or caption.
    public let readingRecipe = plain("Reading the recipe…")
    /// The share sheet's button that keeps the recipe it found.
    public let saveToRecipes = plain("Save to recipes")
    /// The share sheet's way to finish the recipe in the app, as a draft.
    public let editInCauldron = plain("Edit in Cauldron")
    /// The same button when the recipe has ingredient lines to check: it nudges toward fixing.
    public let fixInCauldron = plain("Fix it in Cauldron")
    /// The labels under the share sheet's stats strip. The total time's is `recipeView.total`.
    public let ingredientsLabel = plain("ingredients")
    public let stepsLabel = plain("steps")
    public let servesLabel = plain("serves")
    /// The share sheet's folded sections.
    public let ingredientsSection = plain("Ingredients")
    public let stepsSection = plain("Steps")
    /// The share sheet when the page needs an AI to be read and there's no key (and no model on
    /// the device). The next step is the button under it.
    public let noAIKey = plain(
      "Cauldron needs an AI key to read this, and there isn't one yet. Add one in Cauldron's Settings, or send it to Cauldron to finish later."
    )
    /// When the share sheet couldn't read the recipe: leave the link for the app instead.
    public let sendInstead = plain("Send to Cauldron instead")
    /// The share sheet's confirmation after Save, and what it means.
    public let savedToRecipes = plain("Saved to your recipes")
    public let savedDetail = plain("It's in your recipe box the next time you open Cauldron.")
    /// The share sheet couldn't leave the finished recipe for the app.
    public let couldntSave = plain(
      "Cauldron couldn't keep that recipe. Send it to Cauldron instead.")
    /// On a draft the on-device model read because the AI couldn't be reached. The web app had
    /// no such state: it only ever had the one model.
    public let rough = plain(
      "The model on this device read this recipe because the AI couldn't be reached, so it may be rougher than usual. Check it carefully before you save."
    )

    // From a photo. The web app had no photo import. Native-only sections are all plain
    // (`CopyTests`); the sheet's one voice string, Distill, is the button that starts it.

    /// Heading of the photo section of the Distill sheet, after "Or paste the recipe".
    public let fromPhoto = plain("Or use a photo")
    /// Explains where the text is read.
    public let photoHint = plain(
      "Photograph a cookbook page or a recipe card. The text is read on this device, and only the words are sent to be distilled, as if you had pasted them."
    )
    public let macPhotoHint = plain(
      "Choose pictures of a recipe, or drop them here. The text is read on this Mac, and only the words are sent to be distilled, as if you had pasted them."
    )
    public let scanPages = plain("Scan pages")
    public let choosePhotos = plain("Choose photos")
    public let chooseFiles = plain("Choose image files")
    public let keepFirstPage = plain("Keep the first page as the recipe photo")
    /// While the pages are being read, above the page count.
    public let readingPages = plain("Reading the text…")
    /// After a tap on Scan, with no scanner to open (such as a Mac or a simulator).
    public let scannerUnavailable = plain(
      "The scanner isn't available on this device. Choose photos instead, or paste the recipe text."
    )
    public let cameraRefused = plain(
      "Cauldron isn't allowed to use the camera. Allow it in Settings, or choose photos instead.")
    /// The scanner failed after it opened.
    public let scannerStopped = plain("The scanner stopped. Try again, or choose photos instead.")
    // Failures of a read. Each one offers what to do next.
    public let noText = plain(
      "We couldn't find any text to read. Try again with the page flat and well lit, or paste the recipe text instead."
    )
    public let noRecipeInPhotos = plain(
      "We couldn't find a recipe in those photos. Check they show the ingredients and the method, or paste the recipe text instead."
    )
    public let tooMuchText = plain(
      "That's more text than one recipe. Try fewer pages, or paste just the recipe."
    )
    public let couldntReadPhotos = plain(
      "We couldn't read the text in those photos. Try again, or paste the recipe text instead.")

    public init() {}

    /// Above the pages, and beside the Distill button.
    public func pageCount(_ count: Int) -> CopyString {
      plain(count == 1 ? "1 page" : "\(count) pages")
    }

    /// Under the reading line.
    public func pageOf(_ page: Int, _ pages: Int) -> CopyString {
      plain("Page \(page) of \(pages)")
    }

    /// On the import sheet while more shared items wait their turn.
    public func moreShared(_ count: Int) -> CopyString { plain("\(count) more shared") }

    /// In the share sheet's summary.
    public func ingredientCount(_ count: Int) -> CopyString {
      plain(count == 1 ? "1 ingredient" : "\(count) ingredients")
    }

    public func stepCount(_ count: Int) -> CopyString {
      plain(count == 1 ? "1 step" : "\(count) steps")
    }

    /// In the share sheet's summary, in the tips colour: lines the import wasn't sure of.
    public func linesToCheck(_ count: Int) -> CopyString {
      plain(count == 1 ? "1 ingredient line to check" : "\(count) ingredient lines to check")
    }

    /// The accessibility label of a page's thumbnail.
    public func page(_ number: Int) -> CopyString { plain("Page \(number)") }

    public func removePage(_ number: Int) -> CopyString { plain("Remove page \(number)") }

    /// When more pages were chosen than a recipe can have.
    public func pageLimit(_ limit: Int) -> CopyString {
      plain("A recipe can have up to \(limit) pages. The rest were left out.")
    }

    /// Above the paste box after a link couldn't be read. The link stays as the recipe's source.
    public func pastingFor(_ link: String) -> CopyString {
      plain("Paste the recipe from \(link). The link stays as its source.")
    }
  }
}
