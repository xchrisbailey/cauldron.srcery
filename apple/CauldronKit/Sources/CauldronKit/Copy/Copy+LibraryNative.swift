extension Copy {
  /// What the recipe library says that the web copy doesn't: renaming a tag, which the web
  /// has an API for but no screen. These strings have no counterpart in the web copy, so the
  /// reference fixture leaves them out. All of it is a control or a form, so all of it is plain.
  public struct LibraryNative: Sendable {
    /// The tag menu's item that renames the tag being filtered on.
    public let renameTag = plain("Rename tag…")
    public let renameTagField = plain("Tag name")
    public let renameTagSave = plain("Rename")

    public init() {}

    public func renameTagTitle(_ name: String) -> CopyString { plain("Rename \(name)") }
  }
}
