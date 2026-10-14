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

    /// The AI provider, its key and the state of the AI. A problem shows as a line that stays,
    /// here and beside AI actions, never as an alert. The strings that name a provider take it,
    /// so they read the same for Gemini, OpenAI and Claude.
    public struct AI: Sendable {
      public let title = plain("AI")
      public let providerLabel = plain("Provider")
      public let geminiName = plain("Gemini")
      public let openAIName = plain("OpenAI")
      public let claudeName = plain("Claude")
      public let keyPlaceholder = plain("Paste your key")
      public let saveKey = plain("Save key")
      public let removeKey = plain("Remove key")
      public let keySaved = plain("A key is saved in your keychain.")
      public let keyNotSaved = plain("Couldn't save the key to your keychain.")
      public let modelLabel = plain("Model")

      /// What `AIProvider.displayName` says.
      public func providerName(_ provider: AIProvider) -> CopyString {
        switch provider {
        case .gemini: geminiName
        case .openai: openAIName
        case .anthropic: claudeName
        }
      }

      public func keyLabel(_ provider: AIProvider) -> CopyString {
        plain("\(provider.displayName) API key")
      }

      /// Who gets the text, named the way the cook knows them.
      public func hint(_ provider: AIProvider) -> CopyString {
        let who =
          switch provider {
          case .gemini: "Google's Gemini"
          case .openai: "OpenAI"
          case .anthropic: "Anthropic's Claude"
          }
        return plain(
          "Cauldron sends recipe text and meal descriptions to \(who) with your own key. The key stays in your keychain."
        )
      }

      public func ready(_ provider: AIProvider) -> CopyString {
        plain("\(provider.displayName) is set up.")
      }

      public func missingKey(_ provider: AIProvider) -> CopyString {
        let name = provider.displayName
        return plain(
          "Add a \(name) API key to read recipes and estimate macros with \(name). Until then recipes are read on this device, and estimates wait."
        )
      }

      public func invalidKey(_ provider: AIProvider) -> CopyString {
        plain("\(provider.displayName) didn't accept that key. Check it and save it again.")
      }

      public func rateLimited(_ provider: AIProvider) -> CopyString {
        plain(
          "Your \(provider.displayName) key has reached its limit for now. Estimates wait and finish later."
        )
      }

      public func invalidModel(_ provider: AIProvider) -> CopyString {
        plain(
          "\(provider.displayName) doesn't know that model. Check its name below, or clear it to use the usual one."
        )
      }

      public func modelHint(_ model: String) -> CopyString {
        plain("Leave empty to use \(model).")
      }

      public func estimateMissing(_ count: Int) -> CopyString {
        plain(count == 1 ? "Estimate macros for 1 recipe" : "Estimate macros for \(count) recipes")
      }

      public let nothingMissing = plain("Every recipe with ingredients has macros.")

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
