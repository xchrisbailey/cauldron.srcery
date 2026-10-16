import CauldronKit
import Foundation
import Security
import Synchronization
import Testing

@testable import Cauldron
@testable import CauldronImports

/// A keychain in memory that keeps the rules the AI key depends on: each item sits in one access
/// group, a caller reaches only its own groups, a query with no group searches all of them and
/// adds to the default one, and the Mac's file-based keychain has no groups at all.
final class MemoryKeychain: KeychainItems {
  struct Item: Hashable {
    var service: String
    var account: String
    /// Nil in the file-based keychain.
    var group: String?
    var synchronizable: Bool
    var store: KeychainQuery.Store
  }

  private let items: Mutex<[Item: Data]>
  private let defaultGroup: String
  private let groups: Set<String>
  /// Refusals `move` gives before it works, like a keychain still locked after a restart.
  private let refusals: Mutex<[OSStatus]>

  /// `groups` are the ones the caller's entitlements reach; the first is its default.
  init(groups: [String], items: [Item: Data] = [:], refusingMoves refusals: [OSStatus] = []) {
    self.groups = Set(groups)
    defaultGroup = groups.first ?? ""
    self.items = Mutex(items)
    self.refusals = Mutex(refusals)
  }

  var all: [Item: Data] { items.withLock { $0 } }

  private func matches(_ item: Item, _ query: KeychainQuery) -> Bool {
    guard item.service == query.service, item.account == query.account,
      item.store == query.store
    else { return false }
    if let synchronizable = query.synchronizable, synchronizable != item.synchronizable {
      return false
    }
    guard item.store != .file else { return true }
    if let group = query.group { return item.group == group && groups.contains(group) }
    return item.group.map(groups.contains) ?? false
  }

  func read(_ query: KeychainQuery) -> (status: OSStatus, data: Data?) {
    items.withLock { items in
      guard let found = items.first(where: { matches($0.key, query) }) else {
        return (errSecItemNotFound, nil)
      }
      return (errSecSuccess, found.value)
    }
  }

  func add(_ query: KeychainQuery, data: Data) -> OSStatus {
    let group = query.store == .file ? nil : (query.group ?? defaultGroup)
    if let group, !groups.contains(group) { return errSecMissingEntitlement }
    let item = Item(
      service: query.service, account: query.account, group: group,
      synchronizable: query.synchronizable ?? false, store: query.store)
    return items.withLock { items in
      guard items[item] == nil else { return errSecDuplicateItem }
      items[item] = data
      return errSecSuccess
    }
  }

  func move(_ query: KeychainQuery, to group: String) -> OSStatus {
    if let refusal = refusals.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) { return refusal }
    guard groups.contains(group), query.store == .dataProtection else {
      return errSecMissingEntitlement
    }
    return items.withLock { items in
      let found = items.filter { matches($0.key, query) }
      guard !found.isEmpty else { return errSecItemNotFound }
      var moved: [Item: Data] = [:]
      for (item, data) in found {
        var target = item
        target.group = group
        guard items[target] == nil || found[target] != nil else { return errSecDuplicateItem }
        moved[target] = data
      }
      for item in found.keys { items[item] = nil }
      items.merge(moved) { _, new in new }
      return errSecSuccess
    }
  }

  func replace(_ query: KeychainQuery, with data: Data) -> OSStatus {
    items.withLock { items in
      let found = items.keys.filter { matches($0, query) }
      guard !found.isEmpty else { return errSecItemNotFound }
      for item in found { items[item] = data }
      return errSecSuccess
    }
  }

  func delete(_ query: KeychainQuery) -> OSStatus {
    items.withLock { items in
      let found = items.keys.filter { matches($0, query) }
      guard !found.isEmpty else { return errSecItemNotFound }
      for item in found { items[item] = nil }
      return errSecSuccess
    }
  }
}

/// Moving the AI key into the group the share extension can read (#200), and the key store that
/// reads it from there. All against `MemoryKeychain`: no test touches the real keychain.
@Suite("AI key group")
struct AIKeyMoveTests {
  private let shared = "TEAM.computer.srcery.cauldron.shared"
  private let legacy = "TEAM.computer.srcery.cauldron"

  private func item(
    _ provider: AIProvider = .gemini, group: String?, synchronizable: Bool = true,
    store: KeychainQuery.Store = .dataProtection
  ) -> MemoryKeychain.Item {
    MemoryKeychain.Item(
      service: KeychainKeyStore.service(for: provider), account: KeychainKeyStore.account,
      group: group, synchronizable: synchronizable, store: store)
  }

  /// The app's keychain: the shared group, which is its default as the first entry of its
  /// `keychain-access-groups`, and its own.
  private func appKeychain(
    _ items: [MemoryKeychain.Item: Data] = [:], refusingMoves refusals: [OSStatus] = []
  ) -> MemoryKeychain {
    MemoryKeychain(groups: [shared, legacy], items: items, refusingMoves: refusals)
  }

  @Test func aKeySavedBeforeTheGroupIsMovedIntoIt() {
    let keychain = appKeychain([item(group: legacy): Data("old-key".utf8)])

    let outcomes = AIKeyMove.run(
      keychain: keychain, shared: shared, legacy: legacy, fileKeychain: false)

    #expect(outcomes[.gemini] == .moved)
    #expect(keychain.all == [item(group: shared): Data("old-key".utf8)])
    // It still syncs: only its group changed.
    #expect(
      KeychainKeyStore(provider: .gemini, group: shared, keychain: keychain).key() == "old-key")
  }

  @Test func aKeyAnotherDeviceMovedAlreadyLeavesOneCopy() {
    // The other device moved it, and iCloud Keychain brought the moved copy here beside the
    // old one.
    let keychain = appKeychain([
      item(group: legacy): Data("old-key".utf8), item(group: shared): Data("old-key".utf8),
    ])

    let outcomes = AIKeyMove.run(
      keychain: keychain, shared: shared, legacy: legacy, fileKeychain: false)

    #expect(outcomes[.gemini] == .alreadyMoved)
    #expect(keychain.all == [item(group: shared): Data("old-key".utf8)])
  }

  @Test func aDifferentKeyFromADeviceOnAnOlderBuildWinsOverTheMovedOne() {
    // The other device, still on the old build, couldn't see the moved key, and the cook typed
    // a new one there. It came back in the old group.
    let keychain = appKeychain([
      item(group: legacy): Data("new-key".utf8), item(group: shared): Data("old-key".utf8),
    ])

    let outcomes = AIKeyMove.run(
      keychain: keychain, shared: shared, legacy: legacy, fileKeychain: false)

    #expect(outcomes[.gemini] == .alreadyMoved)
    #expect(keychain.all == [item(group: shared): Data("new-key".utf8)])
  }

  @Test func aMoveTheKeychainRefusedIsTriedAgainNextTime() {
    // Before the first unlock after a restart, the keychain refuses.
    let keychain = appKeychain(
      [item(group: legacy): Data("old-key".utf8)], refusingMoves: [errSecInteractionNotAllowed])
    let store = KeychainKeyStore(provider: .gemini, group: shared, keychain: keychain)

    let first = AIKeyMove.run(
      keychain: keychain, shared: shared, legacy: legacy, fileKeychain: false)
    #expect(first[.gemini] == .failed(errSecInteractionNotAllowed))
    #expect(store.key() == nil)

    // The app comes forward once it is unlocked.
    let second = AIKeyMove.run(
      keychain: keychain, shared: shared, legacy: legacy, fileKeychain: false)
    #expect(second[.gemini] == .moved)
    #expect(store.key() == "old-key")
  }

  @Test func withoutATeamTheKeyIsKeptWhereverTheSystemPutsIt() throws {
    let keychain = appKeychain()
    let store = KeychainKeyStore(provider: .gemini, group: nil, keychain: keychain)

    try store.setKey("key")

    #expect(keychain.all.keys.map(\.store) == [.automatic])
    #expect(store.key() == "key")
  }

  @Test func withNoKeyNothingChanges() {
    let keychain = appKeychain()

    let outcomes = AIKeyMove.run(
      keychain: keychain, shared: shared, legacy: legacy, fileKeychain: true)

    #expect(
      outcomes == [.gemini: .nothingToMove, .openai: .nothingToMove, .anthropic: .nothingToMove])
    #expect(keychain.all.isEmpty)
  }

  @Test func eachProvidersKeyMovesOnItsOwn() {
    let keychain = appKeychain([
      item(.openai, group: legacy): Data("openai-key".utf8),
      item(.anthropic, group: shared): Data("claude-key".utf8),
    ])

    let outcomes = AIKeyMove.run(
      keychain: keychain, shared: shared, legacy: legacy, fileKeychain: false)

    #expect(outcomes == [.gemini: .nothingToMove, .openai: .moved, .anthropic: .nothingToMove])
    #expect(
      KeychainKeyStore(provider: .openai, group: shared, keychain: keychain).key() == "openai-key")
    #expect(
      KeychainKeyStore(provider: .anthropic, group: shared, keychain: keychain).key()
        == "claude-key")
  }

  @Test func aKeyInTheMacsFileKeychainIsCopiedAcrossThenRemoved() {
    let keychain = appKeychain([
      item(group: nil, synchronizable: false, store: .file): Data("mac-key".utf8)
    ])

    let outcomes = AIKeyMove.run(
      keychain: keychain, shared: shared, legacy: legacy, fileKeychain: true)

    #expect(outcomes[.gemini] == .moved)
    #expect(keychain.all == [item(group: shared): Data("mac-key".utf8)])
  }

  @Test func aBuildWithoutGroupsMovesNothing() {
    let keychain = appKeychain([item(group: legacy): Data("old-key".utf8)])

    #expect(AIKeyMove.run(keychain: keychain, shared: nil, legacy: legacy).isEmpty)
    #expect(AIKeyMove.run(keychain: keychain, shared: shared, legacy: nil).isEmpty)
    #expect(keychain.all == [item(group: legacy): Data("old-key".utf8)])
  }

  @Test func theExtensionReadsOnlyTheSharedGroup() {
    // The extension's entitlements reach the shared group and not the app's own.
    let before = MemoryKeychain(groups: [shared], items: [item(group: legacy): Data("k".utf8)])
    #expect(KeychainKeyStore(provider: .gemini, group: shared, keychain: before).key() == nil)

    let after = MemoryKeychain(groups: [shared], items: [item(group: shared): Data("k".utf8)])
    #expect(KeychainKeyStore(provider: .gemini, group: shared, keychain: after).key() == "k")
  }

  @Test func savingAKeyPutsItInTheSharedGroupAndRemovingTakesItOut() throws {
    let keychain = appKeychain()
    let store = KeychainKeyStore(provider: .gemini, group: shared, keychain: keychain)

    try store.setKey("  new-key ")
    #expect(keychain.all == [item(group: shared): Data("new-key".utf8)])

    try store.setKey("")
    #expect(keychain.all.isEmpty)
  }

  @Test func theGroupNamesComeFromTheInfoPlistOnlyWhenSigningFilledThemIn() {
    #expect(AIKeyGroup.parse("TEAM.computer.srcery.cauldron.shared") == shared)
    #expect(AIKeyGroup.parse("$(AppIdentifierPrefix)computer.srcery.cauldron.shared") == nil)
    #expect(AIKeyGroup.parse(".computer.srcery.cauldron.shared") == nil)
    #expect(AIKeyGroup.parse("") == nil)
    #expect(AIKeyGroup.parse(nil) == nil)
  }
}

/// The AI choices the share extension reads from the App Group (#200).
@MainActor
@Suite("AI choices for the share extension")
struct SharedAIChoicesTests {
  @Test func theProviderAndModelsAreCopiedForTheExtension() throws {
    let sourceName = "computer.srcery.cauldron.test.\(UUID())"
    let source = try #require(UserDefaults(suiteName: sourceName))
    defer { source.removePersistentDomain(forName: sourceName) }
    let targetName = "computer.srcery.cauldron.test.\(UUID())"
    let target = try #require(UserDefaults(suiteName: targetName))
    defer { target.removePersistentDomain(forName: targetName) }
    source.set(AIProvider.anthropic.rawValue, forKey: RecipeAIService.providerDefaultsKey)
    source.set("claude-test", forKey: RecipeAIService.modelDefaultsKey(for: .anthropic))
    target.set("old-model", forKey: RecipeAIService.modelDefaultsKey(for: .gemini))

    RecipeAIService.shareChoices(from: source, to: target)

    #expect(RecipeAIService.chosenProvider(target) == .anthropic)
    #expect(RecipeAIService.chosenModel(for: .anthropic, target) == "claude-test")
    // A model cleared in Settings is cleared for the extension too.
    #expect(RecipeAIService.chosenModel(for: .gemini, target) == AIProvider.gemini.defaultModel)
  }
}
