import CauldronImports
import CauldronKit
import Foundation

/// A durable handoff, kept until the cook saves or explicitly discards it. Reads never consume it.
struct RetainedSharedDraft: Codable, Equatable, Identifiable {
  enum Status: String, Codable { case editing, saved, discarded }
  var version = 1
  var id: UUID
  var item: SharedItem
  var status = Status.editing
  var parsed: FinishedRecipe?
  var photo: KeptDraft.Photo?
  var photoRemoved = false
  var review: Set<DraftField> = []
  var flagged: [Bool] = []
  var stepFlags: [Bool]?
  /// Original unreadable/unsupported bytes survive salvage, promotion, and explicit discard.
  var recoveryEvidence: Data?
  var ingredientsLocked = false
  var stepsLocked = false

  init(item: SharedItem, draft: RecipeDraft? = nil, coverLink: String? = nil) {
    self.item = item
    id = item.id
    if let draft { update(draft, coverLink: coverLink) }
  }

  mutating func update(_ draft: RecipeDraft, coverLink: String? = nil) {
    parsed = FinishedRecipe(
      draft: draft, id: id, sharedAt: item.sharedAt, coverLink: coverLink ?? parsed?.coverLink)
    photo = KeptDraft(draft).photo
    photoRemoved = draft.photo == .remove
    review = draft.review
    flagged = draft.ingredients.map(\.flagged)
    stepFlags = draft.steps.map(\.flagged)
    ingredientsLocked = draft.ingredientsLocked
    stepsLocked = draft.stepsLocked
  }

  var recipeDraft: RecipeDraft? {
    guard var draft = parsed?.recipeDraft else { return nil }
    draft.review = review
    draft.ingredientsLocked = ingredientsLocked
    draft.stepsLocked = stepsLocked
    for index in draft.ingredients.indices where flagged.indices.contains(index) && flagged[index] {
      let row = draft.ingredients[index]
      if !row.isHeading && !row.corrected {
        draft.ingredients[index] = .imported(row.text, flagged: true)
      }
    }
    if let stepFlags {
      for index in draft.steps.indices where stepFlags.indices.contains(index) && stepFlags[index] {
        let old = draft.steps[index]
        var step = StepRowDraft.imported(old.text, section: old.section, flagged: true)
        step.timerSeconds = old.timerSeconds
        step.timerSet = old.timerSet
        draft.steps[index] = step
      }
    }
    if let photo {
      draft.photo = .replace(
        ProcessedPhoto(data: photo.data, width: photo.width, height: photo.height))
    } else if photoRemoved {
      draft.photo = .remove
    }
    return draft
  }
}

struct RetainedSharedDraftStore {
  let folder: URL?

  static func live() -> Self { Self(folder: AppGroupFolder.named("RetainedSharedDrafts")) }

  func write(_ draft: RetainedSharedDraft) throws {
    guard let folder else { throw CocoaError(.fileNoSuchFile) }
    try JSONEncoder().encode(draft).write(
      to: folder.appending(path: "\(draft.id.uuidString).json"), options: .atomic)
  }

  func read(_ id: UUID) -> RetainedSharedDraft? {
    guard let folder,
      let data = try? Data(contentsOf: folder.appending(path: "\(id.uuidString).json"))
    else { return nil }
    if let draft = try? JSONDecoder().decode(RetainedSharedDraft.self, from: data),
      draft.id == id, draft.item.id == id, draft.version == 1,
      draft.parsed.map({
        $0.version == FinishedRecipe.currentVersion && $0.draft.version == KeptDraft.currentVersion
      }) ?? true
    {
      return draft
    }
    // Decode the source independently: a damaged parsed payload must not hide a good link.
    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let source = object?["item"] as? [String: Any]
    var item = SharedItem(id: id, url: source?["url"] as? String, text: source?["text"] as? String)
    if let date = source?["sharedAt"] as? Double {
      item.sharedAt = Date(timeIntervalSinceReferenceDate: date)
    }
    var recovered = RetainedSharedDraft(item: item)
    if let status = object?["status"] as? String,
      let terminal = RetainedSharedDraft.Status(rawValue: status)
    {
      recovered.status = terminal
    }
    recovered.recoveryEvidence = data
    return recovered
  }

  func all() -> [RetainedSharedDraft] {
    guard let folder,
      let files = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
    else { return [] }
    return files.filter { $0.pathExtension == "json" }.compactMap {
      UUID(uuidString: $0.deletingPathExtension().lastPathComponent)
    }
    .compactMap(read).sorted { $0.item.sharedAt < $1.item.sharedAt }
  }
}
