import CauldronKit
import Foundation
import Security
import Synchronization

/// Where a provider's key is kept. The key is never compiled in, logged or exported.
public protocol AIKeyStore: Sendable {
  func key() -> String?
  /// Saves `key`, or removes the saved one when it is nil or blank.
  func setKey(_ key: String?) throws
}

public struct AIKeyFailure: Error, Equatable {
  public let status: Int32
}

/// The keychain. The key is saved as synchronizable, so iCloud Keychain carries it to the
/// cook's other devices. That needs the keychain entitlement, which arrives with signing
/// (#162); a build without it keeps the key on this device instead.
///
/// Each provider has an item of its own. Gemini's is the one the app has always used
/// (`computer.srcery.cauldron.gemini`), so a key saved before there were other providers is
/// still found.
public struct KeychainKeyStore: AIKeyStore {
  public let provider: AIProvider

  public static func service(for provider: AIProvider) -> String {
    "computer.srcery.cauldron.\(provider.rawValue)"
  }

  public static let account = "api-key"

  private func query(synchronizable: Any) -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.service(for: provider),
      kSecAttrAccount: Self.account,
      kSecAttrSynchronizable: synchronizable,
    ]
  }

  public func key() -> String? {
    var query = query(synchronizable: kSecAttrSynchronizableAny)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
    else { return nil }
    return key
  }

  public func setKey(_ key: String?) throws {
    let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let removed = SecItemDelete(query(synchronizable: kSecAttrSynchronizableAny) as CFDictionary)
    guard !trimmed.isEmpty else {
      guard removed == errSecSuccess || removed == errSecItemNotFound else {
        throw AIKeyFailure(status: removed)
      }
      return
    }
    var status = add(trimmed, synchronizable: true)
    if status != errSecSuccess { status = add(trimmed, synchronizable: false) }
    guard status == errSecSuccess else { throw AIKeyFailure(status: status) }
  }

  private func add(_ key: String, synchronizable: Bool) -> OSStatus {
    var item = query(synchronizable: synchronizable)
    item[kSecValueData] = Data(key.utf8)
    item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
    return SecItemAdd(item as CFDictionary, nil)
  }
}

/// A key held in memory, for tests and previews.
public final class MemoryKeyStore: AIKeyStore {
  private let stored: Mutex<String?>
  private let failsToSave: Bool

  public init(_ key: String? = nil, failsToSave: Bool = false) {
    stored = Mutex(key)
    self.failsToSave = failsToSave
  }

  public func key() -> String? {
    stored.withLock { $0 }
  }

  public func setKey(_ key: String?) throws {
    if failsToSave { throw AIKeyFailure(status: errSecMissingEntitlement) }
    let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    stored.withLock { $0 = trimmed.isEmpty ? nil : trimmed }
  }
}
