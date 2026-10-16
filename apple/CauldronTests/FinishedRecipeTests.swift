import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron
@testable import CauldronImports

/// Recipes the share sheet finished: what it leaves in the App Group, and how the app puts them
/// in the box. Folders are temporary and the store is in memory; the real inbox is never touched.
@MainActor
@Suite("Finished recipes")
struct FinishedRecipeTests {
  private let container: ModelContainer
  private let context: ModelContext
  private let finished: URL
  private let drafts: URL

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
    finished = try Self.folder("finished")
    drafts = try Self.folder("drafts")
  }

  private static func folder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "FinishedRecipeTests-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func tidy() {
    try? FileManager.default.removeItem(at: finished)
    try? FileManager.default.removeItem(at: drafts)
  }

  private func files(in folder: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: folder.path()))?.sorted() ?? []
  }

  private func recipes() throws -> [RecipeRecord] {
    try ModelContext(container).fetch(FetchDescriptor<RecipeRecord>())
  }

  private func draft(title: String = "Shakshuka", link: String = "https://eats.example/shakshuka")
    -> RecipeDraft
  {
    var draft = RecipeDraft()
    draft.title = title
    draft.servings = "4"
    draft.sourceURL = link
    draft.setIngredientText(draft.ingredients[0].id, "2 tbsp olive oil")
    draft.addIngredient(after: draft.ingredients[0].id)
    draft.setIngredientText(draft.ingredients[1].id, "1 onion, diced")
    draft.setStepText(draft.steps[0].id, "Simmer for 10 minutes.")
    draft.imported = ImportedFrom(
      platform: .web, author: "Ada Cook", siteName: "Eats",
      fetchedAt: Date(timeIntervalSince1970: 5),
      rough: false)
    return draft
  }

  private func leave(
    _ draft: RecipeDraft, id: UUID = UUID(), at sharedAt: Date = .now
  ) throws -> FinishedRecipe {
    let recipe = FinishedRecipe(draft: draft, id: id, sharedAt: sharedAt)
    try FinishedInbox.add(recipe, in: finished)
    return recipe
  }

  @discardableResult
  private func receive(fileManager: FileManager = .default) -> Int {
    FinishedRecipeReceiver.receive(
      from: finished, into: context, draftsFolder: drafts, fileManager: fileManager)
  }

  // MARK: The payload

  @Test func aPayloadKeepsTheStructuredDraftAndWhereItCameFrom() throws {
    var source = draft()
    source.fill(withPage: Macros(calories: 300, protein: 20, carbs: 30, fat: 10))
    source.photo = .replace(ProcessedPhoto(data: Data([1, 2, 3]), width: 4, height: 3))
    let payload = FinishedRecipe(draft: source, sharedAt: Date(timeIntervalSince1970: 9))

    let back = try JSONDecoder().decode(
      FinishedRecipe.self, from: JSONEncoder().encode(payload))
    #expect(back == payload)
    let opened = back.recipeDraft
    #expect(opened.title == "Shakshuka")
    #expect(opened.ingredients.compactMap(\.parsed).map(\.item) == ["olive oil", "onion"])
    #expect(opened.ingredients.first?.parsed?.quantity?.min == 2)
    #expect(opened.imported?.author == "Ada Cook")
    #expect(opened.imported?.platform == .web)
    #expect(opened.pageMacros == Macros(calories: 300, protein: 20, carbs: 30, fat: 10))
    // The cover photo is not carried yet.
    #expect(opened.photo == .keep)
  }

  @Test func aWaitingEstimateTravelsAsTheMarkerOnTheDraft() throws {
    var source = draft()
    source.estimateOnSave = true
    let payload = FinishedRecipe(draft: source)
    #expect(payload.recipeDraft.estimateOnSave)
  }

  // MARK: The inbox

  @Test func payloadsComeOutOldestFirstAndStayUntilRemoved() throws {
    defer { tidy() }
    let later = try leave(draft(title: "Later"), at: Date(timeIntervalSince1970: 200))
    let earlier = try leave(draft(title: "Earlier"), at: Date(timeIntervalSince1970: 100))
    let pending = FinishedInbox.pending(from: finished)
    #expect(pending.map(\.recipe.id) == [earlier.id, later.id])
    // Reading takes nothing.
    #expect(FinishedInbox.pending(from: finished).count == 2)
    FinishedInbox.remove(pending[0])
    #expect(FinishedInbox.pending(from: finished).map(\.recipe.id) == [later.id])
  }

  @Test func theSameIdIsTheSameFile() throws {
    defer { tidy() }
    let id = UUID()
    try leave(draft(), id: id)
    try leave(draft(title: "Again"), id: id)
    #expect(files(in: finished).count == 1)
  }

  @Test func anUnreadableFileIsDroppedAndWithoutAFolderNothingIsWritten() throws {
    defer { tidy() }
    try Data("not json".utf8).write(to: finished.appending(path: "broken.json"))
    #expect(FinishedInbox.pending(from: finished).isEmpty)
    #expect(files(in: finished).isEmpty)
    #expect(throws: (any Error).self) {
      try FinishedInbox.add(FinishedRecipe(draft: draft()), in: nil)
    }
    #expect(FinishedInbox.pending(from: nil).isEmpty)
  }

  @Test func finishedRecipesDontShareTheLinkInboxesFolder() throws {
    defer { tidy() }
    try leave(draft())
    // The link inbox deletes any file it can't read as a shared item; that is its folder only.
    #expect(ShareInbox.takeAll(from: drafts).isEmpty)
    #expect(files(in: finished).count == 1)
  }

  // MARK: The box

  @Test func aFinishedRecipeBecomesOneRecipeWithStructuredIngredientsAndNoDraft() throws {
    defer { tidy() }
    let payload = try leave(draft())

    #expect(receive() == 1)
    let saved = try #require(try recipes().first)
    #expect(try recipes().count == 1)
    #expect(saved.id == payload.id)
    #expect(saved.title == "Shakshuka")
    #expect(saved.servings == 4)
    #expect(saved.sourceURL == "https://eats.example/shakshuka")
    #expect(saved.sourcePlatform == .web)
    #expect(saved.sourceAuthor == "Ada Cook")
    #expect(saved.ingredients.map(\.item) == ["olive oil", "onion"])
    #expect(saved.ingredients.first?.quantity?.min == 2)
    #expect(saved.ingredients.first?.original == "2 tbsp olive oil")
    #expect(saved.steps.map(\.text) == ["Simmer for 10 minutes."])
    // Saved, not a draft to finish: nothing is left for the editor.
    #expect(files(in: finished).isEmpty)
    #expect(files(in: drafts).isEmpty)
  }

  @Test func theFileGoesOnlyAfterTheSave() throws {
    defer { tidy() }
    let payload = try leave(draft())
    let watcher = WatchingFileManager { [container] in
      // Another context of the store, as the sync engine would be: what is saved is there.
      let saved = (try? ModelContext(container).fetch(FetchDescriptor<RecipeRecord>())) ?? []
      return saved.map(\.id)
    }

    #expect(receive(fileManager: watcher) == 1)
    #expect(watcher.removed.count == 1)
    #expect(watcher.savedAtRemoval == [[payload.id]])
  }

  @Test func replayingAPayloadInsertsNothing() throws {
    defer { tidy() }
    let id = UUID()
    try leave(draft(), id: id)
    #expect(receive() == 1)

    // A crash between the save and the delete leaves the file behind.
    try leave(draft(), id: id)
    #expect(receive() == 0)
    #expect(try recipes().count == 1)
    #expect(files(in: finished).isEmpty)
  }

  @Test func aRecipeBanishedSinceStaysBanished() throws {
    defer { tidy() }
    let id = UUID()
    try leave(draft(), id: id)
    receive()
    let saved = try #require(try context.fetch(FetchDescriptor<RecipeRecord>()).first)
    saved.deletedAt = .now
    try context.save()

    try leave(draft(), id: id)
    #expect(receive() == 0)
    #expect(try recipes().count == 1)
  }

  @Test func eachPayloadIsItsOwnRecipe() throws {
    defer { tidy() }
    try leave(draft(title: "One", link: "https://a.example/one"))
    try leave(draft(title: "Two", link: "https://a.example/two"))
    #expect(receive() == 2)
    #expect(Set(try recipes().map(\.title)) == ["One", "Two"])
  }

  @Test func anEstimateTheSheetCouldntAskForIsQueuedByTheApp() throws {
    defer { tidy() }
    var waiting = draft()
    waiting.estimateOnSave = true
    try leave(waiting)
    receive()
    let saved = try #require(try recipes().first)
    #expect(saved.macrosPending)
    #expect(try ModelContext(container).fetchCount(FetchDescriptor<AIJobRecord>()) == 1)
  }

  @Test func aPayloadTheSaverWontTakeFallsBackToItsLinkAsADraft() throws {
    defer { tidy() }
    try leave(draft(title: "   "))
    #expect(receive() == 0)
    #expect(try recipes().isEmpty)
    #expect(files(in: finished).isEmpty)
    let items = ShareInbox.takeAll(from: drafts)
    #expect(items.map(\.url) == ["https://eats.example/shakshuka"])
  }

  // MARK: The queue

  @Test func finishedRecipesAreTakenBeforeDraftItemsAndDraftsStillOpenAsDrafts() throws {
    defer { tidy() }
    try leave(draft(title: "Kept"))
    // One that can't be saved leaves its link as a draft: only a queue that takes the finished
    // ones first finds that link in the same pick-up.
    try leave(draft(title: " ", link: "https://eats.example/rescued"))
    try ShareInbox.add(SharedItem(text: "1 egg. Fry it."), in: drafts)

    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: true)
    #expect(queue.pickUp(in: context) == 1)

    #expect(try recipes().map(\.title) == ["Kept"])
    #expect(queue.waiting == 2)
    var opened: [SharedImportRoute] = []
    while let next = queue.next() { opened.append(next) }
    #expect(opened.count == 2)
    #expect(opened.contains(.link("https://eats.example/rescued")))
    #expect(opened.contains(.text("1 egg. Fry it.")))
    #expect(files(in: drafts).isEmpty)
    #expect(files(in: finished).isEmpty)
  }

  @Test func withoutAContextOnlyDraftsAreTaken() throws {
    defer { tidy() }
    try leave(draft())
    try ShareInbox.add(SharedItem(text: "1 egg. Fry it."), in: drafts)
    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: true)
    #expect(queue.pickUp() == 0)
    #expect(queue.waiting == 1)
    #expect(files(in: finished).count == 1)
  }

  @Test func aQueueThatIsntEnabledTouchesNothing() throws {
    defer { tidy() }
    try leave(draft())
    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: false)
    #expect(queue.pickUp(in: context) == 0)
    #expect(files(in: finished).count == 1)
    #expect(try recipes().isEmpty)
  }
}

/// Notes what the store held at the moment each file was removed.
private final class WatchingFileManager: FileManager, @unchecked Sendable {
  private let saved: () -> [UUID]
  private(set) var removed: [URL] = []
  private(set) var savedAtRemoval: [[UUID]] = []

  init(saved: @escaping () -> [UUID]) {
    self.saved = saved
    super.init()
  }

  override func removeItem(at url: URL) throws {
    removed.append(url)
    savedAtRemoval.append(saved())
    try super.removeItem(at: url)
  }
}
