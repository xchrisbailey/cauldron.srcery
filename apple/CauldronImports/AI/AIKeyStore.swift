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
/// cook's other devices; where that is refused it is kept on this device instead.
///
/// Each provider has an item of its own. Gemini's is the one the app has always used
/// (`computer.srcery.cauldron.gemini`), so a key saved before there were other providers is
/// still found. Every call names the access group the app shares with its share extension
/// (`AIKeyGroup.shared`), so the extension reads the same key; `AIKeyMove` brings a key saved
/// before that group existed into it.
public struct KeychainKeyStore: AIKeyStore {
  public let provider: AIProvider
  /// The access group, or nil for the default one (a build without a team).
  public let group: String?
  private let keychain: any KeychainItems

  public init(
    provider: AIProvider, group: String? = AIKeyGroup.shared,
    keychain: any KeychainItems = SystemKeychain()
  ) {
    self.provider = provider
    self.group = group
    self.keychain = keychain
  }

  public static func service(for provider: AIProvider) -> String {
    "computer.srcery.cauldron.\(provider.rawValue)"
  }

  public static let account = "api-key"

  private func query(synchronizable: Bool?) -> KeychainQuery {
    KeychainQuery(
      service: Self.service(for: provider), account: Self.account, group: group,
      synchronizable: synchronizable)
  }

  public func key() -> String? {
    let found = keychain.read(query(synchronizable: nil))
    guard found.status == errSecSuccess, let data = found.data,
      let key = String(data: data, encoding: .utf8), !key.isEmpty
    else { return nil }
    return key
  }

  public func setKey(_ key: String?) throws {
    let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let removed = keychain.delete(query(synchronizable: nil))
    guard !trimmed.isEmpty else {
      guard removed == errSecSuccess || removed == errSecItemNotFound else {
        throw AIKeyFailure(status: removed)
      }
      return
    }
    var status = keychain.add(query(synchronizable: true), data: Data(trimmed.utf8))
    if status != errSecSuccess {
      status = keychain.add(query(synchronizable: false), data: Data(trimmed.utf8))
    }
    guard status == errSecSuccess else { throw AIKeyFailure(status: status) }
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
