/// How a string speaks. The brand rule is magic verbs with plain nouns: `voice` is for the
/// verbs (Conjure, Distill, Stir in, Gather, Divine, Banish) and `plain` for everything else.
/// Errors, quantities, step controls and the literal part of delete confirmations are always
/// plain.
public enum Tone: String, Sendable, Hashable, Codable {
  case voice
  case plain
}

/// One user-facing string and its marking. Views read `text`, for example
/// `Text(Copy.recipes.conjure.text)`; the tone is what a String Catalog comment or a
/// localisation pass will key off later.
public struct CopyString: Sendable, Hashable {
  public let tone: Tone
  public let text: String

  public init(tone: Tone, text: String) {
    self.tone = tone
    self.text = text
  }

  public static func voice(_ text: String) -> CopyString {
    CopyString(tone: .voice, text: text)
  }

  public static func plain(_ text: String) -> CopyString {
    CopyString(tone: .plain, text: text)
  }
}

// Shorthand for the copy structs, which read like the TypeScript table they come from.
func voice(_ text: String) -> CopyString { .voice(text) }
func plain(_ text: String) -> CopyString { .plain(text) }

/// A number the way the web app prints one: no trailing ".0" on whole numbers.
func number(_ value: Double) -> String {
  value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
}
