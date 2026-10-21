extension Copy {
  public struct SharedDrafts: Sendable {
    public let continueInCauldron = plain("Continue in Cauldron")
    public let openToFinish = plain("Open Cauldron to finish editing.")
    public let couldntKeep = plain(
      "Cauldron couldn't keep this draft. Try continuing again, or cancel.")
    public let discardConfirm = plain("Discard this shared draft and its changes?")
    public let discard = plain("Discard shared draft")
    public let kept = plain("Your shared draft is kept on this device.")
  }
  public static let sharedDrafts = SharedDrafts()
}
