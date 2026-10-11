import Foundation
import SwiftData

/// A record whose `updatedAt` decides which duplicate wins (see `Deduplication`).
protocol Stamped: PersistentModel {
  var updatedAt: Date { get set }
}

extension RecipeRecord: Stamped {}
extension TagRecord: Stamped {}
extension PlanEntryRecord: Stamped {}
extension GatherItemRecord: Stamped {}
extension DiaryEntryRecord: Stamped {}
extension FavouriteRecord: Stamped {}
extension WeighInRecord: Stamped {}
extension BodyProfileRecord: Stamped {}
extension TargetsRecord: Stamped {}
extension PreferencesRecord: Stamped {}
extension AIJobRecord: Stamped {}

/// Sets `updatedAt` on every row a context is about to save a change to, so no screen has to
/// remember. Rows arriving from iCloud are saved by another context and keep the time the
/// other device gave them. Keep the value alive for as long as the context is in use.
final class ChangeStamps {
  private let observer: any NSObjectProtocol

  init(on context: ModelContext, now: @escaping @Sendable () -> Date = { .now }) {
    observer = NotificationCenter.default.addObserver(
      forName: ModelContext.willSave, object: context, queue: nil
    ) { notification in
      guard let context = notification.object as? ModelContext else { return }
      let stamp = now()
      for case let row as any Stamped in context.changedModelsArray {
        row.updatedAt = stamp
      }
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(observer)
  }
}
