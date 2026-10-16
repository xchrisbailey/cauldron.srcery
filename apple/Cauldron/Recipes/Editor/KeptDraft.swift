import CauldronImports
import CauldronKit
import Foundation
import SwiftUI

// An unfinished new recipe, kept on this device so closing the editor, the app or the Mac doesn't
// lose it (`lib/recipe-draft.ts` and `keepDraft` in the web editor).
//
// The rules are the web editor's:
// - Only a new recipe's draft is kept. An edit is saved by Save or not at all, and an import is
//   kept by the import (its draft is the sheet's until the cook saves it), so neither reads,
//   writes or clears this one.
// - It is written a short while after the cook stops changing something, and when the editor
//   closes. Nothing time-limited: it stays until the recipe is saved, the cook starts over, or
//   the draft is empty again.
// - A draft written by another version of the app, or that can't be read, is dropped.
// - It lives in a file in the app's own folder: never in SwiftData, so it is never synced.

extension RecipeDraft {
  /// Whether the draft has nothing in it worth keeping.
  var hasNothingToKeep: Bool { KeptDraft(self).isEmpty }
}

// MARK: Where it is kept

/// Somewhere an unfinished draft is kept. The live one is a file; tests use memory.
@MainActor
protocol DraftKeeping: AnyObject {
  /// The kept draft, or nil when there is none or it can't be used (which also removes it).
  func load() -> KeptDraft?
  /// Keeps `draft`, replacing any before it. False when it couldn't be written; the editor works
  /// without it.
  func keep(_ draft: KeptDraft) -> Bool
  func clear()
}

/// A draft kept in a JSON file.
@MainActor
final class FileDraftKeeper: DraftKeeping {
  private let url: URL
  private let fileManager: FileManager

  init(url: URL, fileManager: FileManager = .default) {
    self.url = url
    self.fileManager = fileManager
  }

  /// The file in the app's own Application Support folder (its container, where the Mac app is
  /// sandboxed).
  static func live() -> FileDraftKeeper? {
    guard
      let support = try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    else { return nil }
    let folder = support.appending(path: "computer.srcery.cauldron", directoryHint: .isDirectory)
    return FileDraftKeeper(url: folder.appending(path: "ConjureDraft.json"))
  }

  func load() -> KeptDraft? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    guard let kept = try? JSONDecoder().decode(KeptDraft.self, from: data),
      kept.version == KeptDraft.currentVersion
    else {
      clear()
      return nil
    }
    return kept
  }

  func keep(_ draft: KeptDraft) -> Bool {
    do {
      try fileManager.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(draft).write(to: url, options: [.atomic])
      return true
    } catch {
      return false
    }
  }

  func clear() {
    try? fileManager.removeItem(at: url)
  }
}

/// A draft kept in memory: for tests and previews, and under test as the default so a test run
/// never reads or writes the real file.
@MainActor
final class MemoryDraftKeeper: DraftKeeping {
  private(set) var kept: KeptDraft?
  /// Makes `keep` fail, as a full disk would.
  var failsToKeep = false

  init(_ kept: KeptDraft? = nil) {
    self.kept = kept
  }

  func load() -> KeptDraft? {
    guard let kept else { return nil }
    guard kept.version == KeptDraft.currentVersion else {
      self.kept = nil
      return nil
    }
    return kept
  }

  func keep(_ draft: KeptDraft) -> Bool {
    guard !failsToKeep else { return false }
    kept = draft
    return true
  }

  func clear() {
    kept = nil
  }
}

extension EnvironmentValues {
  /// Where a new recipe's unfinished draft is kept; nil means the app's own (`DraftKeepers`).
  @Entry var draftKeeper: (any DraftKeeping)?
}

@MainActor
enum DraftKeepers {
  /// The app's file, or memory under test so a test run never reads or writes the real one.
  static let shared: any DraftKeeping = {
    if CauldronStore.launchMode != .inMemory, let file = FileDraftKeeper.live() { return file }
    return MemoryDraftKeeper()
  }()
}

// MARK: Keeping as the editor changes

/// Whether the new recipe's draft is on this device.
enum DraftKeepStatus: Equatable {
  /// Nothing to keep yet, or the draft is empty again.
  case idle
  case kept
  /// Couldn't be written. Leaving the editor would lose what was typed.
  case failed
}

/// What the editor does with a new recipe's draft: reads it back when the editor opens, keeps
/// it as it changes, and drops it once the recipe is saved or started over.
@MainActor
struct DraftKeep {
  let keeper: any DraftKeeping

  /// The draft kept earlier, to open the editor on.
  func restored() -> RecipeDraft? { keeper.load()?.draft }

  /// Keeps `draft`, or clears what was kept when it has nothing in it any more.
  @discardableResult
  func keep(_ draft: RecipeDraft) -> DraftKeepStatus {
    let kept = KeptDraft(draft)
    if kept.isEmpty {
      keeper.clear()
      return .idle
    }
    return keeper.keep(kept) ? .kept : .failed
  }

  /// The recipe is saved, or the cook started over.
  func clear() { keeper.clear() }
}
