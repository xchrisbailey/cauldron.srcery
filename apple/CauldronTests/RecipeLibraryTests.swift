import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Recipe library")
struct RecipeLibraryTests {
  private let context: ModelContext

  init() throws {
    context = ModelContext(try CauldronStore.container(.inMemory))
  }

  @discardableResult
  private func recipe(
    _ title: String, items: [String] = [], tags: [String] = [], summary: String? = nil,
    created: TimeInterval = 0, cooked: String? = nil, banished: Bool = false, id: Int? = nil
  ) -> RecipeRecord {
    let record = RecipeRecord(title: title)
    context.insert(record)
    if let id {
      // The ids that sort by number: 00000000-0000-0000-0000-00000000000N.
      record.id =
        UUID(uuidString: "00000000-0000-0000-0000-" + String(format: "%012d", id)) ?? UUID()
    }
    record.summary = summary
    record.ingredients = items.map {
      Ingredient(
        section: nil, quantity: nil, unit: nil, item: $0, note: nil, optional: false, alt: nil,
        original: $0, itemKey: ingredientKey($0))
    }
    record.tags = tags.map { name in
      // A name in any case is the tag that is already there.
      let existing = (try? context.fetch(FetchDescriptor<TagRecord>())) ?? []
      if let tag = existing.first(where: { $0.name.lowercased() == name.lowercased() }) {
        return tag
      }
      let tag = TagRecord(name: name)
      context.insert(tag)
      return tag
    }
    record.createdAt = Date(timeIntervalSince1970: created)
    record.lastCookedOn = cooked.flatMap { LocalDate($0) }
    if banished { record.deletedAt = .now }
    record.refreshSearchText()
    return record
  }

  private func titles(
    _ recipes: [RecipeRecord], matching query: String = "", tag: String? = nil,
    sort: RecipeSort = .recent
  ) -> [String] {
    RecipeLibrary.visible(recipes, matching: query, tag: tag, sort: sort).map(\.title)
  }

  // MARK: Search

  @Test func aBlankSearchKeepsEveryRecipe() {
    let all = [recipe("Soup"), recipe("Cookies", created: 1)]
    #expect(Set(titles(all, matching: "   ")) == ["Soup", "Cookies"])
  }

  @Test func searchMatchesTitleIngredientAndTagAnyCase() {
    let all = [
      recipe("Shakshuka", items: ["feta"]),
      recipe("Oats", tags: ["Breakfast"]),
      recipe("Soup", items: ["white beans"]),
    ]
    #expect(titles(all, matching: "SHAK") == ["Shakshuka"])
    #expect(titles(all, matching: "feta") == ["Shakshuka"])
    #expect(titles(all, matching: "breakfast") == ["Oats"])
    #expect(titles(all, matching: "beans") == ["Soup"])
    #expect(titles(all, matching: "nothing at all").isEmpty)
  }

  @Test func everyWordOfASearchHasToMatch() {
    let all = [recipe("Tomato soup", items: ["basil"]), recipe("Tomato salad")]
    #expect(titles(all, matching: "tomato basil") == ["Tomato soup"])
    #expect(titles(all, matching: " basil  tomato ") == ["Tomato soup"])
  }

  @Test func banishedRecipesAreHiddenFromTheListAndSearch() {
    let all = [recipe("Soup"), recipe("Stew", banished: true)]
    #expect(titles(all) == ["Soup"])
    #expect(titles(all, matching: "stew").isEmpty)
  }

  @Test func banishingHidesTheRecipeButKeepsItsRow() throws {
    let soup = recipe("Soup")
    let stew = recipe("Stew")
    let now = Date(timeIntervalSince1970: 1_000)
    RecipeLibrary.banish(soup, at: now)
    #expect(soup.deletedAt == now)
    #expect(titles([soup, stew]) == ["Stew"])
    #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 2)
  }

  @Test func banishingTwiceKeepsTheFirstTime() {
    let soup = recipe("Soup")
    RecipeLibrary.banish(soup, at: Date(timeIntervalSince1970: 1_000))
    RecipeLibrary.banish(soup, at: Date(timeIntervalSince1970: 2_000))
    #expect(soup.deletedAt == Date(timeIntervalSince1970: 1_000))
  }

  @Test func restoringBringsABanishedRecipeBackIntoTheList() {
    let soup = recipe("Soup")
    let stew = recipe("Stew")
    RecipeLibrary.banish(soup)
    #expect(titles([soup, stew]) == ["Stew"])
    RecipeLibrary.restore(soup)
    #expect(soup.deletedAt == nil)
    #expect(Set(titles([soup, stew])) == ["Soup", "Stew"])
    #expect(titles([soup, stew], matching: "soup") == ["Soup"])
  }

  @Test func restoringARecipeThatWasNeverBanishedChangesNothing() {
    let soup = recipe("Soup")
    RecipeLibrary.restore(soup)
    #expect(soup.deletedAt == nil)
    #expect(titles([soup]) == ["Soup"])
  }

  // MARK: Notice

  @Test func theNoticeAfterABanishOffersUndoAndAfterARestoreDoesNot() {
    let soup = recipe("Soup")
    let banished = RecipeNotice.banished(soup)
    #expect(banished.text == "Banished Soup.")
    #expect(banished.undoLabel == "Undo")
    let restored = RecipeNotice.restored
    #expect(restored.text == "Restored.")
    #expect(restored.undoLabel == nil)
  }

  // MARK: Sort

  @Test func newestFirstUsesTheCreatedDate() {
    let all = [recipe("Old", created: 1), recipe("New", created: 9), recipe("Mid", created: 5)]
    #expect(titles(all, sort: .recent) == ["New", "Mid", "Old"])
  }

  @Test func titleSortIgnoresCase() {
    let all = [recipe("banana bread"), recipe("Apple pie"), recipe("Cookies")]
    #expect(titles(all, sort: .title) == ["Apple pie", "banana bread", "Cookies"])
  }

  @Test func lastCookedPutsTheLatestFirstAndNeverCookedLast() {
    let all = [
      recipe("Never too", id: 4),
      recipe("Spring", cooked: "2026-04-01", id: 3),
      recipe("Autumn", cooked: "2026-10-01", id: 2),
      recipe("Never", id: 1),
    ]
    #expect(titles(all, sort: .lastCooked) == ["Autumn", "Spring", "Never too", "Never"])
  }

  // The web breaks a tie by id: highest first for newest and last cooked, lowest first for A to Z.
  @Test func newestAndLastCookedBreakATieByTheHigherIDFirst() {
    let created = [recipe("B", created: 4, id: 1), recipe("A", created: 4, id: 2)]
    #expect(titles(created, sort: .recent) == ["A", "B"])
    let cooked = [
      recipe("A", cooked: "2026-04-01", id: 1), recipe("B", cooked: "2026-04-01", id: 2),
    ]
    #expect(titles(cooked, sort: .lastCooked) == ["B", "A"])
  }

  @Test func aTitleTieInAToZBreaksByTheLowerIDFirst() {
    let all = [recipe("soup", id: 2), recipe("Soup", id: 1)]
    #expect(
      RecipeLibrary.visible(all, matching: "", sort: .title).map(\.title) == ["Soup", "soup"])
  }

  @Test func sortsReadTheirNamesFromTheCopyModule() {
    #expect(RecipeSort.allCases.map(\.label.text) == ["Newest", "A to Z", "Last cooked"])
  }

  // MARK: Search like the web

  @Test func searchMatchesTheDescription() {
    let all = [
      recipe("Fries", summary: "A crispy side for burgers"), recipe("Salad"),
    ]
    #expect(titles(all, matching: "crispy") == ["Fries"])
    #expect(titles(all, matching: "burger") == ["Fries"])
  }

  @Test func searchFindsPluralsBothWays() {
    let all = [
      recipe("Tomato soup"), recipe("Roasted potatoes"), recipe("Mixed berry crumble"),
      recipe("Salad", items: ["cherry tomatoes"]),
    ]
    #expect(Set(titles(all, matching: "tomatoes")) == ["Tomato soup", "Salad"])
    #expect(Set(titles(all, matching: "tomato")) == ["Tomato soup", "Salad"])
    #expect(titles(all, matching: "potato") == ["Roasted potatoes"])
    #expect(titles(all, matching: "berries") == ["Mixed berry crumble"])
  }

  @Test func searchWordsMatchTheStartOfAWordButATitleMatchesWholeTextAnywhere() {
    let all = [recipe("Shakshuka", items: ["feta"]), recipe("Oats")]
    #expect(titles(all, matching: "shak") == ["Shakshuka"])
    // "uka" starts no word, but the title contains it.
    #expect(titles(all, matching: "uka") == ["Shakshuka"])
    // The same letters inside an ingredient are not enough.
    #expect(titles(all, matching: "eta").isEmpty)
  }

  @Test func searchFindsARecipeByATagItWasRenamedFor() {
    let all = [recipe("Spaghetti", tags: ["Pasta"])]
    #expect(RecipeTagRename.rename("pasta", to: "Noodles", in: context) == .success("noodles"))
    #expect(titles(all, matching: "noodles") == ["Spaghetti"])
    #expect(titles(all, matching: "pasta").isEmpty)
  }

  // MARK: Tag filter

  @Test func theTagFilterKeepsRecipesWithThatTagInAnyCase() {
    let all = [
      recipe("Soup", tags: ["Dinner"]), recipe("Oats", tags: ["Breakfast"]), recipe("Plain"),
    ]
    #expect(titles(all, tag: "dinner") == ["Soup"])
    #expect(titles(all, tag: "breakfast") == ["Oats"])
    #expect(titles(all, tag: "lunch").isEmpty)
    #expect(Set(titles(all, tag: nil)) == ["Soup", "Oats", "Plain"])
  }

  @Test func theTagFilterAndTheSearchNarrowTogether() {
    let all = [
      recipe("Tomato soup", tags: ["Dinner"]), recipe("Tomato toast", tags: ["Breakfast"]),
    ]
    #expect(titles(all, matching: "tomato", tag: "dinner") == ["Tomato soup"])
    #expect(titles(all, matching: "toast", tag: "dinner").isEmpty)
  }

  @Test func aTagFilterIsOneTagAtATimeAndKeepsTheSort() {
    let all = [
      recipe("Old", tags: ["A"], created: 1), recipe("New", tags: ["A"], created: 9),
      recipe("Other", tags: ["B"], created: 5),
    ]
    #expect(titles(all, tag: "a", sort: .recent) == ["New", "Old"])
    #expect(titles(all, tag: "a", sort: .title) == ["New", "Old"])
  }

  @Test func tagOptionsCountTheRecipesAndLeaveOutBanishedOnes() {
    let all = [
      recipe("Soup", tags: ["Dinner", "Quick"]), recipe("Stew", tags: ["dinner"]),
      recipe("Gone", tags: ["Dinner", "Old"], banished: true),
    ]
    let options = RecipeLibrary.tagOptions(all)
    // One tag in two cases is one option.
    #expect(options.map(\.key) == ["dinner", "quick"])
    #expect(options.map(\.count) == [2, 1])
    #expect(options.map(\.label) == ["Dinner (2)", "Quick (1)"])
  }

  @Test func tagOptionsAreByNameWhateverTheCase() {
    let all = [
      recipe("A", tags: ["zesty"]), recipe("B", tags: ["Apple"]), recipe("C", tags: ["mild"]),
    ]
    #expect(RecipeLibrary.tagOptions(all).map(\.name) == ["Apple", "mild", "zesty"])
  }

  @Test func theSelectedTagStaysInTheMenuWithNoRecipes() {
    let all = [recipe("Soup", tags: ["Dinner"])]
    let options = RecipeLibrary.tagOptions(all, selected: "lunch")
    #expect(options.map(\.key) == ["dinner", "lunch"])
    #expect(options.last?.count == 0)
    #expect(RecipeLibrary.tagOptions(all, selected: "dinner").count == 1)
  }

  // MARK: Rename a tag

  private func tagNames() -> [String] {
    ((try? context.fetch(FetchDescriptor<TagRecord>())) ?? []).map(\.name).sorted()
  }

  @Test func renamingATagRenamesItForEveryRecipeAndKeepsTheCount() {
    let spaghetti = recipe("Spaghetti", tags: ["Pasta"])
    let penne = recipe("Penne", tags: ["pasta", "Quick"])
    #expect(RecipeTagRename.rename("pasta", to: "Noodles", in: context) == .success("noodles"))
    #expect(spaghetti.tags?.map(\.name) == ["Noodles"])
    #expect(Set(penne.tags?.map(\.name) ?? []) == ["Noodles", "Quick"])
    #expect(tagNames() == ["Noodles", "Quick"])
    #expect(
      RecipeLibrary.tagOptions([spaghetti, penne]).map(\.label) == ["Noodles (2)", "Quick (1)"])
    #expect(spaghetti.searchText.contains("noodles"))
    #expect(!spaghetti.searchText.contains("pasta"))
  }

  @Test func renamingTrimsTheName() {
    recipe("Soup", tags: ["Dinner"])
    #expect(RecipeTagRename.rename("dinner", to: "  Supper \n", in: context) == .success("supper"))
    #expect(tagNames() == ["Supper"])
  }

  @Test func renamingOntoAnotherTagsNameInAnyCaseIsRefused() {
    let soup = recipe("Soup", tags: ["Lunch", "Dinner"])
    #expect(RecipeTagRename.rename("lunch", to: "dinner", in: context) == .failure(.taken))
    #expect(RecipeTagRename.rename("lunch", to: "DINNER", in: context) == .failure(.taken))
    #expect(Set(soup.tags?.map(\.name) ?? []) == ["Lunch", "Dinner"])
    #expect(RecipeTagRename.Failure.taken.message.text == "You already have a tag with that name.")
  }

  @Test func renamingJustTheCaseOfATagsOwnNameIsFine() {
    recipe("Soup", tags: ["Lunch"])
    #expect(RecipeTagRename.rename("lunch", to: "LUNCH", in: context) == .success("lunch"))
    #expect(tagNames() == ["LUNCH"])
  }

  @Test func aBlankOrTooLongNameIsRefusedAndNothingChanges() {
    recipe("Soup", tags: ["Lunch"])
    #expect(RecipeTagRename.rename("lunch", to: "   ", in: context) == .failure(.blank))
    let long = String(repeating: "x", count: RecipeLimits.tag + 1)
    #expect(RecipeTagRename.rename("lunch", to: long, in: context) == .failure(.tooLong))
    let longest = String(repeating: "x", count: RecipeLimits.tag)
    #expect(RecipeTagRename.rename("lunch", to: longest, in: context) == .success(longest))
    #expect(RecipeTagRename.Failure.blank.message.text == "Fill this in.")
    #expect(
      RecipeTagRename.Failure.tooLong.message.text == "Keep it to 40 characters or fewer.")
  }

  @Test func renamingATagThatIsntThereIsRefused() {
    recipe("Soup", tags: ["Lunch"])
    #expect(RecipeTagRename.rename("nothing", to: "Dinner", in: context) == .failure(.missing))
    #expect(tagNames() == ["Lunch"])
  }

  @Test func twoRowsOfOneTagAreRenamedTogether() {
    // Two devices each made "Soup" before they synced.
    let a = TagRecord(name: "Soup")
    let b = TagRecord(name: "soup")
    context.insert(a)
    context.insert(b)
    #expect(RecipeTagRename.rename("soup", to: "Stew", in: context) == .success("stew"))
    #expect([a.name, b.name] == ["Stew", "Stew"])
  }

  // MARK: Summon

  @Test func summonOffersNothingForABlankSearch() {
    let all = [recipe("Soup")]
    #expect(RecipeLibrary.summon(all, matching: "").isEmpty)
    #expect(RecipeLibrary.summon(all, matching: "  !").isEmpty)
  }

  @Test func summonPutsATitleThatStartsWithTheQueryFirstThenByTitle() {
    let all = [
      recipe("Zesty chicken soup"), recipe("Chicken soup"), recipe("Soup", items: ["chicken"]),
      recipe("Chicken curry"), recipe("Soup of the day", banished: true),
    ]
    let found = RecipeLibrary.summon(all, matching: "chicken").map(\.title)
    #expect(found == ["Chicken curry", "Chicken soup", "Zesty chicken soup", "Soup"])
  }

  @Test func summonStopsAtTheLimitAndSkipsBanishedRecipes() {
    let all = (1...15).map { recipe("Soup \($0)") } + [recipe("Soup gone", banished: true)]
    #expect(RecipeLibrary.summon(all, matching: "soup").count == 10)
    #expect(RecipeLibrary.summon(all, matching: "soup", limit: 3).count == 3)
    #expect(RecipeLibrary.summon(all, matching: "gone").isEmpty)
  }

  @Test func summonFindsPluralsAndDescriptions() {
    let all = [recipe("Salad", items: ["tomato"]), recipe("Fries", summary: "Crispy")]
    #expect(RecipeLibrary.summon(all, matching: "tomatoes").map(\.title) == ["Salad"])
    #expect(RecipeLibrary.summon(all, matching: "crispy").map(\.title) == ["Fries"])
  }

  // MARK: The search index

  @Test func everySearchBoxGetsTheSameRecipesFromAKeptIndexAsFromNone() {
    let all = [
      recipe("Zesty chicken soup", created: 1), recipe("Chicken soup", created: 2),
      recipe("Soup", items: ["chicken"], created: 3), recipe("Chicken curry", created: 4),
      recipe("Soup of the day", created: 5, banished: true), recipe("Cake", created: 6),
    ]
    let cache = RecipeSearchCache()
    let index = cache.index(for: all)
    for query in ["", "chicken", "soup", "chickens", "the day", "zzz", "chicken soup"] {
      for sort in RecipeSort.allCases {
        #expect(
          RecipeLibrary.visible(all, matching: query, sort: sort, index: index).map(\.id)
            == RecipeLibrary.visible(all, matching: query, sort: sort).map(\.id))
      }
      #expect(
        RecipeLibrary.summon(all, matching: query, index: index).map(\.id)
          == RecipeLibrary.summon(all, matching: query).map(\.id))
      #expect(
        RecipePicker.matches(all, query: query, index: index).map(\.id)
          == RecipePicker.matches(all, query: query).map(\.id))
      #expect(
        StirFlowSheet.matches(all, search: query, index: index).map(\.id)
          == StirFlowSheet.matches(all, search: query).map(\.id))
    }
  }

  @Test func theLibraryTheSummonSheetTheLogPickerAndTheStirSheetAgree() {
    let all = [
      recipe("Zesty chicken soup", created: 1), recipe("Chicken soup", created: 2),
      recipe("Soup", items: ["chicken"], created: 3), recipe("Chicken curry", created: 4),
      recipe("Soup of the day", created: 5, banished: true),
    ]
    let index = RecipeSearchCache().index(for: all)
    // The library by title, ⌘K by rank, the log picker by title and Stir by newest.
    #expect(
      RecipeLibrary.visible(all, matching: "chicken", sort: .title, index: index).map(\.title)
        == ["Chicken curry", "Chicken soup", "Soup", "Zesty chicken soup"])
    #expect(
      RecipeLibrary.summon(all, matching: "chicken", index: index).map(\.title)
        == ["Chicken curry", "Chicken soup", "Zesty chicken soup", "Soup"])
    #expect(
      RecipePicker.matches(all, query: "chicken", index: index).map(\.title)
        == ["Chicken curry", "Chicken soup", "Soup", "Zesty chicken soup"])
    #expect(
      StirFlowSheet.matches(all, search: " chicken ", index: index).map(\.title)
        == ["Chicken curry", "Soup", "Chicken soup", "Zesty chicken soup"])
  }

  @Test func theStirSheetListsTheLastCookedUntilASearchAndStopsAtThirty() {
    let all = (1...40).map { recipe("Soup \($0)", created: TimeInterval($0)) }
    let cooked = all[3]
    cooked.lastCookedOn = LocalDate("2026-01-05")
    #expect(StirFlowSheet.matches(all, search: "  ").first?.title == "Soup 4")
    #expect(StirFlowSheet.matches(all, search: "  ").count == 30)
    #expect(StirFlowSheet.matches(all, search: "soup").first?.title == "Soup 40")
    #expect(StirFlowSheet.matches(all, search: "soup").count == 30)
  }

  @Test func theCachedIndexIsBuiltOnlyWhenARecipesSearchInputsChange() {
    let soup = recipe("Soup", summary: "A warm bowl")
    let cake = recipe("Cake")
    let cache = RecipeSearchCache()
    _ = cache.index(for: [soup, cake])
    _ = cache.index(for: [soup, cake])
    #expect(cache.builds == 1)
    // Nothing search reads: no rebuild.
    soup.notes = "Serve hot"
    soup.servings = 4
    soup.lastCookedOn = LocalDate("2026-01-05")
    _ = cache.index(for: [soup, cake])
    #expect(cache.builds == 1)
    // Each thing it does read.
    soup.searchKeywords = "comfort"
    _ = cache.index(for: [soup, cake])
    #expect(cache.builds == 2)
    soup.summary = "A hot bowl"
    _ = cache.index(for: [soup, cake])
    #expect(cache.builds == 3)
    soup.title = "Stew"
    soup.refreshSearchText()
    _ = cache.index(for: [soup, cake])
    #expect(cache.builds == 4)
    _ = cache.index(for: [cake])
    #expect(cache.builds == 5)
  }

  @Test func theCachedIndexFollowsTheRecipesSearchableText() {
    let soup = recipe("Soup")
    let cake = recipe("Cake")
    let cache = RecipeSearchCache()
    #expect(
      RecipeLibrary.visible(
        [soup, cake], matching: "soup", sort: .title, index: cache.index(for: [soup, cake])
      ).map(\.title)
        == ["Soup"])
    soup.title = "Stew"
    soup.refreshSearchText()
    #expect(
      RecipeLibrary.visible(
        [soup, cake], matching: "soup", sort: .title, index: cache.index(for: [soup, cake])
      ).isEmpty)
    #expect(
      RecipeLibrary.visible(
        [soup, cake], matching: "stew", sort: .title, index: cache.index(for: [soup, cake])
      ).map(\.title)
        == ["Stew"])
    soup.summary = "with cake crumbs"
    #expect(
      RecipeLibrary.summon(
        [soup, cake], matching: "crumbs", index: cache.index(for: [soup, cake])
      ).map(\.title)
        == ["Stew"])
    let more = recipe("Soup again")
    #expect(
      RecipeLibrary.summon(
        [soup, cake, more], matching: "again", index: cache.index(for: [soup, cake, more])
      ).map(\.title)
        == ["Soup again"])
  }

  // MARK: Close matches

  /// A box where "chiken soup" is found twice over: "Mochiken soup" holds the whole query so it
  /// is exact, and the others need "chiken" forgiven.
  private func closeBox() -> [RecipeRecord] {
    [
      recipe("Mochiken soup", created: 1), recipe("Chicken soup", created: 2),
      recipe("Another chicken soup", created: 3), recipe("Cake", created: 4),
    ]
  }

  @Test func aTypoFindsTheRecipeUnderCloseMatchesWithAReason() {
    let all = [recipe("Chicken curry"), recipe("Cake")]
    let found = RecipeLibrary.visibleMatches(all, matching: "chiken", sort: .title)
    #expect(found.map(\.recipe.title) == ["Chicken curry"])
    #expect(found.map(\.tier) == [.close])
    #expect(found.first?.reasonLine == "Matched chicken")
    #expect(found.first?.shortReasonLine == "Matched chicken")
    #expect(found.exact.isEmpty)
    #expect(found.close.count == 1)
  }

  @Test func exactMatchesComeFirstAndLookTheSameAsBefore() {
    let found = RecipeLibrary.visibleMatches(closeBox(), matching: "chiken soup", sort: .recent)
    #expect(found.map(\.recipe.title) == ["Mochiken soup", "Another chicken soup", "Chicken soup"])
    #expect(found.exact.map(\.recipe.title) == ["Mochiken soup"])
    #expect(found.exact.allSatisfy { $0.reasonLine == nil && $0.shortReasonLine == nil })
    #expect(found.close.map(\.recipe.title) == ["Another chicken soup", "Chicken soup"])
    #expect(found.close.allSatisfy { $0.reasonLine == "Matched chicken, soup" })
  }

  @Test func eachTierKeepsTheOrderTheCookChose() {
    let all = closeBox()
    func order(_ sort: RecipeSort) -> [String] {
      RecipeLibrary.visible(all, matching: "chiken soup", sort: sort).map(\.title)
    }
    #expect(order(.recent) == ["Mochiken soup", "Another chicken soup", "Chicken soup"])
    #expect(order(.title) == ["Mochiken soup", "Another chicken soup", "Chicken soup"])
    all[1].lastCookedOn = LocalDate("2026-01-05")
    #expect(order(.lastCooked) == ["Mochiken soup", "Chicken soup", "Another chicken soup"])
  }

  @Test func theWordsAMisspeltSearchFindsAreTheRecipesOwn() {
    let all = [recipe("Soup", items: ["chickens"]), recipe("Cake")]
    let found = RecipeLibrary.summonMatches(all, matching: "chickn")
    #expect(found.map(\.recipe.title) == ["Soup"])
    #expect(found.first?.reasonLine == "Matched chickens")
  }

  @Test func summonStopsAtTenAcrossBothTiersExactFirst() {
    let exact = (1...3).map { recipe("Mochiken soup \($0)") }
    let close = (1...12).map { recipe("Chicken soup \($0)") }
    let found = RecipeLibrary.summonMatches(exact + close, matching: "chiken soup")
    #expect(found.count == 10)
    #expect(found.prefix(3).allSatisfy { $0.tier == .exact })
    #expect(found.dropFirst(3).allSatisfy { $0.tier == .close })
    #expect(RecipeLibrary.summon(exact + close, matching: "chiken soup").count == 10)
  }

  @Test func theLogPickerAndTheStirSheetStopAtTheirLimitsAcrossBothTiers() {
    let exact = (1...5).map { recipe("Mochiken soup \($0)") }
    let close = (1...60).map { recipe("Chicken soup \($0)", created: TimeInterval($0)) }
    let all = exact + close

    let logged = RecipePicker.found(all, query: "chiken soup")
    #expect(logged.count == 50)
    #expect(logged.prefix(5).allSatisfy { $0.tier == .exact })
    #expect(logged.dropFirst(5).allSatisfy { $0.tier == .close })

    let stirred = StirFlowSheet.found(all, search: "chiken soup")
    #expect(stirred.count == 30)
    #expect(stirred.prefix(5).allSatisfy { $0.tier == .exact })
    #expect(stirred.dropFirst(5).first?.recipe.title == "Chicken soup 60")
  }

  @Test func everySearchBoxFindsATypoTheSameWay() {
    let all = closeBox()
    let index = RecipeSearchCache().index(for: all)
    let library = RecipeLibrary.visibleMatches(
      all, matching: "chiken soup", sort: .title, index: index)
    let summon = RecipeLibrary.summonMatches(all, matching: "chiken soup", index: index)
    let log = RecipePicker.found(all, query: "chiken soup", index: index)
    let stir = StirFlowSheet.found(all, search: "chiken soup", index: index)
    for surface in [summon, log, stir] {
      #expect(Set(surface.map(\.id)) == Set(library.map(\.id)))
      #expect(surface.map(\.tier).sorted() == library.map(\.tier).sorted())
    }
    #expect(
      summon.map(\.recipe.title) == ["Mochiken soup", "Another chicken soup", "Chicken soup"])
  }

  @Test func theKeptIndexGivesTheSameCloseMatchesAsNoIndex() {
    let all = closeBox()
    let index = RecipeSearchCache().index(for: all)
    for query in ["chiken soup", "chiken", "choup", "caek"] {
      let kept = RecipeLibrary.visibleMatches(all, matching: query, sort: .title, index: index)
      let none = RecipeLibrary.visibleMatches(all, matching: query, sort: .title)
      #expect(kept.map(\.id) == none.map(\.id))
      #expect(kept.map(\.reasonLine) == none.map(\.reasonLine))
    }
  }

  @Test func aBanishedRecipeIsNeverACloseMatch() {
    let all = [recipe("Chicken pie", banished: true), recipe("Cake")]
    #expect(RecipeLibrary.visibleMatches(all, matching: "chiken", sort: .title).isEmpty)
    #expect(RecipeLibrary.summonMatches(all, matching: "chiken").isEmpty)
  }

  @Test func aPartialMatchNamesTheMissingWordInTheListAndInSummon() {
    let all = [
      recipe("Pad thai", items: ["rice noodles", "peanuts"]), recipe("Cake"),
    ]
    let listed = RecipeLibrary.visibleMatches(all, matching: "spicy peanut noodles", sort: .title)
    #expect(listed.map(\.recipe.title) == ["Pad thai"])
    #expect(listed.map(\.tier) == [.partial])
    #expect(listed.first?.reasonLine == "Matched peanut, noodles · no spicy")
    #expect(listed.close.count == 1)
    #expect(listed.exact.isEmpty)

    let summoned = RecipeLibrary.summonMatches(all, matching: "spicy peanut noodles")
    #expect(summoned.map(\.recipe.title) == ["Pad thai"])
    #expect(summoned.first?.shortReasonLine == "Matched peanut, noodles · no spicy")
  }

  @Test func partialMatchesComeAfterTheCloseOnesWhateverTheSort() {
    // "Chicken soup" lacks "bowl" and "Chicken soup bowl" needs "chiken" forgiven: it sorts
    // first by title but is the better match.
    let all = [recipe("Chicken soup", created: 2), recipe("Chicken soup bowl", created: 1)]
    for sort in [RecipeSort.title, .recent] {
      let listed = RecipeLibrary.visibleMatches(all, matching: "chiken soup bowl", sort: sort)
      #expect(listed.map(\.recipe.title) == ["Chicken soup bowl", "Chicken soup"])
      #expect(listed.map(\.tier) == [.close, .partial])
    }
    let summoned = RecipeLibrary.summonMatches(all, matching: "chiken soup bowl")
    #expect(summoned.map(\.tier) == [.close, .partial])
    #expect(summoned.last?.reasonLine == "Matched chicken, soup · no bowl")
  }

  @Test func twoWordsStillNeedBothAndFillerWordsDoNotCount() {
    let all = [recipe("Pad thai", items: ["rice noodles", "peanuts"])]
    #expect(RecipeLibrary.visible(all, matching: "spicy peanut", sort: .title).isEmpty)
    #expect(RecipeLibrary.visible(all, matching: "something spicy peanut", sort: .title).isEmpty)
    #expect(RecipeLibrary.visible(all, matching: "a recipe with peanut", sort: .title).count == 1)
  }

  @Test func theCloseMatchStringsAreFromTheCopyModule() {
    #expect(Copy.libraryNative.closeMatches.text == "Close matches")
  }

  @Test func theLibraryCopyForFiltersIsFromTheCopyModule() {
    #expect(Copy.library.allTags.text == "All tags")
    #expect(Copy.library.clearFilters.text == "Clear filters")
    #expect(Copy.libraryNative.renameTag.text == "Rename tag…")
    #expect(Copy.libraryNative.renameTagTitle("Soup").text == "Rename Soup")
  }
}
