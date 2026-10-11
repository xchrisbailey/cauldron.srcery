extension Copy {
  /// Distill: importing a recipe from a link or pasted text. The action is voice; labels,
  /// statuses and every failure are plain.
  public struct Imports: Sendable {
    public let title = voice("Distill a recipe")
    public let distill = voice("Distill")
    public let distilling = voice("Distilling…")
    public let link = plain("Link")
    public let linkPlaceholder = plain("https://")
    public let linkHint = plain("A recipe page, or an Instagram or TikTok post.")
    public let orPaste = plain("Or paste the recipe")
    public let pasteHint = plain("Paste it from anywhere: a notes app, an email, a caption.")
    public let pastePlaceholder = plain("Title, ingredients and method")
    public let stop = plain("Stop")
    public let stopped = plain("Stopped.")
    public let another = voice("Distill another")
    public let review = plain("Check the highlighted fields, then save.")
    public let unsureLine = plain("we may have misread it")
    public let source = plain("Source")
    public let pasted = plain("Pasted text")
    public let openDuplicate = plain("Open it")
    public let saveAnyway = plain("Saving makes a second copy.")
    public let pasteInstead = plain("Paste the text instead")
    public let tryAgain = plain("Try again")
    public let couldntStart = plain(
      "Couldn't start distilling. Check your connection and try again.")
    public let alreadySaved = plain("That draft is already saved.")
    public let notReady = plain("That draft isn't ready to save.")
    // Failures. Each one suggests what to do next.
    public let couldntRead = plain("Couldn't read that page. Paste the recipe text instead.")
    public let noRecipe = plain("We couldn't find a recipe there. Paste the recipe text instead.")
    public let noRecipeInText = plain(
      "We couldn't find a recipe in that text. Check it has the ingredients and the method.")
    public let spokenOnly = plain(
      "That post's caption doesn't have the recipe. It may only be spoken in the video, so paste the recipe text instead."
    )
    public let tooLarge = plain("That page is too large to read. Paste the recipe text instead.")
    public let blocked = plain("We can't open that link. Paste the recipe text instead.")
    public let timeout = plain("That took too long. Try again, or paste the recipe text instead.")
    public let unavailable = plain(
      "Distilling isn't available right now. Try again in a moment, or conjure the recipe by hand."
    )
    public let dailyLimit = plain(
      "That's a lot of distilling for one day. Try again tomorrow, or conjure the recipe by hand."
    )

    public init() {}

    public func duplicate(_ title: String) -> CopyString {
      plain("You already have a recipe from this link: \(title).")
    }

    /// The plain message for a failed import.
    public func failure(_ code: ImportFailureCode) -> CopyString {
      switch code {
      case .couldntRead: couldntRead
      case .noRecipe: noRecipe
      case .spokenOnly: spokenOnly
      case .tooLarge: tooLarge
      case .blocked: blocked
      case .timeout: timeout
      case .unavailable: unavailable
      }
    }
  }

  /// Start brewing. The controls stay plain because hands are busy. Brewed is voice.
  public struct Brewing: Sendable {
    public let nextStep = plain("Next step")
    public let previousStep = plain("Previous step")
    public let leave = plain("Back to the recipe")
    public let forThisStep = plain("For this step")
    public let startTimer = plain("Start timer")
    public let pause = plain("Pause")
    public let resume = plain("Resume")
    public let reset = plain("Reset")
    public let timeUp = plain("Time's up")
    public let timers = plain("Timers")
    public let wakeOn = plain("Screen stays on while you brew")
    public let wakeOff = plain("This browser can't keep the screen on, so it may sleep.")
    public let wakeRefused = plain(
      "The browser wouldn't keep the screen on just now, so it may sleep.")
    public let keys = plain("Arrow keys move between steps. Space starts or pauses the timer.")
    public let noSteps = plain("This recipe has no method steps yet. Add some, then start brewing.")
    public let editRecipe = plain("Edit recipe")
    public let brewed = voice("Brewed")
    public let couldntSave = plain("Couldn't mark it cooked. Check your connection and try again.")

    public init() {}

    public func stepOf(_ n: Int, _ of: Int) -> CopyString { plain("\(n) of \(of)") }
    public func timerFor(_ n: Int) -> CopyString { plain("Step \(n)") }
    public func timerDone(_ title: String, _ n: Int) -> CopyString {
      plain("\(title): the step \(n) timer is done.")
    }
  }
}
