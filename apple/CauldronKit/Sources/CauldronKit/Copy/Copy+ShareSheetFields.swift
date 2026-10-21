extension Copy {
  public struct ShareSheetFields: Sendable {
    public let readOnlyProblems = plain(
      "Other recipe details need attention. Continue in Cauldron to fix them before saving.")
    public let readOnlyLists = plain("Edit ingredients and steps in Cauldron.")
    public let next = plain("Next")
    public func problem(_ label: CopyString, _ error: CopyString) -> CopyString {
      plain("\(label.text): \(error.text)")
    }
  }
  public static let shareSheetFields = ShareSheetFields()
}
