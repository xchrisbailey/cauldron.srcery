import CauldronKit
import Foundation
import Observation

/// The app's one door to the AI: it holds the key, knows whether Gemini is usable, and applies
/// the fallback rule. Views read `status` for the line that stays in Settings and beside AI
/// actions.
@MainActor
@Observable
final class RecipeAIService {
  /// The `UserDefaults` key for the model name. Empty means the default.
  nonisolated static let modelDefaultsKey = "ai.geminiModel"

  private(set) var status: RecipeAIStatus
  private(set) var hasKey: Bool
  /// True after a save the keychain refused, until one works.
  private(set) var keyNotSaved = false

  @ObservationIgnored private let keys: any AIKeyStore
  @ObservationIgnored private let gemini: any RecipeAI
  @ObservationIgnored private let onDevice: (any RecipeAI)?

  init(keys: any AIKeyStore, gemini: any RecipeAI, onDevice: (any RecipeAI)?) {
    self.keys = keys
    self.gemini = gemini
    self.onDevice = onDevice
    let hasKey = keys.key() != nil
    self.hasKey = hasKey
    status = hasKey ? .ready : .missingKey
  }

  /// The model named in Settings, or the default.
  nonisolated static func chosenModel(_ defaults: UserDefaults = .standard) -> String {
    let chosen = defaults.string(forKey: modelDefaultsKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return chosen.flatMap { $0.isEmpty ? nil : $0 } ?? Gemini.defaultModel
  }

  /// Gemini over the network with the keychain's key, and the on-device model where there is
  /// one.
  static func live() -> RecipeAIService {
    let keys = KeychainKeyStore()
    return RecipeAIService(
      keys: keys,
      gemini: GeminiRecipeAI(keys: keys, transport: URLSessionTransport()) { chosenModel() },
      onDevice: OnDeviceRecipeAI.make())
  }

  /// What the app starts with. Under test it has no key and no network, so a test run never
  /// reads the keychain or calls Gemini.
  static func forLaunch(mode: CauldronStore.Mode) -> RecipeAIService {
    mode == .inMemory ? .offline() : .live()
  }

  /// No key, no network and no on-device model, for tests and previews.
  static func offline(key: String? = nil) -> RecipeAIService {
    let keys = MemoryKeyStore(key)
    return RecipeAIService(
      keys: keys,
      gemini: GeminiRecipeAI(keys: keys, transport: NoTransport()) { Gemini.defaultModel },
      onDevice: nil)
  }

  // MARK: The key

  /// Saves the key, or removes it when blank. Returns whether the keychain took it.
  @discardableResult
  func saveKey(_ key: String) -> Bool {
    do {
      try keys.setKey(key)
    } catch {
      keyNotSaved = true
      return false
    }
    keyNotSaved = false
    hasKey = keys.key() != nil
    // A new key is taken on trust until Gemini says otherwise.
    status = hasKey ? .ready : .missingKey
    return true
  }

  @discardableResult
  func removeKey() -> Bool {
    saveKey("")
  }

  // MARK: Asking

  /// Reads a recipe out of text: Gemini first, the on-device model when Gemini can't be
  /// reached, with that result marked rough.
  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    try await FallbackExtractor(primary: Watched(base: gemini, service: self), onDevice: onDevice)
      .extract(input)
  }

  /// Gemini alone, for the queue. Macro estimates never fall back.
  var estimator: any RecipeAI {
    Watched(base: gemini, service: self)
  }

  fileprivate func succeeded() {
    status = .ready
  }

  fileprivate func failed(_ error: RecipeAIError) {
    if let lasting = RecipeAIStatus(after: error) { status = lasting }
  }
}

/// Passes calls through and tells the service how each went, so its status follows Gemini.
private struct Watched: RecipeAI {
  let base: any RecipeAI
  let service: RecipeAIService

  private func watch<T: Sendable>(
    _ call: () async throws(RecipeAIError) -> T
  ) async throws(RecipeAIError) -> T {
    do {
      let value = try await call()
      await service.succeeded()
      return value
    } catch {
      await service.failed(error)
      throw error
    }
  }

  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    try await watch { () async throws(RecipeAIError) in try await base.extract(input) }
  }

  func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros {
    try await watch { () async throws(RecipeAIError) in try await base.estimateMacros(input) }
  }

  func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem] {
    try await watch { () async throws(RecipeAIError) in try await base.estimateMeal(text) }
  }
}
