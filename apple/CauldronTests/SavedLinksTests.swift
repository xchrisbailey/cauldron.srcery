import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron
@testable import CauldronImports

/// The saved-links index (#204): the rules it matches by, the file, when the app rewrites it,
/// and the share sheet's duplicate flag and banner. Every index lives in a temporary folder;
/// the real App Group is never touched.
@MainActor
@Suite("Saved links")
struct SavedLinksTests {
  private let folder: URL
  private let index: SavedLinksIndex
  private let context: ModelContext

  init() throws {
    folder = FileManager.default.temporaryDirectory.appending(
      path: "SavedLinksTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    index = SavedLinksIndex(folder: folder)
    context = ModelContext(try CauldronStore.container(.inMemory))
  }

  private func tidy() { try? FileManager.default.removeItem(at: folder) }

  private func draft(_ title: String = "Soup", link: String = "") -> RecipeDraft {
    var draft = RecipeDraft()
    draft.title = title
    draft.sourceURL = link
    draft.setIngredientText(draft.ingredients[0].id, "1 onion")
    draft.setStepText(draft.steps[0].id, "Cook it.")
    return draft
  }

  @discardableResult
  private func save(_ title: String = "Soup", link: String = "") throws -> RecipeRecord {
    try RecipeSaver.save(draft(title, link: link), into: nil, context: context, index: index)
  }

  private func files() -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: folder.path()))?.sorted() ?? []
  }

  // MARK: The rules

  @Test func aLinkIsKeptAsGivenAndWithoutWhatDoesntChangeThePage() {
    let keys = SavedLinks.keys(of: " https://cook.example/tacos/?utm_source=x#top \n")
    #expect(keys == ["https://cook.example/tacos/?utm_source=x#top", "https://cook.example/tacos"])
    #expect(SavedLinks.keys(of: nil).isEmpty)
    #expect(SavedLinks.keys(of: "  ").isEmpty)
    // A link that is already tidy is one key; blanks add none.
    #expect(SavedLinks.keys(of: ["https://a.example/x", nil, ""]) == ["https://a.example/x"])
  }

  @Test func theIndexMatchesWhateverTheAppsDuplicateRulesDo() throws {
    // Every pair of these, saved against shared, must agree with `DuplicateLinks.find`.
    let links = [
      "https://cook.example/tacos", "https://cook.example/tacos/",
      "https://cook.example/tacos?utm_source=share", "https://cook.example/tacos#steps",
      "  https://cook.example/tacos  ", "https://cook.example/burritos",
      "https://COOK.example/tacos", "http://cook.example/tacos", "not a link", "", "tacos",
    ]
    for saved in links {
      let recipe = RecipeRecord(title: "Saved")
      recipe.sourceURL = saved
      let keys = SavedLinks.keys(of: saved)
      for shared in links {
        let app = DuplicateLinks.find(in: [recipe], links: [shared]) != nil
        #expect(
          SavedLinks.contains(keys, anyOf: [shared]) == app,
          "saved \(saved.debugDescription), shared \(shared.debugDescription)")
      }
    }
  }

  @Test func aBanishedRecipeIsNotADuplicateByTheAppsRulesEither() {
    let recipe = RecipeRecord(title: "Saved")
    recipe.sourceURL = "https://cook.example/tacos"
    #expect(DuplicateLinks.find(in: [recipe], links: [recipe.sourceURL]) === recipe)
    recipe.deletedAt = .now
    #expect(DuplicateLinks.find(in: [recipe], links: [recipe.sourceURL]) == nil)
  }

  // MARK: The file

  @Test func theIndexIsWrittenWholeAndReadBack() throws {
    defer { tidy() }
    #expect(index.read().isEmpty)
    try index.write(["https://a.example/x", "https://a.example/y"])
    #expect(index.read() == ["https://a.example/x", "https://a.example/y"])
    try index.write(["https://b.example"])
    #expect(index.read() == ["https://b.example"])
    // Written by moving a whole file into place: nothing else is left in the folder.
    #expect(files() == [SavedLinksIndex.fileName])
  }

  @Test func anIndexThatCantBeReadIsEmptyNotAnError() throws {
    defer { tidy() }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: SavedLinksIndex.fileName)
    try Data("{ half a file".utf8).write(to: file)
    #expect(index.read().isEmpty)
    try Data(#"{"version":99,"links":["https://a.example"]}"#.utf8).write(to: file)
    #expect(index.read().isEmpty)
  }

  @Test func withNoFolderNothingIsReadOrWritten() throws {
    let nowhere = SavedLinksIndex(folder: nil)
    #expect(nowhere.read().isEmpty)
    #expect(throws: CocoaError.self) { try nowhere.write(["https://a.example"]) }
    try save(link: "https://cook.example/tacos")
    #expect(!nowhere.rewrite(from: context))
  }

  @Test func theAppKeepsNoIndexUnderTest() {
    #expect(SavedLinksIndex.live.folder == nil)
    #expect(SavedLinksIndex.live(mode: .inMemory).folder == nil)
  }

  // MARK: When the app rewrites it

  @Test func savingARecipeAddsItsLink() throws {
    defer { tidy() }
    #expect(index.read().isEmpty)
    try save(link: " https://cook.example/tacos?utm_source=share ")
    #expect(
      index.read() == [
        "https://cook.example/tacos?utm_source=share", "https://cook.example/tacos",
      ])
  }

  @Test func aRecipeWithNoLinkAddsNothing() throws {
    defer { tidy() }
    try save()
    #expect(index.read().isEmpty)
    #expect(files() == [SavedLinksIndex.fileName])
  }

  @Test func editingTheLinkMovesItInTheIndex() throws {
    defer { tidy() }
    let recipe = try save(link: "https://cook.example/tacos")
    #expect(SavedLinks.contains(index.read(), anyOf: ["https://cook.example/tacos"]))

    try RecipeSaver.save(
      draft(link: "https://cook.example/burritos"), into: recipe, context: context, index: index)
    #expect(!SavedLinks.contains(index.read(), anyOf: ["https://cook.example/tacos"]))
    #expect(SavedLinks.contains(index.read(), anyOf: ["https://cook.example/burritos"]))

    try RecipeSaver.save(draft(link: ""), into: recipe, context: context, index: index)
    #expect(index.read().isEmpty)
  }

  @Test func twoRecipesFromOneLinkKeepItUntilBothAreGone() throws {
    defer { tidy() }
    let first = try save("One", link: "https://cook.example/tacos")
    let second = try save("Two", link: "https://cook.example/tacos/")
    RecipeLibrary.banish(first, index: index)
    #expect(SavedLinks.contains(index.read(), anyOf: ["https://cook.example/tacos"]))
    RecipeLibrary.banish(second, index: index)
    #expect(index.read().isEmpty)
  }

  @Test func banishingDropsTheLinkAndRestoringBringsItBack() throws {
    defer { tidy() }
    let recipe = try save(link: "https://cook.example/tacos")
    try save("Other", link: "https://cook.example/soup")

    // Not saved yet: the index follows the banish as the cook sees it.
    RecipeLibrary.banish(recipe, index: index)
    #expect(!SavedLinks.contains(index.read(), anyOf: ["https://cook.example/tacos"]))
    #expect(SavedLinks.contains(index.read(), anyOf: ["https://cook.example/soup"]))

    RecipeLibrary.restore(recipe, index: index)
    #expect(SavedLinks.contains(index.read(), anyOf: ["https://cook.example/tacos"]))
  }

  @Test func aRecipeDeletedFromTheStoreLeavesTheIndexAtTheNextRewrite() throws {
    defer { tidy() }
    let recipe = try save(link: "https://cook.example/tacos")
    context.delete(recipe)
    try context.save()
    #expect(index.rewrite(from: context))
    #expect(index.read().isEmpty)
  }

  @Test func launchRebuildsTheIndexFromTheStore() throws {
    defer { tidy() }
    try save("Kept", link: "https://cook.example/tacos")
    let gone = try save("Gone", link: "https://cook.example/gone")
    gone.deletedAt = .now
    try context.save()
    // An index left stale: it still has a link that is gone, and lacks one that was synced in.
    try index.write(["https://cook.example/gone", "https://stale.example"])

    #expect(index.rewrite(from: context))
    let links = index.read()
    #expect(SavedLinks.contains(links, anyOf: ["https://cook.example/tacos"]))
    #expect(!SavedLinks.contains(links, anyOf: ["https://cook.example/gone"]))
    #expect(!SavedLinks.contains(links, anyOf: ["https://stale.example"]))
  }

  @Test func launchWritesAnIndexWhereThereWasNone() throws {
    defer { tidy() }
    let recipe = RecipeRecord(title: "Synced")
    recipe.sourceURL = "https://cook.example/tacos"
    context.insert(recipe)
    try context.save()
    #expect(index.read().isEmpty)
    #expect(index.rewrite(from: context))
    #expect(SavedLinks.contains(index.read(), anyOf: ["https://cook.example/tacos"]))
  }

  @Test func aFinishedRecipeFromTheSheetAddsItsLink() throws {
    defer { tidy() }
    let inbox = folder.appending(path: "finished", directoryHint: .isDirectory)
    try FinishedInbox.add(
      FinishedRecipe(
        draft: draft("Tacos", link: "https://cook.example/tacos"), id: UUID(),
        sharedAt: .now),
      in: inbox)
    #expect(
      FinishedRecipeReceiver.receive(
        from: inbox, into: context, draftsFolder: nil, index: index
      ).added == 1)
    #expect(SavedLinks.contains(index.read(), anyOf: ["https://cook.example/tacos"]))
  }

  // MARK: The sheet

  private func sheet(
    _ link: String, saved: Set<String>, fetcher: ScriptedFetcher? = nil
  ) -> ShareSheetModel {
    ShareSheetModel(
      item: SharedItem(url: link),
      importer: ImportModel(
        fetcher: fetcher
          ?? ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)]),
        extractor: nil, options: ImportFixtures.quick,
        findDuplicate: ShareSheetModel.duplicateLookup(savedLinks: { saved })),
      finishedFolder: folder.appending(path: "finished"),
      inboxFolder: folder.appending(path: "drafts"), closeDelay: .milliseconds(1), close: { _ in })
  }

  private func review(_ sheet: ShareSheetModel) throws -> ShareSheetModel.Review {
    guard case .ready(let review) = sheet.phase else {
      throw SheetNotReady(phase: "\(sheet.phase)")
    }
    return review
  }

  private struct SheetNotReady: Error { let phase: String }

  @Test func aLinkAlreadyInTheBoxFlagsTheReview() async throws {
    defer { tidy() }
    let sheet = sheet(
      ImportFixtures.tacosLink, saved: SavedLinks.keys(of: ImportFixtures.tacosLink))
    sheet.start()
    await sheet.finished()
    #expect(try review(sheet).duplicate)
  }

  @Test func theLookupAsksWithTheSharedLinkAndTheOneThePageNames() async throws {
    defer { tidy() }
    // The box has the same page under a tidier address than the one shared.
    let shared = ImportFixtures.tacosLink + "?utm_source=share"
    let sheet = sheet(
      shared, saved: SavedLinks.keys(of: ImportFixtures.tacosLink),
      fetcher: ScriptedFetcher([shared: ImportFixtures.tacos(image: false)]))
    sheet.start()
    await sheet.finished()
    #expect(try review(sheet).duplicate)
  }

  @Test func aLinkNotInTheBoxIsNotFlagged() async throws {
    defer { tidy() }
    let sheet = sheet(
      ImportFixtures.tacosLink, saved: SavedLinks.keys(of: "https://cook.example/burritos"))
    sheet.start()
    await sheet.finished()
    #expect(try !review(sheet).duplicate)
  }

  @Test func withNoIndexNothingIsFlagged() async throws {
    defer { tidy() }
    let sheet = sheet(ImportFixtures.tacosLink, saved: [])
    sheet.start()
    await sheet.finished()
    #expect(try !review(sheet).duplicate)
  }

  @Test func savingAnotherCopyStillLeavesTheRecipe() async throws {
    defer { tidy() }
    let finished = folder.appending(path: "finished")
    let sheet = sheet(
      ImportFixtures.tacosLink, saved: SavedLinks.keys(of: ImportFixtures.tacosLink))
    sheet.start()
    await sheet.finished()
    #expect(try review(sheet).duplicate)
    sheet.save()
    #expect(sheet.phase == .saved)
    #expect(FinishedInbox.pending(from: finished).count == 1)
  }

  @Test func theSheetReadsTheIndexThroughTheSameRules() async throws {
    defer { tidy() }
    try save(link: ImportFixtures.tacosLink + "/")
    let live = index
    let sheet = ShareSheetModel(
      item: SharedItem(url: ImportFixtures.tacosLink),
      importer: ImportModel(
        fetcher: ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)]),
        extractor: nil, options: ImportFixtures.quick,
        findDuplicate: ShareSheetModel.duplicateLookup(savedLinks: { live.read() })),
      finishedFolder: nil, inboxFolder: nil, closeDelay: .milliseconds(1), close: { _ in })
    sheet.start()
    await sheet.finished()
    #expect(try review(sheet).duplicate)
  }

  @Test func theBannerAndTheSaveLabelRenderInBothAppearances() async throws {
    defer { tidy() }
    let sheet = sheet(
      ImportFixtures.tacosLink, saved: SavedLinks.keys(of: ImportFixtures.tacosLink))
    sheet.start()
    await sheet.finished()
    #expect(try review(sheet).duplicate)
    #expect(Copy.importNative.alreadyInBox.text == "You already have this one")
    #expect(Copy.importNative.saveAnotherCopy.text == "Save another copy")
    for scheme in [ColorScheme.light, .dark] {
      let view = ShareSheetView(model: sheet).environment(\.colorScheme, scheme)
        .frame(width: 380, height: 420)
      #expect(ImageRenderer(content: view).cgImage != nil, "duplicate in \(scheme)")
    }
    sheet.cancel()
  }
}
