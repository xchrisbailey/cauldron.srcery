import CauldronKit
import CloudKit
import CoreData
import Foundation
import Observation

/// Where iCloud sync stands, as the Settings status line and the banner report it. Whatever the
/// state, the data stays on the device; the copy says so for the two that look alarming.
enum ICloudStatus: Equatable, Sendable {
  /// Not asked yet.
  case checking
  /// This build has no iCloud entitlement (#162), so the store is local only.
  case notSetUp
  case synced
  case signedOut
  /// The iCloud quota is used up, so changes can't be uploaded.
  case full
  /// iCloud can't be reached for a reason that isn't the two above.
  case unavailable

  var message: CopyString {
    let copy = Copy.settings.iCloud
    return switch self {
    case .checking: copy.checking
    case .notSetUp: copy.notSetUp
    case .synced: copy.synced
    case .signedOut: copy.signedOut
    case .full: copy.full
    case .unavailable: copy.unavailable
    }
  }

  /// An SF Symbol.
  var systemImage: String {
    switch self {
    case .checking: "icloud"
    case .notSetUp, .unavailable: "icloud.slash"
    case .synced: "checkmark.icloud"
    case .signedOut: "person.crop.circle.badge.exclamationmark"
    case .full: "exclamationmark.icloud"
    }
  }

  /// Whether the cook should be told outside Settings. A build without iCloud isn't a problem
  /// the cook can fix, so it stays in Settings.
  var needsAttention: Bool {
    switch self {
    case .signedOut, .full: true
    case .checking, .notSetUp, .synced, .unavailable: false
    }
  }

  /// The state for a synced store, from what iCloud reports. A full quota outranks a signed-in
  /// account: it is the thing the cook has to act on.
  static func resolve(hasAccount: Bool, quotaExceeded: Bool) -> ICloudStatus {
    if !hasAccount { return .signedOut }
    return quotaExceeded ? .full : .synced
  }
}

/// The source of `ICloudStatus`. The app uses `LiveICloudAccount`; tests use a double that
/// reports whatever they need.
protocol ICloudAccount: Sendable {
  func status() async -> ICloudStatus
  /// Every later change of state. It may never yield, and finishes only when the source can
  /// never change again.
  func changes() -> AsyncStream<ICloudStatus>
}

/// Holds the current status for the views.
@MainActor
@Observable
final class SyncStatusModel {
  private(set) var status = ICloudStatus.checking
  @ObservationIgnored private let account: any ICloudAccount

  init(account: any ICloudAccount) {
    self.account = account
  }

  /// Reads the status, then follows changes until cancelled. Run it from a `.task`.
  func run() async {
    status = await account.status()
    for await next in account.changes() {
      status = next
    }
  }
}

/// iCloud as the device reports it. A store that isn't `.synced` has no CloudKit mirroring to
/// ask about, and CloudKit refuses to run in an app without the entitlement, so it reports
/// `.notSetUp` without touching it.
///
/// For a synced store it reads the account from `ubiquityIdentityToken` and watches
/// `NSPersistentCloudKitContainer`'s event notification (which SwiftData's CloudKit mirroring
/// posts) for a quota error. Neither path can run until the entitlement exists, so the synced
/// branch is untested beyond `ICloudStatus.resolve`.
struct LiveICloudAccount: ICloudAccount {
  let mode: CauldronStore.Mode

  func status() async -> ICloudStatus {
    guard mode == .synced else { return .notSetUp }
    return ICloudStatus.resolve(hasAccount: Self.hasAccount, quotaExceeded: false)
  }

  func changes() -> AsyncStream<ICloudStatus> {
    guard mode == .synced else {
      return AsyncStream { $0.finish() }
    }
    return AsyncStream { continuation in
      let observers = Observers()
      let center = NotificationCenter.default
      observers.add(
        center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: nil) { _ in
          continuation.yield(.resolve(hasAccount: Self.hasAccount, quotaExceeded: false))
        })
      observers.add(
        center.addObserver(
          forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
        ) { notification in
          let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
          guard let event = notification.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
            event.endDate != nil
          else { return }
          let quotaExceeded = (event.error as? CKError)?.code == .quotaExceeded
          // A finished event with no error means sync is working again.
          guard quotaExceeded || event.error == nil else { return }
          continuation.yield(.resolve(hasAccount: Self.hasAccount, quotaExceeded: quotaExceeded))
        })
      continuation.onTermination = { _ in observers.removeAll() }
    }
  }

  private static var hasAccount: Bool { FileManager.default.ubiquityIdentityToken != nil }
}

/// Notification observer tokens, removed together when a stream ends.
private final class Observers: @unchecked Sendable {
  private let lock = NSLock()
  private var tokens: [any NSObjectProtocol] = []

  func add(_ token: any NSObjectProtocol) {
    lock.withLock { tokens.append(token) }
  }

  func removeAll() {
    let taken = lock.withLock {
      defer { tokens = [] }
      return tokens
    }
    for token in taken { NotificationCenter.default.removeObserver(token) }
  }
}
