import Foundation
import Security

/// Which generic-password items a keychain call is about. The key store and the move to the
/// shared group (`AIKeyMove`) say what they want in these terms, so a test can answer from
/// memory, with the same rules about groups, instead of from the real keychain.
public struct KeychainQuery: Hashable, Sendable {
  public enum Store: Hashable, Sendable {
    /// The keychain iOS has and the Mac's iCloud Keychain uses, where access groups apply.
    case dataProtection
    /// The Mac's older file-based keychain, which has no access groups. Only `AIKeyMove`
    /// looks there, for a key that a build which didn't ask for the other one kept on this Mac.
    case file
  }

  public var service: String
  public var account: String
  /// The access group, or nil for any group the caller can reach (and its default one when
  /// adding).
  public var group: String?
  /// Whether the item syncs through iCloud Keychain, or nil for either (and no when adding).
  public var synchronizable: Bool?
  public var store: Store

  public init(
    service: String, account: String, group: String?, synchronizable: Bool?,
    store: Store = .dataProtection
  ) {
    self.service = service
    self.account = account
    self.group = group
    self.synchronizable = synchronizable
    self.store = store
  }
}

/// The few keychain calls the AI key needs, answered with the keychain's own result codes.
public protocol KeychainItems: Sendable {
  /// The first matching item's data, or `errSecItemNotFound`.
  func read(_ query: KeychainQuery) -> (status: OSStatus, data: Data?)
  /// Adds an item holding `data`, readable once the device has been unlocked after starting.
  func add(_ query: KeychainQuery, data: Data) -> OSStatus
  /// Moves every matching item into `group`, or `errSecDuplicateItem` when `group` already
  /// holds the same item.
  func move(_ query: KeychainQuery, to group: String) -> OSStatus
  func delete(_ query: KeychainQuery) -> OSStatus
}

/// The real keychain, through `SecItem`.
public struct SystemKeychain: KeychainItems {
  public init() {}

  private func attributes(_ query: KeychainQuery) -> [CFString: Any] {
    var attributes: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: query.service,
      kSecAttrAccount: query.account,
      kSecAttrSynchronizable: query.synchronizable.map { $0 as Any } ?? kSecAttrSynchronizableAny,
      // Named on every call. On the Mac, leaving it out means the file-based keychain for an
      // item that doesn't sync, where access groups don't apply.
      kSecUseDataProtectionKeychain: query.store == .dataProtection,
    ]
    if let group = query.group { attributes[kSecAttrAccessGroup] = group }
    return attributes
  }

  public func read(_ query: KeychainQuery) -> (status: OSStatus, data: Data?) {
    var search = attributes(query)
    search[kSecReturnData] = true
    search[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(search as CFDictionary, &result)
    return (status, result as? Data)
  }

  public func add(_ query: KeychainQuery, data: Data) -> OSStatus {
    var item = attributes(query)
    item[kSecAttrSynchronizable] = query.synchronizable ?? false
    item[kSecValueData] = data
    item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
    return SecItemAdd(item as CFDictionary, nil)
  }

  public func move(_ query: KeychainQuery, to group: String) -> OSStatus {
    SecItemUpdate(attributes(query) as CFDictionary, [kSecAttrAccessGroup: group] as CFDictionary)
  }

  public func delete(_ query: KeychainQuery) -> OSStatus {
    SecItemDelete(attributes(query) as CFDictionary)
  }
}

/// The keychain groups the AI key is kept in, from the bundle's Info.plist, where signing fills
/// in the team prefix at build time.
public enum AIKeyGroup {
  /// The group the app and the share extension share. Nil in a build without a team, where the
  /// key stays in the default group as it always did.
  public static var shared: String? { value(for: "CauldronKeychainGroup") }

  /// The app's own group, where keys were kept before the shared one. Only the app has it.
  public static var legacy: String? { value(for: "CauldronLegacyKeychainGroup") }

  static func value(for key: String, in bundle: Bundle = .main) -> String? {
    parse(bundle.object(forInfoDictionaryKey: key))
  }

  /// A group name as signing filled it in, or nil when it didn't.
  static func parse(_ raw: Any?) -> String? {
    guard let value = raw as? String, !value.isEmpty, !value.contains("$("),
      // With no team the prefix is empty, and the name starts with a bare dot.
      !value.hasPrefix(".")
    else { return nil }
    return value
  }
}
