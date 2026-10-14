import CauldronKit
import Foundation
import Observation

/// The app's one door to the AI: it holds the chosen provider and that provider's key, knows
/// whether the AI is usable, and applies the fallback rule. Views read `status` for the line
/// that stays in Settings and beside AI actions. Nothing outside this file and Settings needs
/// to know which provider is in use.
@MainActor
@Observable
final class RecipeAIService {
  /// The `UserDefaults` key for the chosen provider. Absent means Gemini.
  nonisolated static let providerDefaultsKey = "ai.provider"

  /// The `UserDefaults` key for a provider's model name. Empty means the default. Gemini's is
  /// the key the app used before there were other providers, so a model set then still holds.
  nonisolated static func modelDefaultsKey(for provider: AIProvider) -> String {
    provider == .gemini ? "ai.geminiModel" : "ai.model.\(provider.rawValue)"
  }

  /// The provider the cook chose, or Gemini.
  nonisolated static func chosenProvider(_ defaults: UserDefaults = .standard) -> AIProvider {
    defaults.string(forKey: providerDefaultsKey).flatMap(AIProvider.init(rawValue:)) ?? .gemini
  }

  /// The model named in Settings for `provider`, or its default.
  nonisolated static func chosenModel(
    for provider: AIProvider, _ defaults: UserDefaults = .standard
  ) -> String {
    let chosen = defaults.string(forKey: modelDefaultsKey(for: provider))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return chosen.flatMap { $0.isEmpty ? nil : $0 } ?? provider.defaultModel
  }

  /// The provider in use. Change it with `select(_:)`.
  private(set) var provider: AIProvider
  private(set) var status: RecipeAIStatus
  /// Whether the chosen provider has a key.
  private(set) var hasKey: Bool
  /// True after a save the keychain refused, until one works.
  private(set) var keyNotSaved = false
  /// Why the last call to the chosen provider failed, when it answered with something unusable.
  /// It never holds the key or the provider's message, only a short reason such as
  /// "rejected: invalid_request_error". Shown in debug builds, to tell a bug from a bad answer.
  private(set) var lastFailure: String?

  @ObservationIgnored private let defaults: UserDefaults
  /// Set when `defaults` is a throwaway domain for a test or preview, to be removed with it.
  @ObservationIgnored private let throwawayDomain: String?
  @ObservationIgnored private let keys: [AIProvider: any AIKeyStore]
  @ObservationIgnored private let clients: [AIProvider: any RecipeAI]
  @ObservationIgnored private let onDevice: (any RecipeAI)?

  /// `keys` gives each provider's key store and `makeClient` its cloud client, which is handed
  /// that store.
  init(
    defaults: UserDefaults = .standard, throwawayDomain: String? = nil,
    keys: (AIProvider) -> any AIKeyStore,
    makeClient: (AIProvider, any AIKeyStore) -> any RecipeAI,
    onDevice: (any RecipeAI)?
  ) {
    self.defaults = defaults
    self.throwawayDomain = throwawayDomain
    var stores: [AIProvider: any AIKeyStore] = [:]
    var clients: [AIProvider: any RecipeAI] = [:]
    for provider in AIProvider.allCases {
      let store = keys(provider)
      stores[provider] = store
      clients[provider] = makeClient(provider, store)
    }
    self.keys = stores
    self.clients = clients
    self.onDevice = onDevice
    let provider = Self.chosenProvider(defaults)
    self.provider = provider
    let hasKey = stores[provider]?.key() != nil
    self.hasKey = hasKey
    status = hasKey ? .ready : .missingKey
  }

  /// One key store and one client for every provider, on settings that vanish with the
  /// service. For tests of what happens on a single provider.
  convenience init(keys: any AIKeyStore, client: any RecipeAI, onDevice: (any RecipeAI)?) {
    let domain = "computer.srcery.cauldron.throwaway.\(UUID().uuidString)"
    self.init(
      defaults: UserDefaults(suiteName: domain) ?? .standard, throwawayDomain: domain,
      keys: { _ in keys }, makeClient: { _, _ in client }, onDevice: onDevice)
  }

  deinit {
    if let domain = throwawayDomain {
      UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
    }
  }

  /// Each provider over the network with its own key from the keychain, and the on-device
  /// model where there is one.
  static func live() -> RecipeAIService {
    RecipeAIService(
      keys: { KeychainKeyStore(provider: $0) },
      makeClient: { provider, keys in
        CloudRecipeAI(provider: provider, keys: keys, transport: URLSessionTransport()) {
          chosenModel(for: provider)
        }
      },
      onDevice: OnDeviceRecipeAI.make())
  }

  /// What the app starts with. Under test it has no key and no network, so a test run never
  /// reads the keychain or calls a provider.
  static func forLaunch(mode: CauldronStore.Mode) -> RecipeAIService {
    mode == .inMemory ? .offline() : .live()
  }

  /// No key, no network and no on-device model, for tests and previews. `key` is Gemini's, the
  /// provider it starts on; the others have none. Its settings are its own, so a provider
  /// chosen on it is not remembered.
  static func offline(key: String? = nil) -> RecipeAIService {
    let domain = "computer.srcery.cauldron.throwaway.\(UUID().uuidString)"
    return RecipeAIService(
      defaults: UserDefaults(suiteName: domain) ?? .standard, throwawayDomain: domain,
      keys: { MemoryKeyStore($0 == .gemini ? key : nil) },
      makeClient: { provider, keys in
        CloudRecipeAI(provider: provider, keys: keys, transport: NoTransport()) {
          provider.defaultModel
        }
      },
      onDevice: nil)
  }

  // MARK: The provider

  /// Switches to `provider`: reads its key and clears whatever the last provider left in the
  /// status, as saving a key does. The caller runs the queue, since waiting estimates may be
  /// able to run now.
  func select(_ provider: AIProvider) {
    guard provider != self.provider else { return }
    self.provider = provider
    defaults.set(provider.rawValue, forKey: Self.providerDefaultsKey)
    keyNotSaved = false
    hasKey = key.key() != nil
    status = hasKey ? .ready : .missingKey
  }

  private var key: any AIKeyStore {
    // Every provider has a store; this only keeps the lookup total.
    keys[provider] ?? MemoryKeyStore()
  }

  // MARK: The key

  /// Saves the chosen provider's key, or removes it when blank. Returns whether the keychain
  /// took it.
  @discardableResult
  func saveKey(_ key: String) -> Bool {
    do {
      try self.key.setKey(key)
    } catch {
      keyNotSaved = true
      return false
    }
    keyNotSaved = false
    hasKey = self.key.key() != nil
    // A new key is taken on trust until the provider says otherwise.
    status = hasKey ? .ready : .missingKey
    return true
  }

  @discardableResult
  func removeKey() -> Bool {
    saveKey("")
  }

  /// Looks at the keychain again. A key saved on another device arrives through iCloud
  /// Keychain without this device being told.
  func refreshKey() {
    let found = key.key() != nil
    guard found != hasKey else { return }
    hasKey = found
    if !found {
      status = .missingKey
    } else if status == .missingKey {
      status = .ready
    }
  }

  // MARK: Asking

  /// Reads a recipe out of text: the chosen provider first, the on-device model when it can't
  /// be reached, with that result marked rough.
  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    try await extractor.extract(input)
  }

  /// `extract(_:)` as a value the import pipeline can take: the same fallback rule, and the
  /// same effect on `status`.
  var extractor: any RecipeExtracting {
    FallbackExtractor(primary: watched, onDevice: onDevice)
  }

  /// The chosen provider alone, for the queue. Macro estimates never fall back.
  var estimator: any RecipeAI { watched }

  private var watched: Watched {
    Watched(base: clients[provider] ?? NoRecipeAI(), provider: provider, service: self)
  }

  // A call that was started under another provider says nothing about this one.
  fileprivate func succeeded(_ provider: AIProvider) {
    guard provider == self.provider else { return }
    status = .ready
    hasKey = true
    lastFailure = nil
  }

  fileprivate func failed(_ error: RecipeAIError, _ provider: AIProvider) {
    guard provider == self.provider else { return }
    if let lasting = RecipeAIStatus(after: error) { status = lasting }
    if case .failed(let detail) = error { lastFailure = detail }
  }
}

/// Passes calls through and tells the service how each went, so its status follows the
/// provider.
private struct Watched: RecipeAI {
  let base: any RecipeAI
  let provider: AIProvider
  let service: RecipeAIService

  private func watch<T: Sendable>(
    _ call: () async throws(RecipeAIError) -> T
  ) async throws(RecipeAIError) -> T {
    do {
      let value = try await call()
      await service.succeeded(provider)
      return value
    } catch {
      await service.failed(error, provider)
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

/// Stands in where a provider has no client, which can't happen: every provider gets one.
private struct NoRecipeAI: RecipeAI {
  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    throw .unreachable
  }

  func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros {
    throw .unreachable
  }

  func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem] {
    throw .unreachable
  }
}
