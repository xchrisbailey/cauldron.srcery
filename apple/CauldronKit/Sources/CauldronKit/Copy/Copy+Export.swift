extension Copy {
  /// The Export section of Settings. The native app's own, with nothing like it in the web
  /// app's copy table, so it sits beside `catalogue` rather than in it, and the reference
  /// comparison in `CopyTests` doesn't expect it. Plain nouns and plain errors.
  public static let export = Export()

  public struct Export: Sendable {
    public let title = plain("Export")
    public let explanation = plain(
      "Save a copy of everything in Cauldron: recipes, the week, Gather lists, the diary, weigh-ins and targets in one file, and photos in a zip beside it."
    )
    public let action = plain("Export everything")
    public let working = plain("Exporting")
    public let share = plain("Save or share")
    public let failed = plain(
      "Couldn't export your data. Check this device has room to spare and try again.")

    public init() {}

    public func ready(recipes: Int, photos: Int) -> CopyString {
      let recipeCount = "\(recipes) \(recipes == 1 ? "recipe" : "recipes")"
      let photoCount = "\(photos) \(photos == 1 ? "photo" : "photos")"
      return plain("Exported \(recipeCount) and \(photoCount).")
    }

    /// Shown under a finished export that left rows out.
    public func skipped(_ count: Int) -> CopyString {
      plain(
        count == 1
          ? "1 entry couldn't be read, so it was left out."
          : "\(count) entries couldn't be read, so they were left out.")
    }
  }
}
