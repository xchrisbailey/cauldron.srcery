extension Copy {
  public struct SharedOpening: Sendable {
    public let kept = plain("Shared draft kept")
    public let opening = plain("Opening Cauldron…")
    public let opened = plain(
      "Continue in Cauldron. Your shared draft will wait if you're already editing.")
    public let couldntOpen = plain(
      "Cauldron couldn't open. Your shared draft is kept. Open Cauldron to finish editing.")
    public let macContinuation = plain(
      "Keep this shared draft and open Cauldron to finish editing.")
  }
  public static let sharedOpening = SharedOpening()
}
