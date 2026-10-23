import OSLog
import SwiftData

extension CauldronStore {
  private static let log = Logger(subsystem: "computer.srcery.cauldron", category: "store")

  /// Removes settled duplicate rows (see `Deduplication`) once at launch, on `context`.
  /// Under test the store is in memory and there is nothing to tidy, so it does nothing there.
  /// A failure is logged and the app carries on: duplicates are already ignored by reads, so
  /// they only wait for the next launch. Returns how many rows went.
  @discardableResult
  static func tidyAtLaunch(_ context: ModelContext, mode: Mode, now: Date = .now) -> Int {
    guard mode == .synced || mode == .local else { return 0 }
    do {
      let removed = try Deduplication.tidy(context, now: now)
      if removed > 0 {
        try context.save()
        log.info("Tidied \(removed) duplicate rows")
      }
      return removed
    } catch {
      log.error("Couldn't tidy duplicate rows: \(error)")
      return 0
    }
  }
}
