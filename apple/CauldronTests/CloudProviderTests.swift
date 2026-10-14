import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

// Response bodies here are written by hand from each provider's documented shapes, not
// recorded from the live APIs.

private let recipeJSON =
  #"{"recipe":"found","title":"Fried eggs","description":null,"servings":1,"prepMinutes":null,"cookMinutes":3,"totalMinutes":null,"ingredients":[{"line":"2 eggs","section":null,"unsure":false}],"steps":[{"text":"Fry them.","section":null,"unsure":false}],"tags":[],"notes":null,"unsure":[]}"#

/// A successful response from `provider` whose answer is `json`.
private func reply(_ provider: AIProvider, _ json: String) -> ScriptedTransport.Reply {
  let body: [String: Any]
  switch provider {
  case .gemini:
    return .status(200, answer(json))
  case .openai:
    body = [
      "status": "completed",
      "output": [
        ["type": "reasoning", "summary": []],
        ["type": "message", "content": [["type": "output_text", "text": json]]],
      ],
      "usage": ["input_tokens": 10, "output_tokens": 5],
    ]
  case .anthropic:
    body = [
      "content": [["type": "text", "text": json]],
      "stop_reason": "end_turn",
      "usage": ["input_tokens": 10, "output_tokens": 5],
    ]
  }
  let data = try! JSONSerialization.data(withJSONObject: body)
  return .status(200, String(decoding: data, as: UTF8.self))
}

/// Chooses between providers: each has a key store, a scripted transport and a model.
@MainActor
private final class Rig {
  let ai: RecipeAIService
  let keys: [AIProvider: MemoryKeyStore]
  let transports: [AIProvider: ScriptedTransport]
  let defaults: UserDefaults
  /// The settings domain this rig made for itself, removed with it.
  private let ownedDomain: String?

  init(
    keys keyValues: [AIProvider: String] = [:],
    replies: [AIProvider: [ScriptedTransport.Reply]] = [:],
    onDevice: Bool = false,
    defaults: UserDefaults? = nil
  ) throws {
    let suite = "AIProviderTests.\(UUID().uuidString)"
    ownedDomain = defaults == nil ? suite : nil
    let defaults = try defaults ?? #require(UserDefaults(suiteName: suite))
    var keys: [AIProvider: MemoryKeyStore] = [:]
    var transports: [AIProvider: ScriptedTransport] = [:]
    for provider in AIProvider.allCases {
      keys[provider] = MemoryKeyStore(keyValues[provider])
      transports[provider] = ScriptedTransport(replies[provider] ?? [])
    }
    let stores = keys
    let scripted = transports
    ai = RecipeAIService(
      defaults: defaults,
      keys: { stores[$0] ?? MemoryKeyStore() },
      makeClient: { provider, keys in
        CloudRecipeAI(
          provider: provider, keys: keys, transport: scripted[provider] ?? NoTransport()
        ) { "\(provider.rawValue)-test" }
      },
      onDevice: onDevice ? DeviceStub() : nil)
    self.keys = keys
    self.transports = transports
    self.defaults = defaults
  }

  deinit {
    if let domain = ownedDomain {
      UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
    }
  }
}

private struct DeviceStub: RecipeAI {
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
@Suite("AI provider choice")
struct AIProviderChoiceTests {
  private let input = ExtractInput(text: "2 eggs. Fry them.", kind: .text)

  @Test func theServiceStartsOnGeminiAndRemembersTheChoice() throws {
    let rig = try Rig(keys: [.gemini: "g"])
    #expect(rig.ai.provider == .gemini)
    #expect(rig.defaults.string(forKey: "ai.provider") == nil)
    rig.ai.select(.anthropic)
    #expect(rig.ai.provider == .anthropic)
    #expect(rig.defaults.string(forKey: "ai.provider") == "anthropic")
    // A service made later on the same settings starts where this one left off.
    let again = try Rig(defaults: rig.defaults)
    #expect(again.ai.provider == .anthropic)
    // Something unrecognised is Gemini.
    rig.defaults.set("palm", forKey: "ai.provider")
    #expect(RecipeAIService.chosenProvider(rig.defaults) == .gemini)
  }

  @Test func switchingReadsThatProvidersKeyAndResetsTheStatus() async throws {
    let rig = try Rig(keys: [.gemini: "g", .openai: "o"], replies: [.gemini: [.status(429, "{}")]])
    await #expect(throws: RecipeAIError.rateLimited) { try await rig.ai.extract(input) }
    #expect(rig.ai.status == .rateLimited)

    rig.ai.select(.openai)
    #expect(rig.ai.hasKey && rig.ai.status == .ready)
    rig.ai.select(.anthropic)
    #expect(!rig.ai.hasKey && rig.ai.status == .missingKey)
    rig.ai.select(.gemini)
    // Gemini's spent quota was Gemini's: coming back to it starts clean, as a new key does.
    #expect(rig.ai.hasKey && rig.ai.status == .ready)
  }

  @Test func keysAreKeptSeparately() throws {
    let rig = try Rig(keys: [.gemini: "g"])
    rig.ai.select(.openai)
    #expect(rig.ai.saveKey("  o-key \n"))
    rig.ai.select(.anthropic)
    #expect(rig.ai.saveKey("a-key"))
    #expect(rig.keys[.gemini]?.key() == "g")
    #expect(rig.keys[.openai]?.key() == "o-key")
    #expect(rig.keys[.anthropic]?.key() == "a-key")

    // Removing one provider's key leaves the others.
    #expect(rig.ai.removeKey())
    #expect(!rig.ai.hasKey && rig.ai.status == .missingKey)
    #expect(rig.keys[.anthropic]?.key() == nil)
    #expect(rig.keys[.openai]?.key() == "o-key" && rig.keys[.gemini]?.key() == "g")
    rig.ai.select(.openai)
    #expect(rig.ai.hasKey && rig.ai.status == .ready)
  }

  @Test func aKeyFromAnotherDeviceIsNoticedForTheChosenProvider() throws {
    let rig = try Rig()
    rig.ai.select(.openai)
    #expect(!rig.ai.hasKey)
    // Another provider's key arriving doesn't count.
    #expect(throws: Never.self) { try rig.keys[.gemini]?.setKey("g") }
    rig.ai.refreshKey()
    #expect(!rig.ai.hasKey && rig.ai.status == .missingKey)
    #expect(throws: Never.self) { try rig.keys[.openai]?.setKey("o") }
    rig.ai.refreshKey()
    #expect(rig.ai.hasKey && rig.ai.status == .ready)
  }

  @Test func aSaveTheKeychainRefusedIsForgottenOnSwitching() throws {
    let refusing = MemoryKeyStore(nil, failsToSave: true)
    let ai = RecipeAIService(
      defaults: try #require(UserDefaults(suiteName: "AIProviderTests.\(UUID().uuidString)")),
      keys: { $0 == .gemini ? refusing : MemoryKeyStore() },
      makeClient: { _, _ in DeviceStub() }, onDevice: nil)
    #expect(!ai.saveKey("abc") && ai.keyNotSaved)
    ai.select(.openai)
    #expect(!ai.keyNotSaved)
  }

  @Test func theModelIsPerProviderAndGeminisSettingCarriesOver() throws {
    let defaults = try #require(
      UserDefaults(suiteName: "AIProviderTests.model.\(UUID().uuidString)"))
    // What Chris set before there were other providers.
    defaults.set(" gemini-3.5-pro ", forKey: "ai.geminiModel")
    #expect(RecipeAIService.modelDefaultsKey(for: .gemini) == "ai.geminiModel")
    #expect(RecipeAIService.chosenModel(for: .gemini, defaults) == "gemini-3.5-pro")
    #expect(RecipeAIService.chosenModel(for: .openai, defaults) == "gpt-6-luna")
    #expect(RecipeAIService.chosenModel(for: .anthropic, defaults) == "claude-haiku-5-5")

    #expect(RecipeAIService.modelDefaultsKey(for: .openai) == "ai.model.openai")
    #expect(RecipeAIService.modelDefaultsKey(for: .anthropic) == "ai.model.anthropic")
    defaults.set("gpt-6-sol", forKey: "ai.model.openai")
    defaults.set("  ", forKey: "ai.model.anthropic")
    #expect(RecipeAIService.chosenModel(for: .openai, defaults) == "gpt-6-sol")
    #expect(RecipeAIService.chosenModel(for: .anthropic, defaults) == "claude-haiku-5-5")
    #expect(RecipeAIService.chosenModel(for: .gemini, defaults) == "gemini-3.5-pro")
  }

  @Test func geminisExistingKeychainItemIsStillTheOneRead() {
    #expect(KeychainKeyStore.service(for: .gemini) == "computer.srcery.cauldron.gemini")
    #expect(KeychainKeyStore.account == "api-key")
    // The others have items of their own.
    #expect(KeychainKeyStore.service(for: .openai) == "computer.srcery.cauldron.openai")
    #expect(KeychainKeyStore.service(for: .anthropic) == "computer.srcery.cauldron.anthropic")
  }

  @Test func theLaunchAndPreviewServicesHaveNoNetworkAndNoKeys() async {
    for ai in [RecipeAIService.forLaunch(mode: .inMemory), .offline()] {
      #expect(ai.provider == .gemini && !ai.hasKey && ai.status == .missingKey)
      await #expect(throws: RecipeAIError.missingKey) { try await ai.extract(input) }
    }
    let keyed = RecipeAIService.offline(key: "abc")
    #expect(keyed.hasKey)
    await #expect(throws: RecipeAIError.unreachable) { try await keyed.estimator.estimateMeal("x") }
    keyed.select(.openai)
    #expect(!keyed.hasKey)
  }

  @Test func aCallThatStartedOnAnotherProviderDoesntMoveTheStatus() async throws {
    let rig = try Rig(
      keys: [.gemini: "g", .openai: "o"], replies: [.gemini: [.status(403, "{}")]])
    let old = rig.ai.estimator
    rig.ai.select(.openai)
    await #expect(throws: RecipeAIError.invalidKey) {
      try await old.estimateMacros(
        MacroEstimateInput(title: nil, servings: nil, ingredients: ["x"]))
    }
    #expect(rig.ai.status == .ready)
    rig.ai.select(.gemini)
    #expect(rig.ai.status == .ready)
  }

  @Test func switchingProviderRunsTheQueue() async throws {
    let container = try CauldronStore.container(.inMemory)
    let context = container.mainContext
    let recipe = RecipeRecord(title: "Shakshuka")
    recipe.servings = 4
    recipe.ingredients = [
      Ingredient(
        section: nil, quantity: nil, unit: nil, item: "eggs", note: nil, optional: false,
        alt: nil, original: "6 large eggs", itemKey: "egg")
    ]
    context.insert(recipe)
    AIJobQueue.enqueueMacros(for: recipe, in: context)

    // Gemini has no key, so the estimate waits; OpenAI has one and can answer.
    let rig = try Rig(
      keys: [.openai: "o"],
      replies: [
        .openai: [
          reply(.openai, #"{"servings":4,"calories":310,"protein":17,"carbs":18,"fat":19}"#)
        ]
      ])
    #expect(await AIJobQueue.drain(in: context, using: rig.ai.estimator) == 0)
    #expect(recipe.macrosPending)

    let drained = AIQueueRunner.switchProvider(to: .openai, in: context, ai: rig.ai)
    // The switch itself is immediate.
    #expect(rig.ai.provider == .openai)
    #expect(await drained.value == 1)
    #expect(!recipe.macrosPending)
    #expect(recipe.macros == Macros(calories: 310, protein: 17, carbs: 18, fat: 19))
    #expect(rig.transports[.openai]?.requests.count == 1)
    #expect(rig.transports[.gemini]?.requests.isEmpty == true)
  }

  private func message(_ status: RecipeAIStatus, _ provider: AIProvider) -> String {
    status.message(for: provider).text
  }

  @Test func theStatusLinesNameTheChosenProvider() {
    let statuses: [RecipeAIStatus] = [
      .ready, .missingKey, .invalidKey, .rateLimited, .invalidModel,
    ]
    for provider in AIProvider.allCases {
      for status in statuses {
        #expect(message(status, provider).contains(provider.displayName), "\(provider) \(status)")
        #expect(status.message(for: provider).tone == .plain)
      }
    }
    #expect(message(.ready, .gemini) == "Gemini is set up.")
    #expect(message(.invalidKey, .anthropic).hasPrefix("Claude didn't accept that key."))
    #expect(!message(.missingKey, .openai).contains("Gemini"))
  }
}

@MainActor
@Suite("Cloud clients")
struct CloudClientTests {
  private let input = ExtractInput(text: "2 eggs. Fry them.", kind: .text)

  /// The header that carries each provider's key, and the value it carries.
  private func keyHeader(_ provider: AIProvider, _ request: URLRequest, key: String) -> Bool {
    switch provider {
    case .gemini: request.value(forHTTPHeaderField: "x-goog-api-key") == key
    case .openai: request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)"
    case .anthropic: request.value(forHTTPHeaderField: "x-api-key") == key
    }
  }

  @Test(arguments: AIProvider.allCases)
  func aRequestGoesToTheProviderWithTheKeyInItsHeaderOnly(provider: AIProvider) async throws {
    let rig = try Rig(
      keys: [provider: "secret-key"], replies: [provider: [reply(provider, recipeJSON)]])
    rig.ai.select(provider)
    let extraction = try await rig.ai.extract(input)
    #expect(extraction.recipe.title == "Fried eggs")
    #expect(!extraction.rough)
    #expect(
      extraction.usage
        == AIUsage(model: "\(provider.rawValue)-test", inputTokens: 10, outputTokens: 5))

    let request = try #require(rig.transports[provider]?.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(keyHeader(provider, request, key: "secret-key"))
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let url = try #require(request.url?.absoluteString)
    #expect(url.hasPrefix("https://"))
    #expect(!url.contains("secret-key"))
    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
    #expect(body.contains("2 eggs. Fry them."))
    #expect(!body.contains("secret-key"))
    // Only the chosen provider was asked.
    for other in AIProvider.allCases where other != provider {
      #expect(rig.transports[other]?.requests.isEmpty == true)
    }
  }

  @Test func eachProviderGoesToItsOwnHostAndModel() async throws {
    let hosts: [AIProvider: String] = [
      .gemini: "generativelanguage.googleapis.com", .openai: "api.openai.com",
      .anthropic: "api.anthropic.com",
    ]
    for provider in AIProvider.allCases {
      let rig = try Rig(keys: [provider: "k"], replies: [provider: [reply(provider, recipeJSON)]])
      rig.ai.select(provider)
      _ = try await rig.ai.extract(input)
      let request = try #require(rig.transports[provider]?.requests.first)
      #expect(request.url?.host == hosts[provider], "\(provider)")
      #expect(
        String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains(
          "\(provider.rawValue)-test")
          || request.url?.absoluteString.contains("\(provider.rawValue)-test") == true)
    }
  }

  @Test(arguments: AIProvider.allCases)
  func withoutAKeyNothingIsSent(provider: AIProvider) async throws {
    let rig = try Rig(replies: [provider: [reply(provider, recipeJSON)]])
    rig.ai.select(provider)
    #expect(rig.ai.status == .missingKey)
    await #expect(throws: RecipeAIError.missingKey) { try await rig.ai.extract(input) }
    #expect(rig.transports[provider]?.requests.isEmpty == true)
  }

  @Test(arguments: AIProvider.allCases)
  func offlineTheDeviceReadsTheRecipeAndItIsMarkedRough(provider: AIProvider) async throws {
    let rig = try Rig(keys: [provider: "k"], replies: [provider: [.offline]], onDevice: true)
    rig.ai.select(provider)
    let extraction = try await rig.ai.extract(input)
    #expect(extraction.recipe.title == "From the device")
    #expect(extraction.rough)
    // Being offline says nothing lasting about the key.
    #expect(rig.ai.status == .ready)
  }

  @Test(arguments: AIProvider.allCases)
  func aSpentQuotaAServerErrorARefusedKeyAndAnUnknownModelAllFallBack(
    provider: AIProvider
  ) async throws {
    let cases: [(Int, RecipeAIStatus?)] = [
      (429, .rateLimited), (503, nil), (403, .invalidKey), (404, .invalidModel),
    ]
    for (status, lasting) in cases {
      let rig = try Rig(
        keys: [provider: "k"], replies: [provider: [.status(status, "{}")]], onDevice: true)
      rig.ai.select(provider)
      let extraction = try await rig.ai.extract(input)
      #expect(extraction.rough, "\(provider) \(status)")
      #expect(rig.ai.status == (lasting ?? .ready), "\(provider) \(status)")
    }
  }

  @Test(arguments: AIProvider.allCases)
  func aBadAnswerIsAFailureWithNoFallback(provider: AIProvider) async throws {
    let rig = try Rig(
      keys: [provider: "k"], replies: [provider: [reply(provider, #"{"nope":1}"#)]], onDevice: true)
    rig.ai.select(provider)
    await #expect(throws: RecipeAIError.failed(detail: "bad output")) {
      try await rig.ai.extract(input)
    }
    #expect(rig.ai.status == .ready)
  }

  @Test(arguments: AIProvider.allCases)
  func macrosAndMealsAreReadThroughTheSameClient(provider: AIProvider) async throws {
    let macros = #"{"servings":4,"calories":310,"protein":17,"carbs":18,"fat":19}"#
    let meal =
      #"{"items":[{"name":"Eggs","amount":"2 large","food":true,"calories":143,"protein":12.5,"carbs":1,"fat":9.5}]}"#
    let rig = try Rig(
      keys: [provider: "k"],
      replies: [provider: [reply(provider, macros), reply(provider, meal)]])
    rig.ai.select(provider)
    let estimator = rig.ai.estimator
    #expect(
      try await estimator.estimateMacros(
        MacroEstimateInput(title: nil, servings: 4, ingredients: ["x"]))
        == Macros(calories: 310, protein: 17, carbs: 18, fat: 19))
    #expect(try await estimator.estimateMeal("eggs").map(\.name) == ["Eggs"])
  }

  @Test(arguments: AIProvider.allCases)
  func anEmptyModelNameMakesTheProviderWaitAsAnUnknownModel(provider: AIProvider) async throws {
    let keys = MemoryKeyStore("k")
    let transport = ScriptedTransport([])
    let client = CloudRecipeAI(provider: provider, keys: keys, transport: transport) { "" }
    await #expect(throws: RecipeAIError.invalidModel) { try await client.extract(input) }
    #expect(transport.requests.isEmpty)
  }
}

@MainActor
@Suite("AI settings by provider")
struct AIProviderSettingsTests {
  @Test func theSectionRendersForEachProviderWithAndWithoutAKeyInBothAppearances() throws {
    let container = try CauldronStore.container(.inMemory)
    for provider in AIProvider.allCases {
      for key in [nil, "abc"] as [String?] {
        let rig = try Rig(keys: key.map { [provider: $0] } ?? [:])
        rig.ai.select(provider)
        #expect(rig.ai.hasKey == (key != nil))
        for scheme in [ColorScheme.light, .dark] {
          let view = Form { AIQuotaSection() }
            .environment(rig.ai)
            .modelContainer(container)
            .environment(\.colorScheme, scheme)
            .frame(width: 390, height: 800)
          #expect(ImageRenderer(content: view).cgImage != nil, "\(provider) \(scheme)")
        }
      }
    }
  }

  @Test func theStatusLineRendersForEveryProviderAndStatus() throws {
    let statuses: [RecipeAIStatus] = [
      .ready, .missingKey, .invalidKey, .rateLimited, .invalidModel,
    ]
    for provider in AIProvider.allCases {
      let rig = try Rig()
      rig.ai.select(provider)
      for status in statuses {
        let view = AIStatusLine(status: status).environment(rig.ai).frame(width: 390, height: 120)
        #expect(ImageRenderer(content: view).cgImage != nil)
      }
    }
  }

  @Test func theHintAndPlaceholdersFollowTheProvider() {
    for provider in AIProvider.allCases {
      #expect(Copy.settings.ai.hint(provider).text.contains(provider.displayName))
      #expect(Copy.settings.ai.keyLabel(provider).text.contains(provider.displayName))
    }
    #expect(Copy.settings.ai.hint(.gemini).text.contains("Google's Gemini"))
    #expect(Copy.settings.ai.hint(.anthropic).text.contains("Anthropic's Claude"))
    #expect(Copy.settings.ai.providerLabel.tone == .plain)
  }
}
