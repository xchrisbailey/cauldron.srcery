import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Synchronization
import Testing

@testable import Cauldron

// Describe it (#179), against a scripted Gemini. The pipeline cases are ported from
// `apps/api/test/tracker-describe.test.ts`; what the reference's HTTP route did (rounding,
// bounding, trimming, the 503s) happens here in `CauldronKit`'s Gemini mapping and in
// `DescribeModel`.

private final class Flag {
  var isSet = false
}

/// Takes a long time to answer, and stops when cancelled, as `URLSession` does.
private final class SlowTransport: AITransport {
  private let count = Mutex(0)

  var requestCount: Int { count.withLock { $0 } }

  func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
    count.withLock { $0 += 1 }
    try await Task.sleep(for: .seconds(8))
    return (200, Data())
  }
}

private func food(
  _ name: String, amount: String? = nil, food: Bool = true, calories: String = "null",
  protein: String = "null", carbs: String = "null", fat: String = "null"
) -> String {
  let amount = amount.map { "\"\($0)\"" } ?? "null"
  return
    #"{"name":"\#(name)","amount":\#(amount),"food":\#(food),"calories":\#(calories),"protein":\#(protein),"carbs":\#(carbs),"fat":\#(fat)}"#
}

private func meal(_ items: String...) -> String {
  answer(#"{"items":[\#(items.joined(separator: ","))]}"#)
}

private let eggsAndToast = meal(
  food("Eggs", amount: "2 large", calories: "143", protein: "12.5", carbs: "1", fat: "9.5"),
  food("Toast", amount: "1 slice", calories: "100", protein: "4", carbs: "19", fat: "1"))

@MainActor
private func scripted(
  key: String? = "test-key", _ replies: [ScriptedTransport.Reply]
) -> (RecipeAIService, ScriptedTransport) {
  let (ai, transport, _) = service(key: key, replies)
  return (ai, transport)
}

fileprivate struct Unreachable: CustomTestStringConvertible, Sendable {
  let name: String
  let key: String?
  let reply: ScriptedTransport.Reply?
  let status: RecipeAIStatus
  var testDescription: String { name }
}

fileprivate let unreachableCases = [
  Unreachable(name: "offline", key: "k", reply: .offline, status: .ready),
  Unreachable(name: "no key", key: nil, reply: nil, status: .missingKey),
  Unreachable(name: "refused key", key: "k", reply: .status(403, "{}"), status: .invalidKey),
  Unreachable(name: "spent quota", key: "k", reply: .status(429, "{}"), status: .rateLimited),
  Unreachable(
    name: "unknown model", key: "k",
    reply: .status(404, #"{"error":{"code":404,"status":"NOT_FOUND"}}"#), status: .invalidModel),
  Unreachable(name: "server error", key: "k", reply: .status(503, "{}"), status: .ready),
]

@MainActor
@Suite("Describe it")
struct DescribeItTests {
  private let day = LocalDate(year: 2026, month: 10, day: 12)!
  private let container: ModelContainer
  private var context: ModelContext { container.mainContext }

  init() throws {
    container = try CauldronStore.container(.inMemory)
  }

  private func model(_ text: String, slot: MealSlot = .lunch) -> DescribeModel {
    let model = DescribeModel(day: day, slot: slot)
    model.text = text
    return model
  }

  /// Types `text`, asks and waits for the answer.
  private func divine(
    _ text: String, _ ai: RecipeAIService, slot: MealSlot = .lunch
  ) async -> DescribeModel {
    let model = model(text, slot: slot)
    await model.startDivining(using: ai, in: context)?.value
    return model
  }

  /// The sheet's log: into the day and meal the model was made for, closing when it works.
  private func sheet(
    for model: DescribeModel, closed: Flag = Flag()
  ) -> AddContext {
    let context = context
    return AddContext(day: model.day, slot: model.slot) { entries in
      do {
        try DiaryEditor(context: context).add(entries, on: model.day, slot: model.slot)
        closed.isSet = true
        return nil
      } catch {
        return AddContext.message(for: error)
      }
    }
  }

  private func entries() throws -> [DiaryEntryRecord] {
    try context.fetch(FetchDescriptor<DiaryEntryRecord>()).sorted { $0.position < $1.position }
  }

  private func jobs() throws -> [AIJobRecord] {
    try context.fetch(FetchDescriptor<AIJobRecord>())
  }

  // MARK: A description becomes foods to check

  @Test func aDescriptionBecomesFoodsWithRoundedBoundedNumbers() async throws {
    // Ported: "splits a meal into foods with rounded, bounded numbers".
    let (ai, transport) = scripted([
      .status(
        200,
        meal(
          food(
            "Eggs", amount: "2 large", calories: "140.4", protein: "12.26", carbs: "0.9",
            fat: "10.74"),
          food(
            "Sourdough", amount: "1 slice", calories: "120", protein: "-2", carbs: "24",
            fat: "99999"),
          food("Coffee")))
    ])
    let model = await divine("  2 eggs, sourdough and black coffee \n", ai)

    #expect(model.phase == .reviewing && model.failure == nil)
    let drafts = model.rows.map(\.draft)
    #expect(drafts.map(\.name) == ["Eggs", "Sourdough", "Coffee"])
    #expect(drafts.map(\.amount) == ["2 large", "1 slice", ""])
    #expect(drafts.map(\.calories) == ["140", "120", ""])
    #expect(drafts.map(\.protein) == ["12.5", "", ""])
    #expect(drafts.map(\.carbs) == ["1", "24", ""])
    #expect(drafts.map(\.fat) == ["10.5", "", ""])
    // Only the trimmed text is sent, once. Nothing is logged yet.
    let sent = String(decoding: try #require(transport.requests.first?.httpBody), as: UTF8.self)
    #expect(transport.requests.count == 1)
    #expect(sent.contains("2 eggs, sourdough and black coffee"))
    #expect(!sent.contains("coffee \\n"))
    #expect(try entries().isEmpty)
  }

  @Test func somethingThatIsntFoodHasNoNumbersAndCanBeRemovedOrLogged() async throws {
    // Ported: "returns null numbers for a non-food item, whatever the model said".
    let (ai, _) = scripted([
      .status(
        200, meal(food("A stapler", food: false, calories: "500", protein: "3")))
    ])
    let model = await divine("a stapler", ai)
    let row = try #require(model.rows.first)
    #expect(row.hasNoNumbers)
    #expect(row.draft.calories.isEmpty && row.draft.protein.isEmpty)

    // The reference let it through to the diary as it was; it can also be dropped.
    model.log(through: sheet(for: model))
    let logged = try #require(try entries().first)
    #expect(logged.name == "A stapler" && logged.macros == .none && logged.source == .described)
    #expect(!logged.macrosPending)
  }

  @Test func anUnreadableAnswerFailsPlainlyKeepsTheTextAndSavesNothing() async throws {
    // Ported: "fails plainly when the reply can't be read".
    let (ai, _) = scripted([.status(200, answer(#"{"items":[{"name":"Eggs"}]}"#))])
    let model = await divine("eggs", ai)
    #expect(model.phase == .writing)
    #expect(model.failure == Copy.tracker.describe.failed)
    #expect(model.text == "eggs")
    #expect(try entries().isEmpty && jobs().isEmpty)

    // The cook can ask again.
    let (again, _) = scripted([.status(200, eggsAndToast)])
    await model.startDivining(using: again, in: context)?.value
    #expect(model.phase == .reviewing && model.failure == nil)
  }

  @Test func noFoodFoundSaysSoAndSavesNothing() async throws {
    // Ported: "says so when no food was found".
    let (ai, _) = scripted([.status(200, answer(#"{"items":[]}"#))])
    let model = await divine("hmm", ai)
    #expect(model.phase == .writing)
    #expect(model.failure == Copy.tracker.describe.unreadable)
    #expect(try entries().isEmpty && jobs().isEmpty)
  }

  @Test func foodNamesAndAmountsAreTrimmedBlankOnesDroppedAndThirtyKept() async throws {
    // Ported: "fromModelMeal" (drops blank names and trims, keeps at most 30).
    let many = (0..<40).map { food("Food \($0)", calories: "10") }
    let (ai, _) = scripted([
      .status(
        200,
        meal(
          food("   "), food("  Rice ", amount: "  1 cup "), food("Salt", amount: "   ")))
    ])
    let tidy = await divine("rice", ai)
    #expect(tidy.rows.map(\.draft.name) == ["Rice", "Salt"])
    #expect(tidy.rows.map(\.draft.amount) == ["1 cup", ""])

    let (more, _) = scripted([.status(200, answer(#"{"items":[\#(many.joined(separator: ","))]}"#))]
    )
    let capped = await divine("everything", more)
    #expect(capped.rows.count == 30)
    #expect(capped.rows.first?.draft.name == "Food 0" && capped.rows.last?.draft.name == "Food 29")
  }

  @Test func blankAndOverLongTextIsNeverSent() async throws {
    // Ported: "refuses empty, blank and over-long text".
    let (ai, transport) = scripted([.status(200, eggsAndToast)])
    for text in ["", "   \n\t "] {
      let blank = model(text)
      #expect(blank.startDivining(using: ai, in: context) == nil)
      #expect(blank.phase == .writing && blank.failure == Copy.validation.required)
    }
    let long = model(String(repeating: "a", count: DescribeModel.maxLength + 1))
    #expect(long.lengthError == Copy.validation.tooLong(1000))
    #expect(long.startDivining(using: ai, in: context) == nil)
    #expect(long.failure == Copy.validation.tooLong(1000))
    #expect(transport.requests.isEmpty)

    // Exactly the limit goes through; padding around it doesn't count.
    let exact = model("  " + String(repeating: "a", count: DescribeModel.maxLength) + "\n")
    #expect(exact.lengthError == nil)
    await exact.startDivining(using: ai, in: context)?.value
    #expect(exact.phase == .reviewing)
    #expect(transport.requests.count == 1)
  }

  // MARK: Review and log

  @Test func loggingWritesOneEntryPerFoodInTheChosenMealAndDay() async throws {
    // Ported: "logs the reviewed items as separate entries in the chosen slot".
    let (ai, _) = scripted([.status(200, eggsAndToast)])
    let model = await divine("eggs and toast", ai, slot: .dinner)
    let closed = Flag()
    model.log(through: sheet(for: model, closed: closed))

    #expect(model.failure == nil && closed.isSet)
    let logged = try entries()
    #expect(logged.map(\.name) == ["Eggs", "Toast"])
    #expect(logged.map(\.amount) == ["2 large", "1 slice"])
    #expect(logged.map(\.slot) == [.dinner, .dinner])
    #expect(logged.allSatisfy { $0.day == day && $0.source == .described && !$0.macrosPending })
    #expect(logged.map(\.position) == [0, 1])
    #expect(logged.map(\.servings) == [1, 1])
    #expect(logged[0].macros == Macros(calories: 143, protein: 12.5, carbs: 1, fat: 9.5))
    #expect(logged[1].macros == Macros(calories: 100, protein: 4, carbs: 19, fat: 1))
    #expect(try jobs().isEmpty)
  }

  @Test func newEntriesGoAfterWhatTheMealAlreadyHolds() async throws {
    try DiaryWrites.add(
      [NewEntry(name: "Porridge", macros: Macros(calories: 200), source: .manual)],
      on: day, slot: .lunch, in: context)
    let (ai, _) = scripted([.status(200, eggsAndToast)])
    let model = await divine("eggs and toast", ai)
    model.log(through: sheet(for: model))
    let lunch = try entries().filter { $0.slot == .lunch }
    #expect(lunch.map(\.name) == ["Porridge", "Eggs", "Toast"])
    #expect(lunch.map(\.position) == [0, 1, 2])
  }

  @Test func foodsCanBeAdjustedAndRemovedBeforeLoggingAndTheTotalFollows() async throws {
    let (ai, _) = scripted([
      .status(
        200,
        meal(
          food("Eggs", amount: "2 large", calories: "143", protein: "12.5", carbs: "1", fat: "9.5"),
          food("Toast", amount: "1 slice", calories: "100", protein: "4", carbs: "19", fat: "1"),
          food("Coffee", calories: "2")))
    ])
    let model = await divine("eggs, toast and coffee", ai)
    #expect(model.totals.calories == 245)

    model.rows[1].draft.name = "Sourdough"
    model.rows[1].draft.amount = "2 slices"
    model.rows[1].draft.calories = "210"
    model.remove(model.rows[2])
    #expect(model.rows.count == 2)
    #expect(model.totals.calories == 353)
    #expect(model.totals.protein == 12.5 + 4)

    model.log(through: sheet(for: model))
    let logged = try entries()
    #expect(logged.map(\.name) == ["Eggs", "Sourdough"])
    #expect(logged[1].amount == "2 slices" && logged[1].calories == 210)
  }

  @Test func nothingIsLoggedWhileAnyNumberIsWrongAndTheReviewShowsWhich() async throws {
    let (ai, _) = scripted([.status(200, eggsAndToast)])
    let model = await divine("eggs and toast", ai)
    let row = model.rows[0]
    #expect(model.errors(for: row).isEmpty)

    model.rows[0].draft.calories = "lots"
    model.rows[1].draft.name = "  "
    model.log(through: sheet(for: model))
    #expect(try entries().isEmpty)
    #expect(model.phase == .reviewing)
    #expect(model.errors(for: model.rows[0])[.macro(.calories)] != nil)
    #expect(model.errors(for: model.rows[1])[.name] == Copy.validation.required)

    model.rows[0].draft.calories = "143"
    model.rows[1].draft.name = "Toast"
    model.log(through: sheet(for: model))
    #expect(try entries().count == 2)
  }

  @Test func removingEverythingLeavesNothingToLogAndStartOverKeepsTheText() async throws {
    let (ai, transport) = scripted([.status(200, eggsAndToast)])
    let model = await divine("eggs and toast", ai)
    for row in model.rows { model.remove(row) }
    model.log(through: sheet(for: model))
    #expect(try entries().isEmpty)

    model.startOver()
    #expect(model.phase == .writing && model.text == "eggs and toast" && model.rows.isEmpty)
    #expect(transport.requests.count == 1)
  }

  @Test func aFullDayRefusesTheLogAndKeepsTheReview() async throws {
    try DiaryWrites.add(
      (0..<TrackerLimits.perDay).map { NewEntry(name: "F\($0)", macros: .none, source: .manual) },
      on: day, slot: .snack, in: context)
    let (ai, _) = scripted([.status(200, eggsAndToast)])
    let model = await divine("eggs and toast", ai)
    model.log(through: sheet(for: model))
    #expect(model.failure == Copy.tracker.dayFull)
    #expect(model.phase == .reviewing && model.rows.count == 2)
    #expect(try entries().count == TrackerLimits.perDay)
  }

  // MARK: When Gemini can't be reached

  @Test(
    "an unreachable model saves one waiting entry that fills in later", arguments: unreachableCases)
  fileprivate func waitingEntry(_ case: Unreachable) async throws {
    let words = "Two eggs and toast with butter"
    let (down, transport) = scripted(key: `case`.key, [`case`.reply ?? .offline])
    let model = await divine("  \(words)\n", down, slot: .breakfast)

    // One entry, named with the cook's words, waiting, with the job to fill it in.
    #expect(model.phase == .waiting && model.failure == nil && model.rows.isEmpty)
    let waiting = try #require(try entries().first)
    #expect(try entries().count == 1)
    #expect(waiting.name == words && waiting.macrosPending && waiting.macros == .none)
    #expect(waiting.source == .described && waiting.slot == .breakfast && waiting.day == day)
    #expect(waiting.servings == 1)
    let job = try #require(try jobs().first)
    #expect(try jobs().count == 1)
    #expect(job.kind == .mealEstimate && job.input == words && job.diaryEntry === waiting)
    // The sheet reads the cook's trouble from the service: a missing key reads as that.
    #expect(down.status == `case`.status)
    #expect(down.status.needsAttention == (`case`.status != .ready))
    // Without a key nothing is sent.
    if `case`.key == nil { #expect(transport.requests.isEmpty) }

    // Still down: the entry waits, untouched, and is not guessed at.
    #expect(await AIJobQueue.drain(in: context, using: down.estimator) == 0)
    #expect(waiting.macrosPending && waiting.macros == .none && waiting.name == words)

    // Back: the same entry fills in with the foods added up, keeping the cook's words.
    let (back, _) = scripted([.status(200, eggsAndToast)])
    #expect(await AIJobQueue.drain(in: context, using: back.estimator) == 1)
    #expect(try entries().count == 1)
    #expect(!waiting.macrosPending && waiting.name == words)
    #expect(waiting.macros == Macros(calories: 243, protein: 16.5, carbs: 20, fat: 10.5))
    #expect(try jobs().isEmpty)
  }

  @Test func aLongDescriptionIsNamedByItsFirstWordsButTheJobKeepsAllOfIt() async throws {
    let words = "toast " + String(repeating: "and butter ", count: 60)
    #expect(words.count > TrackerLimits.name && words.count <= DescribeModel.maxLength)
    let (down, _) = scripted([.offline])
    let model = await divine(words, down)
    #expect(model.phase == .waiting)
    let waiting = try #require(try entries().first)
    #expect(waiting.name.count <= TrackerLimits.name && words.hasPrefix(waiting.name))
    #expect(try jobs().first?.input == words.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  @Test func theNameIsTheWordsOnOneLine() {
    #expect(DescribeModel.waitingName(" two eggs,\n  toast\tand tea ") == "two eggs, toast and tea")
  }

  @Test func aWaitingEntryCanBeRemovedAndTakesItsJobWithIt() async throws {
    let (down, _) = scripted([.offline])
    _ = await divine("eggs", down)
    let waiting = try #require(try entries().first)
    try DiaryEditor(context: context).remove(waiting)
    #expect(try entries().isEmpty && jobs().isEmpty)
  }

  @Test func aFullDayCantTakeAWaitingEntryEither() async throws {
    try DiaryWrites.add(
      (0..<TrackerLimits.perDay).map { NewEntry(name: "F\($0)", macros: .none, source: .manual) },
      on: day, slot: .snack, in: context)
    let (down, _) = scripted([.offline])
    let model = await divine("eggs", down)
    #expect(model.phase == .writing && model.failure == Copy.tracker.dayFull)
    #expect(model.text == "eggs")
    #expect(try entries().count == TrackerLimits.perDay && jobs().isEmpty)
  }

  // MARK: Not the same as unreachable

  @Test func aBadAnswerSavesNoWaitingEntryEvenWithoutAnyFoodsInIt() async throws {
    for body in [#"{"nope":1}"#, "not json"] {
      let (ai, _) = scripted([.status(200, answer(body))])
      let model = await divine("eggs", ai)
      #expect(model.phase == .writing && model.failure == Copy.tracker.describe.failed)
    }
    #expect(try entries().isEmpty && jobs().isEmpty)
  }

  @Test func aRequestThatIsCancelledSavesNothingAndSaysNothing() async throws {
    let keys = MemoryKeyStore("k")
    let transport = SlowTransport()
    let ai = RecipeAIService(
      keys: keys, gemini: GeminiRecipeAI(keys: keys, transport: transport) { "m" }, onDevice: nil)
    let model = model("eggs")
    let work = try #require(model.startDivining(using: ai, in: context))
    #expect(model.phase == .asking)
    while transport.requestCount == 0 { await Task.yield() }

    model.cancel()
    #expect(model.phase == .writing)
    await work.value
    #expect(model.phase == .writing && model.failure == nil && model.rows.isEmpty)
    #expect(try entries().isEmpty && jobs().isEmpty)
    // Being cancelled says nothing about the key or the connection.
    #expect(ai.status == .ready)
  }

  @Test func closingTheSheetCancelsTheRequest() async throws {
    let keys = MemoryKeyStore("k")
    let transport = SlowTransport()
    let ai = RecipeAIService(
      keys: keys, gemini: GeminiRecipeAI(keys: keys, transport: transport) { "m" }, onDevice: nil)
    var model: DescribeModel? = model("eggs")
    let work = try #require(model?.startDivining(using: ai, in: context))
    while transport.requestCount == 0 { await Task.yield() }

    // The sheet is gone and takes its model with it.
    model = nil
    let started = ContinuousClock.now
    await work.value
    #expect(ContinuousClock.now - started < .seconds(4))
    #expect(try entries().isEmpty && jobs().isEmpty)
  }

  @Test func askingTwiceAtOnceSendsOneRequest() async throws {
    let keys = MemoryKeyStore("k")
    let transport = SlowTransport()
    let ai = RecipeAIService(
      keys: keys, gemini: GeminiRecipeAI(keys: keys, transport: transport) { "m" }, onDevice: nil)
    let model = model("eggs")
    let first = try #require(model.startDivining(using: ai, in: context))
    #expect(model.startDivining(using: ai, in: context) == nil)
    model.cancel()
    await first.value
    #expect(transport.requestCount == 1)
  }

  // MARK: Where it shows

  @Test func describeIsOneOfTheWaysToAdd() {
    #expect(AddWay.available.contains(.describe))
    #expect(AddWay.describe.label == Copy.tracker.addTabs.describe)
  }
}

@MainActor
@Suite("Describe it screens")
struct DescribeItViewsTests {
  private let day = LocalDate(year: 2026, month: 10, day: 12)!
  private let container: ModelContainer
  private var context: ModelContext { container.mainContext }

  init() throws {
    container = try CauldronStore.container(.inMemory)
  }

  private func draws(_ view: some View) -> Bool {
    ImageRenderer(content: view.frame(width: 390, height: 800)).cgImage != nil
  }

  private func tab(
    _ model: DescribeModel, ai: RecipeAIService, scheme: ColorScheme
  ) -> some View {
    AddDescribeTab(
      context: AddContext(day: day, slot: .lunch) { _ in nil }, onClose: {}, model: model
    )
    .environment(ai)
    .environment(\.colorScheme, scheme)
    .modelContainer(container)
  }

  @Test func everyStateDrawsInBothAppearances() async throws {
    let keys = MemoryKeyStore("k")
    let held = SlowTransport()
    let asking = RecipeAIService(
      keys: keys, gemini: GeminiRecipeAI(keys: keys, transport: held) { "m" }, onDevice: nil)
    let writing = DescribeModel(day: day, slot: .lunch)

    let typed = DescribeModel(day: day, slot: .lunch)
    typed.text = "Two eggs and toast with butter"
    let work = try #require(typed.startDivining(using: asking, in: context))
    while held.requestCount == 0 { await Task.yield() }
    #expect(typed.phase == .asking)

    let (online, _) = scripted([
      .status(
        200,
        meal(
          food("Eggs", amount: "2 large", calories: "143", protein: "12.5", carbs: "1", fat: "9.5"),
          food("A stapler", food: false)))
    ])
    let reviewing = DescribeModel(day: day, slot: .lunch)
    reviewing.text = "eggs and a stapler"
    await reviewing.startDivining(using: online, in: context)?.value
    #expect(reviewing.phase == .reviewing)
    reviewing.log(through: AddContext(day: day, slot: .lunch) { _ in nil })

    let (offline, _) = scripted([.offline])
    let waiting = DescribeModel(day: day, slot: .lunch)
    waiting.text = "Two eggs and toast with butter"
    await waiting.startDivining(using: offline, in: context)?.value
    #expect(waiting.phase == .waiting)

    let (broken, _) = scripted([.status(200, answer("{}"))])
    let failed = DescribeModel(day: day, slot: .lunch)
    failed.text = "eggs"
    await failed.startDivining(using: broken, in: context)?.value
    #expect(failed.failure != nil)

    let keyless = RecipeAIService.offline()
    #expect(keyless.status.needsAttention)

    for scheme in [ColorScheme.light, .dark] {
      #expect(draws(tab(writing, ai: online, scheme: scheme)), "empty \(scheme)")
      #expect(draws(tab(typed, ai: asking, scheme: scheme)), "asking \(scheme)")
      #expect(draws(tab(reviewing, ai: online, scheme: scheme)), "review \(scheme)")
      #expect(draws(tab(waiting, ai: offline, scheme: scheme)), "waiting \(scheme)")
      #expect(draws(tab(failed, ai: broken, scheme: scheme)), "failed \(scheme)")
      #expect(draws(tab(writing, ai: keyless, scheme: scheme)), "attention \(scheme)")
      #expect(draws(tab(waiting, ai: keyless, scheme: scheme)), "waiting, attention \(scheme)")
    }
    // Not drawn inside a navigation stack: iOS stops when one is drawn off screen (see
    // `DiaryViewsTests`).
    typed.cancel()
    await work.value
  }

  @Test func aWaitingEntryDrawsInTheDiaryInBothAppearances() throws {
    let waiting = DiaryEntryRecord(
      day: day, slot: .breakfast, name: "Two eggs and toast", source: .described)
    waiting.macrosPending = true
    context.insert(waiting)
    let filled = DiaryEntryRecord(day: day, slot: .breakfast, name: "Tea", source: .manual)
    filled.macros = Macros(calories: 2)
    context.insert(filled)
    try context.save()
    for scheme in [ColorScheme.light, .dark] {
      let view = DiaryView(today: day, targets: nil, openTargets: {})
        .modelContainer(container)
        .environment(\.colorScheme, scheme)
      #expect(draws(view), "\(scheme)")
    }
  }

  @Test func theWaitingWordsAreInTheCopyModuleAndPlain() {
    #expect(Copy.describeNative.waitingRow.tone == .plain)
    #expect(Copy.describeNative.waitingSheet.tone == .plain)
  }
}

private let gregorian: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
  return calendar
}()

@MainActor
@Suite("Waiting described meals")
struct WaitingMealTests {
  private let day = LocalDate(year: 2026, month: 10, day: 10)!
  private let container: ModelContainer
  private var context: ModelContext { container.mainContext }

  init() throws {
    container = try CauldronStore.container(.inMemory)
  }

  /// A described meal saved while Gemini was out of reach.
  private func waitingMeal(_ words: String = "eggs and toast") async throws -> DiaryEntryRecord {
    let (down, _) = scripted([.offline])
    let model = DescribeModel(day: day, slot: .breakfast)
    model.text = words
    await model.startDivining(using: down, in: context)?.value
    #expect(model.phase == .waiting)
    return try #require(try context.fetch(FetchDescriptor<DiaryEntryRecord>()).first)
  }

  private func jobs() throws -> [AIJobRecord] {
    try context.fetch(FetchDescriptor<AIJobRecord>())
  }

  @Test func numbersTypedIntoAWaitingMealStandWhenTheEstimateArrives() async throws {
    let waiting = try await waitingMeal()
    var draft = EntryDraft(waiting)
    draft.calories = "320"
    draft.protein = "21"
    try DiaryEditor(context: context).update(
      waiting, with: try #require(draft.valid(requireCalories: false)))
    #expect(!waiting.macrosPending)

    // A good answer arrives: nothing is asked, nothing is written over, and no job is left.
    let (back, transport) = scripted([.status(200, eggsAndToast)])
    await AIJobQueue.drain(in: context, using: back.estimator)
    #expect(transport.requests.isEmpty)
    #expect(waiting.macros == Macros(calories: 320, protein: 21))
    #expect(!waiting.macrosPending && waiting.name == "eggs and toast")
    #expect(try jobs().isEmpty)
  }

  @Test func anEditWithNoNumbersKeepsTheMealWaitingAndItStillFillsIn() async throws {
    let waiting = try await waitingMeal()
    var draft = EntryDraft(waiting)
    draft.name = "eggs and toast, breakfast"
    draft.slot = .snack
    try DiaryEditor(context: context).update(
      waiting, with: try #require(draft.valid(requireCalories: false)))
    #expect(waiting.macrosPending && waiting.slot == .snack)
    #expect(try jobs().count == 1)

    let (back, _) = scripted([.status(200, eggsAndToast)])
    await AIJobQueue.drain(in: context, using: back.estimator)
    #expect(!waiting.macrosPending && waiting.macros.calories == 243)
    #expect(try jobs().isEmpty)
  }

  @Test func healthGetsTheMealOnceTheQueueHasFilledItIn() async throws {
    let store = FakeHealthStore()
    let defaults = try #require(UserDefaults(suiteName: "waiting-meal-\(UUID().uuidString)"))
    let health = HealthSync(
      store: store, setup: HealthSetup(isConfigured: true), defaults: defaults,
      calendar: gregorian,
      now: { [day] in
        gregorian.date(
          from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
          ?? .now
      })
    await health.connect()
    let waiting = try await waitingMeal()

    // Still down: nothing finished, nothing to tell Health.
    let (down, _) = scripted([.offline])
    #expect(await AIQueueRunner.drain(in: context, using: down.estimator, health: health) == 0)
    await health.settle()
    #expect(await store.held.isEmpty)

    // Back: the numbers arrive and the nutrition reaches Health without any diary edit.
    let (back, _) = scripted([.status(200, eggsAndToast)])
    #expect(await AIQueueRunner.drain(in: context, using: back.estimator, health: health) == 1)
    await health.settle()
    let held = await store.held
    #expect(held[HealthNutrition.syncID(entry: waiting.id, nutrient: .energy)]?.value == 243)
    #expect(held.count == 4)
  }
}
