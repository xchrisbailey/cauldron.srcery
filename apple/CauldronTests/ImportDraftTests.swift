import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

/// An import becoming a draft in the editor, and the draft becoming a recipe.
@MainActor
@Suite("Imported drafts")
struct ImportDraftTests {
  private let context: ModelContext
  private let fixed = Date(timeIntervalSince1970: 1_800_000_000)

  init() throws {
    context = ModelContext(try CauldronStore.container(.inMemory))
  }

  /// What the pipeline makes of a recipe read by a model from a paste.
  private func distilled(_ recipe: ExtractedRecipe, rough: Bool = false) async throws -> Distilled {
    do {
      return try await Distill.text(
        "a few words about something the layout can't tell, so the model is asked",
        extractor: ScriptedExtractor(recipe: recipe, rough: rough))
    } catch {
      throw ImportDraftError("\(error)")
    }
  }

  private struct ImportDraftError: Error { let message: String; init(_ m: String) { message = m } }

  private func full() -> ExtractedRecipe {
    ExtractedRecipe(
      title: "Smoky tacos", description: "Weeknight tacos.", servings: 4, prepMinutes: 15,
      cookMinutes: 20, totalMinutes: 35,
      macros: Macros(calories: 350, protein: 20, carbs: 30.5, fat: 10), author: "Ada Cook",
      siteName: "Cook Example", tags: ["Mexican", "Quick"], notes: "Serve hot.",
      ingredients: [
        ExtractedLine(line: "2 cans black beans", section: "Filling", unsure: false),
        ExtractedLine(line: "some paprika", section: "Filling", unsure: true),
        ExtractedLine(line: "8 tortillas", section: "To serve", unsure: false),
      ],
      steps: [
        ExtractedStep(text: "Warm the beans for 5 minutes.", section: nil, unsure: false),
        ExtractedStep(text: "Fill the tortillas.", section: nil, unsure: true),
      ],
      unsure: [.servings, .tags])
  }

  // MARK: Mapping

  @Test func everyFieldIsCarriedOverAsTheEditorHoldsIt() async throws {
    let draft = RecipeDraft(
      importing: try await distilled(full()), photo: nil, link: nil, fetchedAt: fixed)
    #expect(draft.title == "Smoky tacos")
    #expect(draft.summary == "Weeknight tacos.")
    #expect(draft.servings == "4")
    #expect(draft.prepMinutes == "15" && draft.cookMinutes == "20" && draft.totalMinutes == "35")
    #expect(draft.calories == "350" && draft.protein == "20")
    #expect(draft.carbs == "30.5" && draft.fat == "10")
    #expect(draft.pageMacros == draft.typedMacros)
    #expect(draft.notes == "Serve hot.")
    #expect(draft.tags == ["Mexican", "Quick"])
    #expect(draft.sourceURL.isEmpty)
    #expect(draft.imported?.author == "Ada Cook")
    #expect(draft.imported?.siteName == "Cook Example")
    #expect(draft.imported?.platform == .text)
    #expect(draft.imported?.fetchedAt == fixed)
  }

  @Test func ingredientsComeWithTheirSectionsAsHeadingsAndAreReadByTheLineParser() async throws {
    let draft = RecipeDraft(
      importing: try await distilled(full()), photo: nil, link: nil, fetchedAt: nil)
    #expect(draft.ingredients.map(\.isHeading) == [true, false, false, true, false])
    #expect(
      draft.ingredients.map(\.text) == [
        "Filling", "2 cans black beans", "some paprika", "To serve", "8 tortillas",
      ])
    #expect(draft.ingredients[1].parsed?.item.contains("black beans") == true)
    #expect(draft.ingredients[1].parsed?.quantity != nil)
    #expect(draft.steps.map(\.text) == ["Warm the beans for 5 minutes.", "Fill the tortillas."])
    #expect(draft.steps[0].timerSeconds == 300, "a step's timer is read as it is when typed")
    #expect(draft.validate().isEmpty, "a draft that read well can be saved as it is")
  }

  @Test func whatThePipelineWasUnsureOfIsFlaggedUntilTheCookChangesIt() async throws {
    var draft = RecipeDraft(
      importing: try await distilled(full()), photo: nil, link: nil, fetchedAt: nil)
    #expect(draft.review == [.servings, .tags])
    #expect(draft.ingredients.map(\.flagged) == [false, false, true, false, false])
    #expect(draft.steps.map(\.flagged) == [false, true])
    #expect(draft.needsReview)

    draft.servings = "6"
    #expect(draft.review == [.tags])
    draft.servings = "6"
    draft.addTag("Dinner")
    #expect(draft.review.isEmpty)

    draft.setIngredientText(draft.ingredients[2].id, "1 tsp smoked paprika")
    #expect(!draft.ingredients[2].flagged)
    draft.setStepText(draft.steps[1].id, "Fill each tortilla.")
    #expect(!draft.needsReview)
  }

  @Test func settingTheFieldsUpDoesntCountAsTheCookChangingThem() async throws {
    var recipe = full()
    recipe.unsure = [.title, .description, .prepMinutes, .macros, .notes]
    let draft = RecipeDraft(
      importing: try await distilled(recipe), photo: nil, link: nil, fetchedAt: nil)
    #expect(draft.review == [.title, .description, .prepMinutes, .macros, .notes])
  }

  @Test func aRoughReadingSaysSo() async throws {
    let rough = RecipeDraft(
      importing: try await distilled(full(), rough: true), photo: nil, link: nil, fetchedAt: nil)
    #expect(rough.imported?.rough == true)
    let sure = RecipeDraft(
      importing: try await distilled(full()), photo: nil, link: nil, fetchedAt: nil)
    #expect(sure.imported?.rough == false)
  }

  @Test func theCoverPhotoJoinsTheDraftAndALinkKeptForAPasteBecomesItsSource() async throws {
    let photo = ProcessedPhoto(data: Data([1, 2, 3]), width: 10, height: 8)
    let draft = RecipeDraft(
      importing: try await distilled(full()), photo: photo,
      link: "https://www.tiktok.com/@a/video/123?is_from_webapp=1#x", fetchedAt: nil)
    #expect(draft.photo == .replace(photo))
    #expect(draft.sourceURL == "https://www.tiktok.com/@a/video/123?is_from_webapp=1")
    #expect(draft.imported?.platform == .tiktok)
    #expect(draft.imported?.fetchedAt == nil)
  }

  @Test func aRecipeWithNothingBlankFieldsAndOneEmptyRowEach() async throws {
    var bare = ExtractedRecipe(title: "Toast")
    bare.ingredients = [ExtractedLine(line: "1 slice bread", section: nil, unsure: false)]
    bare.steps = [ExtractedStep(text: "Toast it.", section: nil, unsure: false)]
    let draft = RecipeDraft(
      importing: try await distilled(bare), photo: nil, link: nil, fetchedAt: nil)
    #expect(draft.servings.isEmpty && draft.calories.isEmpty && draft.pageMacros == nil)
    #expect(!draft.needsReview)
  }

  // MARK: Saving

  private func saved(_ draft: RecipeDraft) throws -> RecipeRecord {
    try RecipeSaver.save(draft, into: nil, context: context)
  }

  @Test func savingStoresTheSourceAndThePageMacros() async throws {
    let draft = RecipeDraft(
      importing: try await distilled(full()), photo: nil, link: "https://cook.example/tacos",
      fetchedAt: fixed)
    let recipe = try saved(draft)
    #expect(recipe.sourcePlatform == .web)
    #expect(recipe.sourceURL == "https://cook.example/tacos")
    #expect(recipe.sourceAuthor == "Ada Cook")
    #expect(recipe.sourceFetchedAt == fixed)
    #expect(recipe.macrosSource == .page)
    #expect(recipe.calories == 350 && recipe.carbs == 30.5)
    #expect(recipe.ingredients.map(\.original).contains("2 cans black beans"))
    #expect(recipe.ingredients.first?.section == "Filling")
  }

  @Test func macrosTheCookChangedAreTheirOwn() async throws {
    var draft = RecipeDraft(
      importing: try await distilled(full()), photo: nil, link: nil, fetchedAt: nil)
    draft.calories = "400"
    #expect(try saved(draft).macrosSource == .manual)
  }

  @Test func pastedTextRecordsNoFetchTime() async throws {
    let recipe = try saved(
      RecipeDraft(importing: try await distilled(full()), photo: nil, link: nil, fetchedAt: nil))
    #expect(recipe.sourcePlatform == .text)
    #expect(recipe.sourceFetchedAt == nil)
  }

  @Test func theCoverPhotoIsStoredWithTheRecipe() async throws {
    let photo = ProcessedPhoto(data: Data([1, 2, 3]), width: 10, height: 8)
    let recipe = try saved(
      RecipeDraft(
        importing: try await distilled(full()), photo: photo, link: nil, fetchedAt: nil))
    #expect(recipe.photo?.imageData == Data([1, 2, 3]))
  }

  @Test func aRecipeWithNoNutritionQueuesAnEstimateAfterItIsSaved() async throws {
    var recipe = full()
    recipe.macros = nil
    let draft = RecipeDraft(
      importing: try await distilled(recipe), photo: nil, link: nil, fetchedAt: nil)
    let stored = try saved(draft)
    #expect(stored.macrosSource == nil)
    #expect(RecipeMacroEstimates.queueAfterSave(of: draft, saved: stored, in: context))
    #expect(stored.macrosPending)
    #expect((stored.aiJobs ?? []).filter { $0.kind == .recipeMacros }.count == 1)
  }

  @Test func aRecipeWhosePageGaveNutritionQueuesNothing() async throws {
    let draft = RecipeDraft(
      importing: try await distilled(full()), photo: nil, link: nil, fetchedAt: nil)
    let stored = try saved(draft)
    #expect(!RecipeMacroEstimates.queueAfterSave(of: draft, saved: stored, in: context))
    #expect(!stored.macrosPending)
    #expect((stored.aiJobs ?? []).isEmpty)
  }

  @Test func aTypedRecipeNotFromAnImportStillQueuesNothingUnlessAsked() throws {
    var draft = RecipeDraft()
    draft.title = "Toast"
    draft.setIngredientText(draft.ingredients[0].id, "1 slice bread")
    let stored = try saved(draft)
    #expect(!RecipeMacroEstimates.queueAfterSave(of: draft, saved: stored, in: context))
  }

  @Test func aDraftThatIsNeverSavedLeavesNothingBehind() async throws {
    _ = RecipeDraft(importing: try await distilled(full()), photo: nil, link: nil, fetchedAt: nil)
    #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<AIJobRecord>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<PhotoRecord>()) == 0)
  }

  // MARK: Duplicates

  private func recipe(
    _ title: String, link: String?, banished: Bool = false, created: TimeInterval = 0
  ) -> RecipeRecord {
    let record = RecipeRecord(title: title)
    record.sourceURL = link
    record.createdAt = Date(timeIntervalSince1970: created)
    if banished { record.deletedAt = .now }
    context.insert(record)
    return record
  }

  @Test func aLinkMatchesARecipeSavedFromItHoweverItWasShared() {
    let saved = recipe("Tacos", link: "https://cook.example/tacos")
    let all = [
      saved, recipe("Other", link: "https://cook.example/other"), recipe("None", link: nil),
    ]
    for link in [
      "https://cook.example/tacos", "https://cook.example/tacos/",
      "https://COOK.example/tacos?utm_source=x#top",
    ] {
      #expect(DuplicateLinks.find(in: all, links: [link])?.title == "Tacos", "\(link)")
    }
    #expect(DuplicateLinks.find(in: all, links: ["https://cook.example/soup"]) == nil)
    #expect(DuplicateLinks.find(in: all, links: [nil, ""]) == nil)
  }

  @Test func aSavedLinkWithTrackingStillMatchesItsCleanedUpForm() {
    let saved = recipe("Tacos", link: "https://cook.example/tacos/?utm_campaign=a")
    #expect(
      DuplicateLinks.find(in: [saved], links: ["https://cook.example/tacos"])?.title == "Tacos")
  }

  @Test func aBanishedRecipeIsNotADuplicateAndTheNewestOneWins() {
    let link = "https://cook.example/tacos"
    let all = [
      recipe("Banished", link: link, banished: true, created: 300),
      recipe("Old", link: link, created: 100), recipe("New", link: link, created: 200),
    ]
    #expect(DuplicateLinks.find(in: all, links: [link])?.title == "New")
    #expect(DuplicateLinks.find(in: [all[0]], links: [link]) == nil)
  }
}
