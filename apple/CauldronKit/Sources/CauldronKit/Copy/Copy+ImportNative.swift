extension Copy {
  /// What the native Distill screens say beyond the web ones (`imports`). These have no
  /// counterpart in the web copy, so the reference fixture leaves them out. All plain: they are
  /// explanations of where a draft came from.
  public struct ImportNative: Sendable {
    /// On a draft the on-device model read because Gemini couldn't be reached. The web app had
    /// no such state: it only ever had the one model.
    public let rough = plain(
      "The model on this device read this recipe because Gemini couldn't be reached, so it may be rougher than usual. Check it carefully before you save."
    )

    public init() {}

    /// Above the paste box after a link couldn't be read. The link stays as the recipe's source.
    public func pastingFor(_ link: String) -> CopyString {
      plain("Paste the recipe from \(link). The link stays as its source.")
    }
  }
}
