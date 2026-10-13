extension Copy {
  /// What Describe it says when the model can't be reached and the meal waits. The web app had
  /// no waiting entry (its describing needed the server), so these strings have no counterpart
  /// in the web copy and the reference fixture leaves them out. A state and its label are
  /// plain; the sheet's other strings are `Copy.tracker.describe`.
  public struct DescribeNative: Sendable {
    /// Beside a described meal in the diary while its numbers wait for the model.
    public let waitingRow = plain("Waiting for numbers")
    /// In the add sheet, after a description was saved to wait.
    public let waitingSheet = plain(
      "Can't reach the model right now. This is in your diary as you wrote it, and the numbers will fill in when it's back."
    )

    public init() {}
  }
}
