import CauldronKit
import Foundation
import Testing

/// The entities read the JSON shapes of the TypeScript schemas, so the web app's data and
/// fixtures keep their meaning. Dates are the numeric `Date` default here.
@Suite("Entity JSON")
struct EntityJSONTests {
  private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
  }

  private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
  }

  private let id = "6F9619FF-8B86-D011-B42D-00C04FC964FF"

  @Test func planEntryWithARecipe() throws {
    let entry = try decode(
      PlanEntry.self,
      """
      {"id":"\(id)","date":"2026-10-12","slot":"dinner","title":"Dal",
       "recipe":{"id":"\(id)","title":"Dal","servings":4,"totalMinutes":40,"photoKey":null,
                 "macros":{"calories":420,"protein":18,"carbs":60,"fat":null}},
       "servings":null,"position":0,"brewed":false}
      """)
    #expect(entry.date == LocalDate("2026-10-12"))
    #expect(entry.slot == .dinner)
    #expect(entry.recipe?.macros.fat == nil)
    #expect(entry.recipe?.macros.protein == 18)
    #expect(entry.servings == nil)
    #expect(try roundTrip(entry) == entry)
  }

  @Test func freeTextPlanEntryHasNoRecipe() throws {
    let entry = try decode(
      PlanEntry.self,
      """
      {"id":"\(id)","date":"2026-10-12","slot":"lunch","title":"Leftovers","recipe":null,
       "servings":2,"position":1,"brewed":false}
      """)
    #expect(entry.recipe == nil)
    #expect(entry.servings == 2)
  }

  @Test func diaryEntry() throws {
    let entry = try decode(
      DiaryEntry.self,
      """
      {"id":"\(id)","date":"2026-10-12","slot":"breakfast","name":"Eggs","amount":"2 large",
       "servings":1.5,"macros":{"calories":140,"protein":12,"carbs":1,"fat":10},
       "source":"described","recipeId":null,"position":0}
      """)
    #expect(entry.servings == 1.5)
    #expect(entry.source == .described)
    #expect(entry.recipeId == nil)
    #expect(try roundTrip(entry) == entry)
  }

  @Test func bodyProfileAndTargets() throws {
    let profile = try decode(
      BodyProfile.self,
      """
      {"sex":"unspecified","birthDate":"1990-04-01","heightCm":180,"activity":"veryActive",
       "goal":"lose","weeklyRateKg":0.5,"proteinPerKg":2,"fatShare":0.3,"weightUnit":"lb",
       "heightUnit":"ftin"}
      """)
    #expect(profile.birthDate == LocalDate("1990-04-01"))
    #expect(profile.activity == .veryActive)
    let targets = try decode(
      Targets.self,
      """
      {"calories":2200,"protein":160,"carbs":220,"fat":70,
       "overridden":{"calories":false,"protein":true,"carbs":false,"fat":false},
       "checkedInOn":null}
      """)
    #expect(targets.overridden.protein)
    #expect(targets.checkedInOn == nil)
    #expect(try roundTrip(TrackerSettings(profile: profile, targets: targets)).targets == targets)
  }

  @Test func gatherItem() throws {
    let item = try decode(
      GatherItem.self,
      """
      {"id":"\(id)","item":"lemons","itemKey":"lemon","quantity":{"min":2,"max":3},"unit":null,
       "aisle":"produce","checked":false,"manual":false,"inPantry":true,
       "sources":[{"recipeId":"\(id)","title":"Lemonade","quantity":{"min":2,"max":3},"unit":null}]}
      """)
    #expect(item.aisle == .produce)
    #expect(item.quantity == Quantity(min: 2, max: 3))
    #expect(item.sources.count == 1)
    #expect(try roundTrip(item) == item)
  }

  @Test func importDraftWithoutMacros() throws {
    let draft = try decode(
      ImportDraft.self,
      """
      {"title":"Soup","description":null,"servings":4,"prepMinutes":10,"cookMinutes":null,
       "totalMinutes":null,"sourcePlatform":"web","sourceUrl":"https://example.com/soup",
       "sourceAuthor":null,"siteName":"Example","notes":null,"photoKey":null,"tags":["soup"],
       "ingredients":[{"line":"1 onion","section":null,"unsure":false}],
       "steps":[{"text":"Simmer.","section":null,"unsure":true}],
       "unsure":["servings","macros"]}
      """)
    #expect(draft.macros == nil)
    #expect(draft.sourcePlatform == .web)
    #expect(draft.unsure == [.servings, .macros])
    #expect(draft.steps.first?.unsure == true)
    #expect(try roundTrip(draft) == draft)
  }

  @Test func importJobFailure() throws {
    let job = try decode(
      ImportJob.self,
      """
      {"id":"\(id)","status":"failed","source":"text","sourceUrl":null,"draft":null,
       "failure":{"code":"noRecipe","message":"No recipe."},"duplicateOf":null,"recipeId":null,
       "createdAt":780000000,"updatedAt":780000060}
      """)
    #expect(job.status == .failed)
    #expect(job.failure?.code == .noRecipe)
    #expect(job.createdAt == Date(timeIntervalSinceReferenceDate: 780_000_000))
  }

  @Test func recipeSummaryAndRecipe() throws {
    let recipe = try decode(
      Recipe.self,
      """
      {"id":"\(id)","title":"Dal","description":null,"servings":4,"prepMinutes":10,
       "cookMinutes":30,"totalMinutes":40,"photoKey":null,
       "macros":{"calories":null,"protein":null,"carbs":null,"fat":null},
       "tags":[{"id":"\(id)","name":"Indian","kind":"cuisine"}],"lastCookedOn":"2026-09-30",
       "createdAt":780000000,"updatedAt":780000000,"sourcePlatform":"manual","sourceUrl":null,
       "sourceAuthor":null,"notes":null,
       "ingredients":[{"section":null,"quantity":{"min":1,"max":null},"unit":"cup",
         "item":"lentils","note":null,"optional":false,"alt":null,"original":"1 cup lentils",
         "itemKey":"lentil"}],
       "steps":[{"section":null,"text":"Boil for 25 minutes.","timerSeconds":1500}],
       "deletedAt":null}
      """)
    #expect(recipe.lastCookedOn == LocalDate("2026-09-30"))
    #expect(recipe.tags.first?.kind == .cuisine)
    #expect(recipe.steps.first?.timerSeconds == 1500)
    #expect(recipe.macros == Macros.none)
    #expect(try roundTrip(recipe) == recipe)
  }

  @Test func extractedRecipeStartsEmpty() {
    let empty = ExtractedRecipe.empty
    #expect(empty.title == nil)
    #expect(empty.ingredients.isEmpty)
    #expect(empty.steps.isEmpty)
    #expect(empty.unsure.isEmpty)
    #expect(empty.macros == nil)
  }

  @Test func limitsMatchTheReference() {
    #expect(RecipeLimits.servings == 1000)
    #expect(RecipeLimits.minutes == 20_160)
    #expect(RecipeLimits.timerSeconds == 259_200)
    #expect(TrackerLimits.weightKg == 20...400)
    #expect(TrackerLimits.calories == 800...10_000)
  }
}
