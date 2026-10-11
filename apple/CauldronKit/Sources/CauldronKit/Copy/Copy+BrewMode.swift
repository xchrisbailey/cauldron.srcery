extension Copy {
  /// What native brew mode says beyond the web's (`brewing`): the Lock Screen timers and the
  /// notification that says one has finished. No counterpart in the web copy, so the reference
  /// fixture leaves them out. All plain: controls and explanations.
  public struct BrewModeNative: Sendable {
    /// Shown while a timer runs and the cook has refused notifications.
    public let notificationsRefused = plain(
      "Notifications are off for Cauldron, so a timer won't alert you when you're away from the app. You can turn them on in Settings."
    )
    /// Adds a minute to the step's timer.
    public let addMinute = plain("Add a minute")
    /// What a Live Activity says while its timer is paused.
    public let paused = plain("Paused")

    public init() {}
  }
}
