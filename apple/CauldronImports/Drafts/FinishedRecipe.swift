import CauldronKit
import Foundation

/// A recipe the share sheet read and the cook chose to keep, left in the App Group for the app
/// to put in the recipe box (#201). The share extension never opens the store, so this is how
/// a finished recipe gets from one to the other.
///
/// It is the structured draft (`KeptDraft`: ingredients as read, not as a blob of text), where
/// the recipe came from, and the numbers the page published. The macros are in the draft too,
/// either an estimate or none with `estimateOnSave` set, which is the marker for the app to
/// queue the estimate once the recipe is saved. The cover photo is not carried: the extension
/// has little memory to spare, so it leaves the photo's link (`coverLink`) and the app fetches
/// the full-size photo itself (#203).
///
/// The `id` becomes the saved recipe's own id, so a payload that is received twice (a crash
/// between the save and the delete) finds its recipe already there.
public struct FinishedRecipe: Codable, Equatable {
  /// Bump when the shape changes; a payload with another version is dropped.
  public static let currentVersion = 1

  /// Where the recipe came from, as the saver records it.
  public struct Source: Codable, Equatable {
    public var platform: String
    public var author: String?
    /// The site's own name. Absent in a payload from before it was carried.
    public var siteName: String?
    public var fetchedAt: Date?
    public var rough: Bool
  }

  public var version = FinishedRecipe.currentVersion
  public var id: UUID
  public var sharedAt: Date
  public var draft: KeptDraft
  public var source: Source?
  /// What the imported page published, which the saver marks as the page's.
  public var pageMacros: Macros?
  /// The link to the page's cover photo, for the app to fetch. Absent in a payload from before
  /// there was one, and when the page had none.
  public var coverLink: String?

  /// - Parameters:
  ///   - draft: the recipe as the sheet read it.
  ///   - id: the recipe's id once saved.
  ///   - sharedAt: when the cook shared it.
  ///   - coverLink: where the page's cover photo is.
  public init(
    draft: RecipeDraft, id: UUID = UUID(), sharedAt: Date = .now, coverLink: String? = nil
  ) {
    self.coverLink = coverLink
    self.id = id
    self.sharedAt = sharedAt
    var kept = KeptDraft(draft)
    kept.photo = nil
    self.draft = kept
    pageMacros = draft.pageMacros
    source = draft.imported.map {
      Source(
        platform: $0.platform.rawValue, author: $0.author, siteName: $0.siteName,
        fetchedAt: $0.fetchedAt, rough: $0.rough)
    }
  }

  /// The draft to save: the one the sheet had, less its photo.
  public var recipeDraft: RecipeDraft {
    var recipe = draft.draft
    recipe.pageMacros = pageMacros
    if let source {
      recipe.imported = ImportedFrom(
        platform: SourcePlatform(rawValue: source.platform) ?? .manual, author: source.author,
        siteName: source.siteName, fetchedAt: source.fetchedAt, rough: source.rough)
    }
    return recipe
  }
}
