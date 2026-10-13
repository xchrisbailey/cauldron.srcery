extension Copy {
  /// The native Settings screen. These strings have no counterpart in the web copy, so the
  /// reference fixture leaves them out. Settings is all plain: it is controls and status.
  public struct Settings: Sendable {
    public let title = plain("Settings")
    public let appearance = Appearance()
    public let iCloud = ICloud()
    public let health = Health()
    public let ai = AI()

    public init() {}

    /// The Gemini key and the state of the AI. A problem shows as a line that stays, here and
    /// beside AI actions, never as an alert.
    public struct AI: Sendable {
      public let title = plain("AI")
      public let keyLabel = plain("Gemini API key")
      public let keyPlaceholder = plain("Paste your key")
      public let saveKey = plain("Save key")
      public let removeKey = plain("Remove key")
      public let keySaved = plain("A key is saved in your keychain.")
      public let keyNotSaved = plain("Couldn't save the key to your keychain.")
      public let modelLabel = plain("Model")
      public let hint = plain(
        "Cauldron sends recipe text and meal descriptions to Google's Gemini with your own key. The key stays in your keychain."
      )
      public let ready = plain("Gemini is set up.")
      public let missingKey = plain(
        "Add a Gemini API key to read recipes and estimate macros with Gemini. Until then recipes are read on this device, and estimates wait."
      )
      public let invalidKey = plain("Gemini didn't accept that key. Check it and save it again.")
      public let rateLimited = plain(
        "Your Gemini key has reached its limit for now. Estimates wait and finish later.")

      public func modelHint(_ model: String) -> CopyString {
        plain("Leave empty to use \(model).")
      }

      public func waiting(_ count: Int) -> CopyString {
        plain(count == 1 ? "1 estimate is waiting." : "\(count) estimates are waiting.")
      }

      public init() {}
    }

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

    /// The Health section, and the text of the two permission prompts. `shareUsage` and
    /// `updateUsage` are copied into `project.yml` as `INFOPLIST_KEY_NSHealthShareUsageDescription`
    /// and `INFOPLIST_KEY_NSHealthUpdateUsageDescription`.
    public struct Health: Sendable {
      public let title = plain("Health")
      public let explanation = plain(
        "Cauldron reads your weight from Health, so weigh-ins from a scale appear on their own, and saves the calories, protein, carbs and fat you log to Health's nutrition data. It never reads your activity."
      )
      public let connect = plain("Connect to Health")
      public let connected = plain("Connected to Health.")
      public let checkNow = plain("Check for new weights")
      public let upToDate = plain("Weigh-ins are up to date.")
      public let notSetUp = plain("Health isn't set up on this build.")
      public let unavailable = plain(
        "Health isn't available on this device. Weigh-ins reach the Mac through iCloud.")
      public let couldntConnect = plain(
        "Couldn't connect to Health. You can allow access in Settings, under Health, Data Access & Devices."
      )
      public let couldntUpdate = plain(
        "Couldn't update Health just now. Cauldron will keep trying.")
      /// `NSHealthShareUsageDescription`: what reading is for.
      public let shareUsage = plain(
        "Cauldron reads your body weight so weigh-ins from your scale appear in the diary. It never reads your activity."
      )
      /// `NSHealthUpdateUsageDescription`: what writing is for.
      public let updateUsage = plain(
        "Cauldron saves the calories, protein, carbs and fat you log to Health's nutrition data, and keeps them up to date when you change or remove an entry."
      )

      public init() {}

      /// `names` is a plain list such as "protein and fat".
      public func someOff(_ names: String) -> CopyString {
        plain(
          "Health isn't taking \(names) from Cauldron. Allow it in Settings, under Health, Data Access & Devices."
        )
      }

      public func imported(_ n: Int) -> CopyString {
        plain(n == 1 ? "Added 1 weigh-in from Health." : "Added \(n) weigh-ins from Health.")
      }
    }
  }
}
