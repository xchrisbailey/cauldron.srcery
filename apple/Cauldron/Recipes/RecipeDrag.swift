import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The payload of dragging a recipe out of the library to a day in the week: the recipe's id,
/// and nothing else.
///
/// It travels as plain text with a prefix, not as JSON like `MealDrag`. A meal dropped on a
/// day and a recipe dropped on a day are different things, and two JSON payloads that each
/// carry one `id` would each be taken for the other by whichever destination looked first. A
/// drop that isn't one of ours (text from another app) fails to read and is ignored.
struct RecipeDrag: Transferable, Sendable, Equatable {
  /// What a payload starts with; the recipe's id follows.
  private static let prefix = "cauldron-recipe:"

  struct NotARecipe: Error {}

  let id: UUID

  init(id: UUID) {
    self.id = id
  }

  /// Reads a payload, or throws `NotARecipe` for anything that isn't one.
  init(payload: Data) throws {
    guard let text = String(data: payload, encoding: .utf8), text.hasPrefix(Self.prefix),
      let id = UUID(uuidString: String(text.dropFirst(Self.prefix.count)))
    else { throw NotARecipe() }
    self.id = id
  }

  var payload: Data { Data((Self.prefix + id.uuidString).utf8) }

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(contentType: .utf8PlainText) { drag in
      drag.payload
    } importing: { data in
      try RecipeDrag(payload: data)
    }
  }
}
