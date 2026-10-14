import CauldronKit
import Foundation
import Observation
import SwiftUI

/// How something shared to Cauldron is imported, chosen from what the share sheet gave.
enum SharedImportRoute: Equatable, Sendable {
  /// A web link, read as if it had been typed into the import sheet.
  case link(String)
  /// An Instagram or TikTok post with its caption, which the share sheet provides. The caption
  /// goes down the pasted-text path, so no token is needed, and the post stays as the source.
  case caption(String, post: String)
  /// Text with no link: the pasted-text path.
  case text(String)

  /// The route for `item`, or nil when it holds nothing to read (the extension doesn't leave
  /// such an item, but a damaged one is skipped rather than opening an empty sheet).
  init?(_ item: SharedItem) {
    let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let link = item.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !link.isEmpty {
      // A caption beats the link only for a post. Some platforms put the link in the caption
      // too, so it is taken out before judging whether any caption is left.
      if Distill.classify(link) != .web {
        let caption = text.replacingOccurrences(of: link, with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty {
          self = .caption(caption, post: link)
          return
        }
      }
      self = .link(link)
      return
    }
    guard !text.isEmpty else { return nil }
    // Some apps share a link as plain text. Pasted into the paste box it would be no recipe.
    if !text.contains(where: \.isWhitespace), Distill.isAcceptedLink(text) {
      self = .link(text)
    } else {
      self = .text(text)
    }
  }
}

/// What the share extension left in the inbox, waiting to be opened as imports one at a time.
///
/// The app picks the inbox up when it comes forward. A waiting item is opened only when nothing
/// else is in the way: no import sheet and no editor is open (`readyToOpen`), so a draft the cook
/// is working on is never replaced.
@MainActor
@Observable
final class SharedImportQueue {
  /// Items picked up and not opened yet, oldest first.
  private(set) var pending: [SharedImportRoute] = []
  /// An import sheet is open (shared or typed).
  var importOpen = false
  @ObservationIgnored private let folder: URL?
  @ObservationIgnored private let enabled: Bool
  /// The editors open now, each by its own token so one that is closed twice counts once.
  private var editors: Set<UUID> = []

  /// - Parameters:
  ///   - folder: the inbox folder; nil is the App Group's, looked up when it is first read.
  ///   - enabled: false under test and in previews, where nothing is picked up so the real
  ///     inbox is never touched.
  init(folder: URL? = nil, enabled: Bool) {
    self.folder = folder
    self.enabled = enabled
  }

  /// How many are waiting their turn.
  var waiting: Int { pending.count }

  /// Something is waiting and nothing is in its way.
  var readyToOpen: Bool { !pending.isEmpty && !importOpen && editors.isEmpty }

  /// Takes what is in the inbox. Called at launch and whenever the app comes forward.
  func pickUp() {
    guard enabled else { return }
    pending.append(
      contentsOf: ShareInbox.takeAll(from: folder ?? ShareInbox.folder()).compactMap(
        SharedImportRoute.init))
  }

  /// The next item to open, removed from the queue; nil unless `readyToOpen`.
  func next() -> SharedImportRoute? {
    guard readyToOpen else { return nil }
    return pending.removeFirst()
  }

  func editorOpened(_ token: UUID) { editors.insert(token) }

  func editorClosed(_ token: UUID) { editors.remove(token) }
}

private struct SharedImportsPickUp: ViewModifier {
  let queue: SharedImportQueue
  @Environment(\.scenePhase) private var scenePhase

  func body(content: Content) -> some View {
    content
      .environment(queue)
      // Runs at launch and each time the app comes forward.
      .task(id: scenePhase) {
        if scenePhase == .active { queue.pickUp() }
      }
  }
}

extension View {
  /// Gives the view the queue of shared items and picks the inbox up whenever the app comes
  /// forward.
  func sharedImports(_ queue: SharedImportQueue) -> some View {
    modifier(SharedImportsPickUp(queue: queue))
  }
}
