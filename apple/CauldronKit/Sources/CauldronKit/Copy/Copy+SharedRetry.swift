extension Copy {
  public struct SharedRetry: Sendable {
    public let couldntDiscard = plain(
      "Cauldron couldn't discard this draft. Try again, or close to keep it.")
    public let couldntKeepResult = plain(
      "Cauldron read the recipe but couldn't keep the result. Try again to keep it. Your original source is still kept."
    )
    public let unreadable = plain(
      "Cauldron couldn't read this shared draft or recover its source. The original file is kept on this device. You can paste the recipe again or discard this draft."
    )
    public let recovered = plain(
      "Cauldron couldn't restore the recipe details. The original shared source is kept for another try."
    )
  }
  public static let sharedRetry = SharedRetry()
}
