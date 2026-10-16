import CauldronKit
import Foundation
import Security

/// Moves each provider's AI key into the keychain group the app shares with its share extension
/// (#193), so the extension can read a key saved before the group existed. The app runs it at
/// launch, before it reads a key. It is safe to run every time: once a key has moved there is
/// nothing left to move, and a key another device saved with an older build moves as soon as
/// iCloud Keychain brings it here.
public enum AIKeyMove {
  /// What happened to one provider's key.
  public enum Outcome: Equatable, Sendable {
    case moved
    /// The shared group held the key already: another device moved it, and iCloud Keychain
    /// brought it here. The old copy is removed.
    case alreadyMoved
    case nothingToMove
    /// The keychain refused, with its result code. The key stays where it was.
    case failed(OSStatus)
  }

  /// Whether this platform has the Mac's file-based keychain, where a key that didn't sync may
  /// have been kept.
  public static var hasFileKeychain: Bool {
    #if os(macOS)
      true
    #else
      false
    #endif
  }

  /// Moves every provider's key from `legacy` into `shared`. Does nothing when either group is
  /// unknown, as in a build without a team.
  @discardableResult
  public static func run(
    keychain: any KeychainItems = SystemKeychain(), shared: String?, legacy: String?,
    fileKeychain: Bool = hasFileKeychain
  ) -> [AIProvider: Outcome] {
    guard let shared, let legacy, shared != legacy else { return [:] }
    var outcomes: [AIProvider: Outcome] = [:]
    for provider in AIProvider.allCases {
      outcomes[provider] = move(
        provider, keychain: keychain, shared: shared, legacy: legacy, fileKeychain: fileKeychain)
    }
    return outcomes
  }

  private static func move(
    _ provider: AIProvider, keychain: any KeychainItems, shared: String, legacy: String,
    fileKeychain: Bool
  ) -> Outcome {
    let service = KeychainKeyStore.service(for: provider)
    let account = KeychainKeyStore.account
    let old = KeychainQuery(service: service, account: account, group: legacy, synchronizable: nil)
    switch keychain.move(old, to: shared) {
    case errSecSuccess:
      return .moved
    case errSecDuplicateItem:
      let removed = keychain.delete(old)
      return removed == errSecSuccess || removed == errSecItemNotFound
        ? .alreadyMoved : .failed(removed)
    case errSecItemNotFound:
      break
    case let refused:
      return .failed(refused)
    }

    // On the Mac, a key that couldn't be saved to sync went to the file-based keychain, which
    // has no groups to move between: it is read, added to the shared group, and only then
    // removed.
    guard fileKeychain else { return .nothingToMove }
    let file = KeychainQuery(
      service: service, account: account, group: nil, synchronizable: nil, store: .file)
    let found = keychain.read(file)
    guard found.status == errSecSuccess, let data = found.data, !data.isEmpty else {
      return found.status == errSecItemNotFound || found.status == errSecSuccess
        ? .nothingToMove : .failed(found.status)
    }
    var target = KeychainQuery(
      service: service, account: account, group: shared, synchronizable: true)
    var added = keychain.add(target, data: data)
    if added != errSecSuccess && added != errSecDuplicateItem {
      // As the key store does: kept on this device when it can't sync.
      target.synchronizable = false
      added = keychain.add(target, data: data)
    }
    guard added == errSecSuccess || added == errSecDuplicateItem else { return .failed(added) }
    _ = keychain.delete(file)
    return added == errSecSuccess ? .moved : .alreadyMoved
  }
}
