extension Copy {
  /// The native Settings screen. These strings have no counterpart in the web copy, so the
  /// reference fixture leaves them out. Settings is all plain: it is controls and status.
  public struct Settings: Sendable {
    public let title = plain("Settings")
    public let appearance = Appearance()
    public let iCloud = ICloud()

    public init() {}

    public struct Appearance: Sendable {
      public let title = plain("Appearance")
      public let system = plain("System")
      /// The light theme, named for the palette.
      public let latte = plain("Latte")
      /// The dark theme, named for the palette.
      public let mocha = plain("Mocha")
      public let hint = plain("Applies to this device only.")

      public init() {}
    }

    /// The sync status line, one message per state. Signed out and full both say the data is
    /// safe on the device, because that is what the cook needs to know.
    public struct ICloud: Sendable {
      public let title = plain("iCloud")
      public let checking = plain("Checking iCloud…")
      public let notSetUp = plain(
        "iCloud sync isn't set up on this build. Everything is saved on this device.")
      public let synced = plain("Syncing with iCloud.")
      public let signedOut = plain(
        "You're signed out of iCloud. Everything is saved on this device and will sync when you sign in."
      )
      public let full = plain(
        "Your iCloud storage is full. Everything is saved on this device. Free up space in iCloud to start syncing again."
      )
      public let unavailable = plain(
        "iCloud isn't available right now. Everything is saved on this device.")

      public init() {}
    }
  }
}
