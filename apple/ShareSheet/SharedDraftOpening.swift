import Foundation

#if os(macOS)
  import AppKit
#endif

/// Workspace dispatch is not an acknowledgement that the editor has consumed the draft.
enum SharedDraftOpeningResult: Equatable, Sendable {
  case opened
  case failed
  case unsupported
}

/// The only platform boundary in continuation. Payloads stay in the retained store.
@MainActor
protocol SharedDraftOpening {
  func open(_ id: UUID) async -> SharedDraftOpeningResult
}

/// Manual continuation, including the supported iPhone Share extension flow.
struct ManualSharedDraftOpening: SharedDraftOpening {
  func open(_ id: UUID) async -> SharedDraftOpeningResult { .unsupported }
}

struct ContainingAppDraftOpening: SharedDraftOpening {
  func open(_ id: UUID) async -> SharedDraftOpeningResult {
    #if os(macOS)
      guard let app = ShareFonts.containingApp(of: Bundle.main.bundleURL) else { return .failed }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      configuration.createsNewApplicationInstance = false
      // Another installed copy may have a different App Group/signing context. Always address
      // the installation that contains this extension, reusing its running instance if any.
      configuration.allowsRunningApplicationSubstitution = false
      configuration.promptsUserIfNeeded = false
      return await withCheckedContinuation { continuation in
        NSWorkspace.shared.open(
          [AppLink.sharedDraft(id).url], withApplicationAt: app, configuration: configuration
        ) { application, error in
          continuation.resume(returning: application != nil && error == nil ? .opened : .failed)
        }
      }
    #else
      return .unsupported
    #endif
  }
}
