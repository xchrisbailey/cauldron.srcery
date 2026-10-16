import CauldronKit
import Foundation
import Observation

/// The app's one door to the AI: it holds the chosen provider and that provider's key, knows
/// whether the AI is usable, and applies the fallback rule. Views read `status` for the line
/// that stays in Settings and beside AI actions. Nothing outside this file and Settings needs
/// to know which provider is in use.
@MainActor
@Observable
public final class RecipeAIService {
  /// The `UserDefaults` key for the chosen provider. Absent means Gemini.
  public nonisolated static let providerDefaultsKey = "ai.provider"

  /// The `UserDefaults` key for a provider's model name. Empty means the default. Gemini's is
  /// the key the app used before there were other providers, so a model set then still holds.
  public nonisolated static func modelDefaultsKey(for provider: AIProvider) -> String {
    provider == .gemini ? "ai.geminiModel" : "ai.model.\(provider.rawValue)"
  }

  /// The provider the cook chose, or Gemini.
  public nonisolated static func chosenProvider(_ defaults: UserDefaults = .standard) -> AIProvider
  {
    defaults.string(forKey: providerDefaultsKey).flatMap(AIProvider.init(rawValue:)) ?? .gemini
  }

  /// The model named in Settings for `provider`, or its default.
  public nonisolated static func chosenModel(
    for provider: AIProvider, _ defaults: UserDefaults = .standard
  ) -> String {
    let chosen = defaults.string(forKey: modelDefaultsKey(for: provider))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return chosen.flatMap { $0.isEmpty ? nil : $0 } ?? provider.defaultModel
  }

  /// The provider in use. Change it with `select(_:)`.
  public private(set) var provider: AIProvider
  public private(set) var status: RecipeAIStatus
  /// Whether the chosen provider has a key.
  public private(set) var hasKey: Bool
  /// True after a save the keychain refused, until one works.
  public private(set) var keyNotSaved = false
  /// Why the last call to the chosen provider failed, when it answered with something unusable.
  /// It never holds the key or the provider's message, only a short reason such as
  /// "rejected: invalid_request_error". Shown in debug builds, to tell a bug from a bad answer.
  public private(set) var lastFailure: String?

  @ObservationIgnored private let defaults: UserDefaults
  /// Set when `defaults` is a throwaway domain for a test or preview, to be removed with it.
  @ObservationIgnored private let throwawayDomain: String?
  @ObservationIgnored private let keys: [AIProvider: any AIKeyStore]
  @ObservationIgnored private let clients: [AIProvider: any RecipeAI]
  @ObservationIgnored private let onDevice: (any RecipeAI)?

  /// `keys` gives each provider's key store and `makeClient` its cloud client, which is handed
  /// that store.
  public init(
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
  public convenience init(keys: any AIKeyStore, client: any RecipeAI, onDevice: (any RecipeAI)?) {
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
  /// model where there is one. The choices are read from the settings named `suiteName`, or
  /// the app's own; the share extension names the App Group's (`AppGroup.id`), where the app
  /// leaves them for it.
  public static func live(suiteName: String? = nil) -> RecipeAIService {
    RecipeAIService(
      defaults: suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard,
      keys: { KeychainKeyStore(provider: $0) },
      makeClient: { provider, keys in
        CloudRecipeAI(provider: provider, keys: keys, transport: URLSessionTransport()) {
          chosenModel(for: provider, suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard)
        }
      },
      onDevice: OnDeviceRecipeAI.make())
  }

  // MARK: The share extension's copy of the choices

  /// The App Group's settings, which the share extension can read. Nil in a build without
  /// the App Group.
  public nonisolated static var sharedDefaults: UserDefaults? {
    UserDefaults(suiteName: AppGroup.id)
  }

  /// Copies the chosen provider and each provider's model from the app's settings into
  /// `target`, so the share extension asks the same AI the app would. The app calls it
  /// whenever it comes forward or goes away, which covers a change in Settings.
  public nonisolated static func shareChoices(
    from source: UserDefaults = .standard, to target: UserDefaults?
  ) {
    guard let target else { return }
    let keys = [providerDefaultsKey] + AIProvider.allCases.map(modelDefaultsKey(for:))
    for key in keys {
      if let value = source.string(forKey: key) {
        target.set(value, forKey: key)
      } else {
        target.removeObject(forKey: key)
      }
    }
  }

  /// No key, no network and no on-device model, for tests and previews. `key` is Gemini's, the
  /// provider it starts on; the others have none. Its settings are its own, so a provider
  /// chosen on it is not remembered.
  public static func offline(key: String? = nil) -> RecipeAIService {
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
  public func select(_ provider: AIProvider) {
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
  public func saveKey(_ key: String) -> Bool {
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
  public func removeKey() -> Bool {
    saveKey("")
  }

  /// Looks at the keychain again. A key saved on another device arrives through iCloud
  /// Keychain without this device being told.
  public func refreshKey() {
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
  public func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    try await extractor.extract(input)
  }

  /// `extract(_:)` as a value the import pipeline can take: the same fallback rule, and the
  /// same effect on `status`.
  public var extractor: any RecipeExtracting {
    FallbackExtractor(primary: watched, onDevice: onDevice)
  }

  /// The chosen provider alone, for the queue. Macro estimates never fall back.
  public var estimator: any RecipeAI { watched }

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
  public let base: any RecipeAI
  public let provider: AIProvider
  public let service: RecipeAIService

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

  public func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    try await watch { () async throws(RecipeAIError) in try await base.extract(input) }
  }

  public func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros {
    try await watch { () async throws(RecipeAIError) in try await base.estimateMacros(input) }
  }

  public func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem] {
    try await watch { () async throws(RecipeAIError) in try await base.estimateMeal(text) }
  }
}

/// Stands in where a provider has no client, which can't happen: every provider gets one.
private struct NoRecipeAI: RecipeAI {
  public func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    throw .unreachable
  }

  public func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros {
    throw .unreachable
  }

  public func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem] {
    throw .unreachable
  }
}
