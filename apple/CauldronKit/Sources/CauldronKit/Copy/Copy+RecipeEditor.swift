extension Copy {
  /// What the native recipe editor says beyond the web editor's strings (`editor`). These have
  /// no counterpart in the web copy, so the reference fixture leaves them out. All plain:
  /// they are controls and explanations.
  public struct RecipeEditorNative: Sendable {
    /// Under the ingredients when a newer version of the app wrote lines this one can't read.
    public let ingredientsReadOnly = plain(
      "Some of this recipe's ingredients were saved by a newer version of Cauldron, so they can't be edited here. They are kept as they are, and you can still change the rest."
    )
    /// The same, for the method.
    public let stepsReadOnly = plain(
      "Some of this recipe's steps were saved by a newer version of Cauldron, so they can't be edited here. They are kept as they are, and you can still change the rest."
    )
    /// Opens the camera, on a device that has one.
    public let takePhoto = plain("Take a photo")
    /// Under "Divining…" when the AI can't be reached while the editor is open: the web editor
    /// failed at once, but a native recipe's estimate waits in the queue and starts on Save.
    public let divineQueued = plain(
      "The AI can't be reached just now. The estimate will fill in after you save, once it can be."
    )

    public init() {}
  }
}
