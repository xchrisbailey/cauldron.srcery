import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Synchronization
import Testing

@testable import Cauldron
@testable import CauldronImports

/// Answers requests from a list, in order, and keeps what it was sent.
final class ScriptedTransport: AITransport {
  enum Reply {
    case status(Int, String)
    case offline
  }

  private let replies: Mutex<[Reply]>
  private let seen = Mutex<[URLRequest]>([])

  init(_ replies: [Reply]) {
    self.replies = Mutex(replies)
  }

  var requests: [URLRequest] { seen.withLock { $0 } }

  func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
    seen.withLock { $0.append(request) }
    let reply = replies.withLock { $0.isEmpty ? Reply.offline : $0.removeFirst() }
    switch reply {
    case .status(let status, let body): return (status, Data(body.utf8))
    case .offline: throw URLError(.notConnectedToInternet)
    }
  }
}

/// Holds every request until `release()`, so two callers can be caught mid-flight.
private final class HeldTransport: AITransport {
  private let body: String
  private let count = Mutex(0)
  private let waiters = Mutex<[CheckedContinuation<Void, Never>]>([])

  init(answering body: String) {
    self.body = body
  }

  var requestCount: Int { count.withLock { $0 } }

  func release() {
    let held = waiters.withLock { held in
      defer { held = [] }
      return held
    }
    for waiter in held { waiter.resume() }
  }

  func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
    count.withLock { $0 += 1 }
    await withCheckedContinuation { waiter in waiters.withLock { $0.append(waiter) } }
    return (200, Data(body.utf8))
  }
}

/// A Gemini response whose answer is `json`.
func answer(_ json: String) -> String {
  let body: [String: Any] = [
    "candidates": [["content": ["parts": [["text": json]]], "finishReason": "STOP"]],
    "usageMetadata": ["promptTokenCount": 10, "candidatesTokenCount": 5],
  ]
  return String(decoding: try! JSONSerialization.data(withJSONObject: body), as: UTF8.self)
}

let macrosJSON = #"{"servings":4,"calories":310,"protein":17,"carbs":18,"fat":19}"#
private let recipeJSON =
  #"{"recipe":"found","title":"Fried eggs","description":null,"servings":1,"prepMinutes":null,"cookMinutes":3,"totalMinutes":null,"ingredients":[{"line":"2 eggs","section":null,"unsure":false}],"steps":[{"text":"Fry them.","section":null,"unsure":false}],"tags":[],"notes":null,"unsure":[]}"#

/// An on-device model that always reads the same recipe.
private struct StubOnDevice: RecipeAI {
  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    Extraction(outcome: .found, recipe: ExtractedRecipe(title: "From the device"), usage: nil)
  }

  func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros {
    throw .unreachable
  }

  func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem] {
    throw .unreachable
  }
}

@MainActor
func service(
  key: String? = "test-key", _ replies: [ScriptedTransport.Reply], onDevice: Bool = false
) -> (RecipeAIService, ScriptedTransport, MemoryKeyStore) {
  let keys = MemoryKeyStore(key)
  let transport = ScriptedTransport(replies)
  let ai = RecipeAIService(
    keys: keys,
    client: CloudRecipeAI(provider: .gemini, keys: keys, transport: transport) { "gemini-test" },
    onDevice: onDevice ? StubOnDevice() : nil)
  return (ai, transport, keys)
}

@MainActor
@Suite("Gemini client")
struct GeminiClientTests {
  @Test func aRequestCarriesTheKeyInAHeaderAndNowhereElse() async throws {
    let (ai, transport, _) = service([.status(200, answer(recipeJSON))])
    let extraction = try await ai.extract(ExtractInput(text: "2 eggs. Fry them.", kind: .text))
    #expect(extraction.recipe.title == "Fried eggs")
    #expect(extraction.usage == AIUsage(model: "gemini-test", inputTokens: 10, outputTokens: 5))
    #expect(!extraction.rough)

    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let url = try #require(request.url)
    #expect(url.absoluteString.hasSuffix("/models/gemini-test:generateContent"))
    #expect(!url.absoluteString.contains("test-key"))
    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
    #expect(body.contains("2 eggs. Fry them."))
    #expect(!body.contains("test-key"))
  }

  @Test func withoutAKeyNothingIsSent() async {
    let (ai, transport, _) = service(key: nil, [.status(200, answer(recipeJSON))])
    #expect(ai.status == .missingKey)
    await #expect(throws: RecipeAIError.missingKey) {
      try await ai.extract(ExtractInput(text: "x", kind: .text))
    }
    #expect(transport.requests.isEmpty)
  }

  @Test func theModelCanBeChangedInSettings() throws {
    let defaults = try #require(UserDefaults(suiteName: "RecipeAITests.model"))
    defaults.removePersistentDomain(forName: "RecipeAITests.model")
    #expect(RecipeAIService.chosenModel(for: .gemini, defaults) == "gemini-3.5-flash-lite")
    defaults.set("  gemini-3.5-pro ", forKey: RecipeAIService.modelDefaultsKey(for: .gemini))
    #expect(RecipeAIService.chosenModel(for: .gemini, defaults) == "gemini-3.5-pro")
    defaults.set("   ", forKey: RecipeAIService.modelDefaultsKey(for: .gemini))
    #expect(RecipeAIService.chosenModel(for: .gemini, defaults) == "gemini-3.5-flash-lite")
  }
}

@MainActor
@Suite("AI service")
struct RecipeAIServiceTests {
  private let input = ExtractInput(text: "2 eggs. Fry them.", kind: .text)

  @Test func offlineTheDeviceReadsTheRecipeAndItIsMarkedRough() async throws {
    let (ai, _, _) = service([.offline], onDevice: true)
    let extraction = try await ai.extract(input)
    #expect(extraction.recipe.title == "From the device")
    #expect(extraction.rough)
    // Being offline says nothing lasting about the key.
    #expect(ai.status == .ready)
  }

  @Test func aSpentQuotaFallsBackAndLeavesALineThatStays() async throws {
    let (ai, _, _) = service(
      [.status(429, "{}"), .status(200, answer(recipeJSON))], onDevice: true)
    let rough = try await ai.extract(input)
    #expect(rough.rough)
    #expect(ai.status == .rateLimited)
    // It clears itself the next time Gemini answers.
    let fine = try await ai.extract(input)
    #expect(!fine.rough)
    #expect(ai.status == .ready)
  }

  @Test func aRefusedKeyShowsAsInvalid() async {
    let (ai, _, _) = service([.status(403, "{}")])
    await #expect(throws: RecipeAIError.invalidKey) { try await ai.extract(input) }
    #expect(ai.status == .invalidKey)
  }

  @Test func aBadAnswerIsAFailureWithNoFallback() async {
    let (ai, _, _) = service([.status(200, answer(#"{"nope":1}"#))], onDevice: true)
    await #expect(throws: RecipeAIError.failed(detail: "bad output")) {
      try await ai.extract(input)
    }
    #expect(ai.status == .ready)
  }

  @Test func savingAndRemovingTheKeyMovesTheStatus() {
    let (ai, _, keys) = service(key: nil, [])
    #expect(!ai.hasKey && ai.status == .missingKey)
    #expect(ai.saveKey("  abc123 \n"))
    #expect(keys.key() == "abc123")
    #expect(ai.hasKey && ai.status == .ready)
    #expect(ai.removeKey())
    #expect(keys.key() == nil)
    #expect(!ai.hasKey && ai.status == .missingKey)
  }

  @Test func aKeyThatArrivesFromAnotherDeviceIsNoticed() {
    let (ai, _, keys) = service(key: nil, [])
    #expect(!ai.hasKey && ai.status == .missingKey)
    // iCloud Keychain puts it there without telling the app.
    #expect(throws: Never.self) { try keys.setKey("from-the-iphone") }
    ai.refreshKey()
    #expect(ai.hasKey && ai.status == .ready)
    #expect(throws: Never.self) { try keys.setKey(nil) }
    ai.refreshKey()
    #expect(!ai.hasKey && ai.status == .missingKey)
  }

  @Test func aCancelledRequestIsntMistakenForBeingOffline() async {
    let (ai, _, _) = service([.offline], onDevice: true)
    let input = input
    let task = Task { @MainActor () -> RecipeAIError? in
      // Cancelled before it starts, as closing the sheet that asked would do.
      withUnsafeCurrentTask { $0?.cancel() }
      do throws(RecipeAIError) {
        _ = try await ai.extract(input)
        return nil
      } catch {
        return error
      }
    }
    #expect(await task.value == .cancelled)
  }

  @Test func aKeychainThatRefusesIsReported() {
    let keys = MemoryKeyStore(nil, failsToSave: true)
    let ai = RecipeAIService(
      keys: keys,
      client: CloudRecipeAI(provider: .gemini, keys: keys, transport: NoTransport()) { "m" },
      onDevice: nil)
    #expect(!ai.saveKey("abc"))
    #expect(ai.keyNotSaved)
    #expect(!ai.hasKey)
  }
}

@MainActor
@Suite("AI job queue")
struct AIJobQueueTests {
  private let container: ModelContainer
  private var context: ModelContext { container.mainContext }

  init() throws {
    container = try CauldronStore.container(.inMemory)
  }

  private func recipe(_ title: String = "Shakshuka") -> RecipeRecord {
    let recipe = RecipeRecord(title: title)
    recipe.servings = 4
    recipe.ingredients = [
      Ingredient(
        section: nil, quantity: nil, unit: nil, item: "eggs", note: nil, optional: false,
        alt: nil, original: "6 large eggs", itemKey: "egg")
    ]
    context.insert(recipe)
    return recipe
  }

  private func jobs() throws -> [AIJobRecord] {
    try context.fetch(FetchDescriptor<AIJobRecord>())
  }

  @Test func aQueuedEstimateFinishesWhenGeminiCanBeReachedAgain() async throws {
    let recipe = recipe()
    AIJobQueue.enqueueMacros(for: recipe, in: context)
    #expect(recipe.macrosPending)
    #expect(AIJobQueue.waitingCount(in: context) == 1)

    // Offline: the job waits, untouched, and the recipe's macros are not guessed.
    let (ai, transport, _) = service([.offline, .status(200, answer(macrosJSON))])
    #expect(await AIJobQueue.drain(in: context, using: ai.estimator) == 0)
    let waiting = try #require(try jobs().first)
    #expect(waiting.status == .waiting && waiting.attempts == 0)
    #expect(recipe.macrosPending && recipe.macros == .none)

    // Back online.
    #expect(await AIJobQueue.drain(in: context, using: ai.estimator) == 1)
    #expect(try jobs().isEmpty)
    #expect(!recipe.macrosPending)
    #expect(recipe.macros == Macros(calories: 310, protein: 17, carbs: 18, fat: 19))
    #expect(recipe.macrosSource == .estimated)

    let body = String(decoding: try #require(transport.requests.last?.httpBody), as: UTF8.self)
    #expect(body.contains("Recipe: Shakshuka\\nServings: 4\\nIngredients:\\n- 6 large eggs"))
  }

  @Test(arguments: [nil, "bad-key"] as [String?])
  func aJobWaitsWithoutAKeyOrWithARefusedOne(key: String?) async throws {
    let recipe = recipe()
    AIJobQueue.enqueueMacros(for: recipe, in: context)
    let (ai, _, _) = service(key: key, [.status(403, "{}")])
    for _ in 0..<5 { await AIJobQueue.drain(in: context, using: ai.estimator) }
    let job = try #require(try jobs().first)
    #expect(job.status == .waiting && job.attempts == 0)
    #expect(recipe.macrosPending)
  }

  @Test func aSpentQuotaStopsTheDrainSoLaterJobsArentTried() async throws {
    AIJobQueue.enqueueMacros(for: recipe("One"), in: context)
    AIJobQueue.enqueueMacros(for: recipe("Two"), in: context)
    let (ai, transport, _) = service([.status(429, "{}"), .status(200, answer(macrosJSON))])
    #expect(await AIJobQueue.drain(in: context, using: ai.estimator) == 0)
    #expect(transport.requests.count == 1)
    #expect(try jobs().count == 2)
    #expect(ai.status == .rateLimited)
  }

  @Test func badAnswersUseUpAttemptsAndTheThirdGivesUp() async throws {
    let recipe = recipe()
    AIJobQueue.enqueueMacros(for: recipe, in: context)
    let bad = ScriptedTransport.Reply.status(200, answer(#"{"nope":1}"#))
    let (ai, _, _) = service([bad, bad, bad])
    await AIJobQueue.drain(in: context, using: ai.estimator)
    #expect(try jobs().first?.attempts == 1)
    #expect(try jobs().first?.status == .waiting)
    await AIJobQueue.drain(in: context, using: ai.estimator)
    await AIJobQueue.drain(in: context, using: ai.estimator)
    let job = try #require(try jobs().first)
    #expect(job.status == .failed && job.attempts == 3)
    #expect(!recipe.macrosPending)
    #expect(recipe.macros == .none)
    #expect(AIJobQueue.waitingCount(in: context) == 0)
  }

  @Test func oneRecipeIsOnlyQueuedOnce() throws {
    let recipe = recipe()
    AIJobQueue.enqueueMacros(for: recipe, in: context)
    AIJobQueue.enqueueMacros(for: recipe, in: context)
    #expect(try jobs().count == 1)
  }

  @Test func macrosTypedInWhileWaitingAreKept() async throws {
    let recipe = recipe()
    AIJobQueue.enqueueMacros(for: recipe, in: context)
    recipe.macros = Macros(calories: 500, protein: 1, carbs: 2, fat: 3)
    recipe.macrosSource = .manual
    let (ai, _, _) = service([.status(200, answer(macrosJSON))])
    await AIJobQueue.drain(in: context, using: ai.estimator)
    #expect(recipe.macros.calories == 500)
    #expect(recipe.macrosSource == .manual)
    #expect(!recipe.macrosPending)
    #expect(try jobs().isEmpty)
  }

  @Test func aJobForABanishedOrEmptyRecipeIsDroppedWithoutAsking() async throws {
    let gone = recipe("Gone")
    AIJobQueue.enqueueMacros(for: gone, in: context)
    gone.deletedAt = .now
    let empty = RecipeRecord(title: "Empty")
    context.insert(empty)
    AIJobQueue.enqueueMacros(for: empty, in: context)
    let (ai, transport, _) = service([])
    await AIJobQueue.drain(in: context, using: ai.estimator)
    #expect(transport.requests.isEmpty)
    #expect(try jobs().isEmpty)
    #expect(!gone.macrosPending && !empty.macrosPending)
  }

  private let mealJSON =
    #"{"items":[{"name":"Eggs","amount":"2 large","food":true,"calories":143,"protein":12.5,"carbs":1,"fat":9.5},{"name":"Toast","amount":"1 slice","food":true,"calories":100,"protein":4,"carbs":19,"fat":null},{"name":"A walk","amount":null,"food":false,"calories":null,"protein":null,"carbs":null,"fat":null}]}"#

  private func describedEntry(_ text: String = "eggs on toast") throws -> DiaryEntryRecord {
    let day = try #require(LocalDate("2026-10-12"))
    let entry = DiaryEntryRecord(day: day, slot: .breakfast, name: text, source: .described)
    context.insert(entry)
    AIJobQueue.enqueueMeal(text, for: entry, in: context)
    return entry
  }

  @Test func aDescribedMealGetsItsFoodsAddedUpAndKeepsTheCooksWords() async throws {
    let entry = try describedEntry()
    #expect(entry.macrosPending)
    let (ai, _, _) = service([.status(200, answer(mealJSON))])
    #expect(await AIJobQueue.drain(in: context, using: ai.estimator) == 1)

    // One entry, however many foods: a job never adds rows, so running it twice (here or on
    // another device) can't duplicate anything.
    let entries = try context.fetch(FetchDescriptor<DiaryEntryRecord>())
    #expect(entries.count == 1)
    #expect(entry.name == "eggs on toast")
    #expect(!entry.macrosPending)
    #expect(entry.macros == Macros(calories: 243, protein: 16.5, carbs: 20, fat: 9.5))
    #expect(try jobs().isEmpty)
  }

  @Test func aMealThatIsntFoodLeavesTheEntryAsWrittenAndStopsWaiting() async throws {
    let entry = try describedEntry("a long walk")
    let (ai, _, _) = service([.status(200, answer(#"{"items":[]}"#))])
    await AIJobQueue.drain(in: context, using: ai.estimator)
    #expect(entry.name == "a long walk")
    #expect(!entry.macrosPending && entry.macros == .none)
  }

  @Test func twoDrainsAtOnceAskOnceAndWriteOnce() async throws {
    let entry = try describedEntry()
    let keys = MemoryKeyStore("test-key")
    let transport = HeldTransport(answering: answer(mealJSON))
    let ai = CloudRecipeAI(provider: .gemini, keys: keys, transport: transport) { "gemini-test" }
    let context = context

    let first = Task { @MainActor in await AIJobQueue.drain(in: context, using: ai) }
    // Let the first drain reach the network, then start a second while it waits there.
    while transport.requestCount == 0 { await Task.yield() }
    let second = await AIJobQueue.drain(in: context, using: ai)
    #expect(second == 0)
    transport.release()
    // The second call asked for another pass, which finds nothing left to do.
    #expect(await first.value == 1)

    #expect(transport.requestCount == 1)
    #expect(try context.fetch(FetchDescriptor<DiaryEntryRecord>()).count == 1)
    #expect(entry.macros.calories == 243)
  }

  @Test func aRemovedEntryThatIsPutBackIsQueuedAgain() async throws {
    let entry = try describedEntry()
    // Removing the entry takes its job with it; putting it back restores only the entry.
    for job in try jobs() { context.delete(job) }
    try context.save()
    #expect(entry.macrosPending)
    #expect(try jobs().isEmpty)

    let (ai, transport, _) = service([.status(200, answer(mealJSON))])
    #expect(await AIJobQueue.drain(in: context, using: ai.estimator) == 1)
    #expect(!entry.macrosPending)
    #expect(entry.macros.calories == 243)
    let body = String(decoding: try #require(transport.requests.first?.httpBody), as: UTF8.self)
    #expect(body.contains("eggs on toast"))
  }

  @Test func aRecipeMarkedWaitingWithNoJobIsQueuedAgain() async throws {
    let recipe = recipe()
    recipe.macrosPending = true
    let (ai, _, _) = service([.status(200, answer(macrosJSON))])
    #expect(await AIJobQueue.drain(in: context, using: ai.estimator) == 1)
    #expect(!recipe.macrosPending)
    #expect(recipe.macros.calories == 310)
  }

  @Test func aJobWhoseRecipeHasntArrivedWaitsAWeekBeforeItIsDropped() async throws {
    // Over sync a job can arrive before the recipe it is for.
    let job = AIJobRecord(kind: .recipeMacros)
    context.insert(job)
    let (ai, transport, _) = service([])
    #expect(await AIJobQueue.drain(in: context, using: ai.estimator) == 0)
    #expect(try jobs().count == 1)
    #expect(try jobs().first?.status == .waiting)
    #expect(transport.requests.isEmpty)

    let later = job.createdAt.addingTimeInterval(AIJobQueue.orphanGrace + 60)
    await AIJobQueue.drain(in: context, using: ai.estimator, now: later)
    #expect(try jobs().isEmpty)
  }

  @Test func anUnknownModelMakesEverythingWaitAndSaysSo() async throws {
    let one = recipe("One")
    AIJobQueue.enqueueMacros(for: one, in: context)
    AIJobQueue.enqueueMacros(for: recipe("Two"), in: context)
    let notFound = ScriptedTransport.Reply.status(
      404, #"{"error":{"code":404,"status":"NOT_FOUND"}}"#)
    let (ai, transport, _) = service([notFound, notFound, notFound])
    for _ in 0..<3 { await AIJobQueue.drain(in: context, using: ai.estimator) }
    // A mistyped model name costs no attempts and fails nothing.
    #expect(try jobs().count == 2)
    #expect(try jobs().allSatisfy { $0.status == .waiting && $0.attempts == 0 })
    #expect(one.macrosPending)
    #expect(transport.requests.count == 3)
    #expect(ai.status == .invalidModel)
  }
}

@MainActor
@Suite("AI settings")
struct AISettingsTests {
  @Test func everyStatusHasItsOwnLine() {
    let statuses: [RecipeAIStatus] = [
      .ready, .missingKey, .invalidKey, .rateLimited, .noCredit, .invalidModel,
    ]
    #expect(Set(statuses.map { $0.message(for: .gemini).text }).count == 6)
    #expect(statuses.allSatisfy { $0.message(for: .gemini).tone == .plain })
    #expect(
      statuses.filter(\.needsAttention) == [
        .missingKey, .invalidKey, .rateLimited, .noCredit, .invalidModel,
      ])
    #expect(Copy.settings.ai.waiting(1).text == "1 estimate is waiting.")
    #expect(Copy.settings.ai.waiting(3).text == "3 estimates are waiting.")
  }

  @Test func theSectionRendersWithAndWithoutAKeyInBothAppearances() throws {
    let container = try CauldronStore.container(.inMemory)
    for key in [nil, "abc"] as [String?] {
      for scheme in [ColorScheme.light, .dark] {
        let view = Form { AIQuotaSection() }
          .environment(RecipeAIService.offline(key: key))
          .modelContainer(container)
          .environment(\.colorScheme, scheme)
          .frame(width: 390, height: 700)
        #expect(ImageRenderer(content: view).cgImage != nil)
      }
    }
  }
}
