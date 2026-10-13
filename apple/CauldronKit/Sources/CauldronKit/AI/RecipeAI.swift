/// Why the AI couldn't answer.
public enum RecipeAIError: Error, Sendable, Hashable {
  /// No Gemini key has been entered in Settings.
  case missingKey
  /// Gemini refused the key.
  case invalidKey
  /// The key's quota is spent for now (HTTP 429).
  case rateLimited
  /// Offline, timed out, or Gemini answered with a server error.
  case unreachable
  /// The model answered, but not with something usable. Asking again may not help.
  case failed(detail: String)

  /// True when the model simply can't be reached right now, so the work should fall back or
  /// wait instead of failing: no key, a refused key, a spent quota, or no connection.
  public var isUnavailable: Bool {
    switch self {
    case .missingKey, .invalidKey, .rateLimited, .unreachable: true
    case .failed: false
    }
  }
}

/// The three things Cauldron asks a model for. Gemini is the provider now; a Private Cloud
/// Compute provider can take its place behind this without touching callers.
public protocol RecipeAI: Sendable {
  /// Reads a recipe out of text.
  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction
  /// Per-serving macros estimated from the ingredient lines.
  func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros
  /// Foods in a described meal, each with an amount and its numbers.
  func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem]
}

/// What the app shows about the AI, as a persistent line in Settings and beside AI actions.
public enum RecipeAIStatus: Sendable, Hashable {
  case ready
  case missingKey
  case invalidKey
  case rateLimited

  /// The status an error leaves behind, or nil when it says nothing lasting (a dropped
  /// connection, a bad answer).
  public init?(after error: RecipeAIError) {
    switch error {
    case .missingKey: self = .missingKey
    case .invalidKey: self = .invalidKey
    case .rateLimited: self = .rateLimited
    case .unreachable, .failed: return nil
    }
  }
}

/// Recipe extraction with the fallback rule: Gemini first, and when it can't be reached the
/// on-device model reads the text instead and the result is marked rough. A bad answer from
/// Gemini is a failure, not a reason to fall back. Macro estimates never come through here:
/// they wait in the queue.
public struct FallbackExtractor: Sendable {
  let primary: any RecipeAI
  /// The on-device model, or nil where the device has none.
  let onDevice: (any RecipeAI)?

  public init(primary: any RecipeAI, onDevice: (any RecipeAI)?) {
    self.primary = primary
    self.onDevice = onDevice
  }

  public func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    do {
      return try await primary.extract(input)
    } catch let primaryError where primaryError.isUnavailable {
      guard let onDevice else { throw primaryError }
      do {
        var extraction = try await onDevice.extract(input)
        extraction.rough = true
        return extraction
      } catch {
        // The cook hears why Gemini wasn't used, which is the part they can act on.
        throw primaryError
      }
    }
  }
}

/// What to do with a queued job after one attempt.
public enum AIJobDecision: Sendable, Hashable {
  /// Keep it waiting and try again when the model is reachable. Doesn't count as an attempt.
  case wait
  /// Count the attempt and try again later.
  case retry
  /// Give up and show the failure.
  case fail
}

public enum AIJobRules {
  /// A job that fails this many times on the model's own answers is given up on.
  public static let maxAttempts = 3

  /// A job waits as long as the model can't be reached, however long that is. Only real
  /// failures use up its attempts.
  public static func decide(after error: RecipeAIError, attempts: Int) -> AIJobDecision {
    if error.isUnavailable { return .wait }
    return attempts + 1 >= maxAttempts ? .fail : .retry
  }
}
