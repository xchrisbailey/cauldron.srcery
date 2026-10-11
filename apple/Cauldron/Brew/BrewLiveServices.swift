import CauldronKit
import Foundation
import UserNotifications

#if os(iOS)
  import ActivityKit
  import UIKit
#endif

// The live implementations of the brew services. They are the only code that touches the
// system, so they are thin: what to ask them is decided in `BrewTimers` and tested there.

/// Notifications through `UNUserNotificationCenter`. A timer's notification is scheduled when
/// it starts, so the system delivers it with the app suspended or closed.
@MainActor
final class LiveBrewAlerts: NSObject, BrewAlerts, UNUserNotificationCenterDelegate {
  static let shared = LiveBrewAlerts()

  private let center = UNUserNotificationCenter.current()

  override init() {
    super.init()
    center.delegate = self
  }

  func permission() async -> AlertPermission {
    Self.permission(await center.notificationSettings().authorizationStatus)
  }

  func requestPermission() async -> AlertPermission {
    let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    return granted ? .granted : .denied
  }

  func schedule(_ alert: BrewAlert) async {
    let content = UNMutableNotificationContent()
    content.title = alert.title
    content.body = alert.body
    content.sound = .default
    let seconds = max(1, alert.fireAt.timeIntervalSinceNow)
    let request = UNNotificationRequest(
      identifier: alert.id, content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
    try? await center.add(request)
  }

  func cancel(id: String) async {
    center.removePendingNotificationRequests(withIdentifiers: [id])
  }

  nonisolated static func permission(_ status: UNAuthorizationStatus) -> AlertPermission {
    switch status {
    case .notDetermined: .notDetermined
    case .authorized, .provisional, .ephemeral: .granted
    default: .denied
    }
  }

  /// A timer that finishes while the app is open still shows and sounds.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }
}

#if os(iOS)
  extension BrewActivityState {
    var attributes: BrewTimerAttributes {
      BrewTimerAttributes(
        key: id, recipeTitle: recipeTitle, stepNumber: stepNumber, label: label,
        totalSeconds: totalSeconds)
    }

    var contentState: BrewTimerAttributes.ContentState {
      switch phase {
      case .running(let endsAt):
        BrewTimerAttributes.ContentState(endsAt: endsAt, remainingSeconds: 0, finished: false)
      case .paused(let remaining):
        BrewTimerAttributes.ContentState(endsAt: nil, remainingSeconds: remaining, finished: false)
      case .finished:
        BrewTimerAttributes.ContentState(endsAt: nil, remainingSeconds: 0, finished: true)
      }
    }
  }

  /// Live Activities on the Lock Screen and in the Dynamic Island, one per running step timer.
  @MainActor
  final class LiveBrewActivities: BrewActivities {
    func show(_ state: BrewActivityState) async { await Self.apply(state) }
    func end(id: String) async { await Self.finish(id: id) }

    /// How long a finished timer stays on the Lock Screen.
    private static let lingers: TimeInterval = 5 * 60

    // `Activity` isn't Sendable, so it stays inside these nonisolated functions.
    private nonisolated static func apply(_ state: BrewActivityState) async {
      guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
      let content = ActivityContent(state: state.contentState, staleDate: nil)
      if let existing = find(state.id) {
        if state.phase == .finished {
          await existing.end(content, dismissalPolicy: .after(.now + lingers))
        } else {
          await existing.update(content)
        }
      } else if state.phase != .finished {
        _ = try? Activity.request(attributes: state.attributes, content: content, pushType: nil)
      }
    }

    private nonisolated static func finish(id: String) async {
      await find(id)?.end(nil, dismissalPolicy: .immediate)
    }

    private nonisolated static func find(_ id: String) -> Activity<BrewTimerAttributes>? {
      Activity<BrewTimerAttributes>.activities.first { $0.attributes.key == id }
    }
  }

  @MainActor
  final class LiveScreenAwake: ScreenAwake {
    func keepAwake(_ on: Bool) {
      UIApplication.shared.isIdleTimerDisabled = on
    }
  }
#endif

/// For where there is no Live Activity (the Mac), or none allowed.
@MainActor
final class NoBrewActivities: BrewActivities {
  func show(_ state: BrewActivityState) async {}
  func end(id: String) async {}
}

/// The Mac's display sleep is the cook's own setting; only the iPhone keeps itself awake.
@MainActor
final class NoScreenAwake: ScreenAwake {
  func keepAwake(_ on: Bool) {}
}

/// Running timers in `UserDefaults`: on this device only, so they never go through the synced
/// store, and they are still there after the app is killed and opened again.
@MainActor
final class UserDefaultsBrewTimerStore: BrewTimerStore {
  private let defaults: UserDefaults
  private let key = "computer.srcery.cauldron.brew-timers"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load(recipeID: UUID) -> BrewTimerBoard? {
    all()[recipeID.uuidString].flatMap { try? JSONDecoder().decode(BrewTimerBoard.self, from: $0) }
  }

  func save(_ board: BrewTimerBoard) {
    guard let data = try? JSONEncoder().encode(board) else { return }
    var boards = all()
    boards[board.recipeID.uuidString] = data
    defaults.set(boards, forKey: key)
  }

  func remove(recipeID: UUID) {
    var boards = all()
    boards[recipeID.uuidString] = nil
    defaults.set(boards, forKey: key)
  }

  private func all() -> [String: Data] {
    defaults.dictionary(forKey: key) as? [String: Data] ?? [:]
  }
}

/// The real services, for the app.
@MainActor
enum BrewLive {
  static func model(for plan: BrewPlan) -> BrewModel {
    #if os(iOS)
      let activities: any BrewActivities = LiveBrewActivities()
      let screen: any ScreenAwake = LiveScreenAwake()
    #else
      let activities: any BrewActivities = NoBrewActivities()
      let screen: any ScreenAwake = NoScreenAwake()
    #endif
    let timers = BrewTimers(
      recipeID: plan.recipe.id, recipeTitle: plan.recipe.title,
      store: UserDefaultsBrewTimerStore(), alerts: LiveBrewAlerts.shared,
      activities: activities)
    return BrewModel(plan: plan, timers: timers, screen: screen)
  }
}
