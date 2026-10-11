extension Copy {
  /// Errors are always plain. (The web app's `unauthorized` is a sign-in prompt and has no
  /// native screen.)
  public struct Errors: Sendable {
    public let forbidden = plain("You don't have access to that.")
    public let notFound = plain("We couldn't find that.")
    public let invalidRequest = plain(
      "Something in that request wasn't right. Check it and try again.")
    public let tooManyRequests = plain(
      "That's a lot of requests at once. Wait a moment and try again.")
    public let `internal` = plain("Something went wrong on our side. Try again in a moment.")
    public let unavailable = plain(
      "Cauldron can't reach its database right now. Try again in a moment.")
    public let crossSite = plain("That request came from another site, so we didn't run it.")

    public init() {}
  }

  public struct Nav: Sendable {
    public let recipes = plain("Recipes")
    public let week = plain("The week")
    public let gather = voice("Gather list")
    public let tracker = plain("Tracker")

    public init() {}
  }

  /// Tab titles for pages that have no nav label or heading of their own. Plain nouns.
  public struct PageTitles: Sendable {
    public let recipe = plain("Recipe")
    public let brew = plain("Brew")

    public init() {}
  }

  public struct UI: Sendable {
    public let appName = plain("Cauldron")
    public let byline = plain("by srcery")
    public let footer = voice("Cauldron, stirred at srcery.computer")
    /// The lockup's wordmark, set in lowercase.
    public let wordmark = plain("cauldron")
    public let tagline = voice(
      "A recipe box and weekly meal planner. Conjure recipes, distill them from a link, and stir them into the week."
    )
    public let menu = plain("Menu")
    public let close = plain("Close")
    public let loading = plain("Loading")
    public let tryAgain = plain("Try again")
    public let skipToContent = plain("Skip to content")
    public let mainNav = plain("Main")
    public let goHome = plain("Back to Cauldron")
    public let switchToLight = plain("Switch to light theme")
    public let switchToDark = plain("Switch to dark theme")

    public init() {}
  }

  /// Quantity words. Always plain.
  public struct Quantities: Sendable {
    /// Shown for amounts below 1/16 tsp.
    public let pinch = plain("pinch")

    public init() {}
  }
}
