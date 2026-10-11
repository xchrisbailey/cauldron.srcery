import CauldronKit
import Foundation
import Observation
import SwiftData

/// Runs one export at a time and holds what the section shows. The work happens off the main
/// actor on a context of its own; progress comes back here.
@MainActor
@Observable
final class ExportController {
  enum Phase {
    case idle
    case working(ExportProgress)
    case ready(ExportResult)
    case failed
  }

  private(set) var phase = Phase.idle
  private var directory: URL?

  var isWorking: Bool {
    if case .working = phase { return true }
    return false
  }

  /// Exports `container` into a fresh folder in the temporary directory, replacing the
  /// folder of the last export. Does nothing while one is running.
  func start(_ container: ModelContainer) async {
    guard !isWorking else { return }
    discardFiles()
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "CauldronExport-\(UUID().uuidString)", directoryHint: .isDirectory)
    directory = folder
    phase = .working(ExportProgress(completed: 0, total: 2))
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        try StoreExporter.export(from: container, into: folder, appVersion: version) { progress in
          Task { @MainActor in self.advance(to: progress) }
        }
      }.value
      phase = .ready(result)
    } catch {
      discardFiles()
      phase = .failed
    }
  }

  /// Progress reports hop threads and can arrive out of order; the bar only moves forward.
  private func advance(to progress: ExportProgress) {
    guard case .working(let current) = phase, progress.completed > current.completed else {
      return
    }
    phase = .working(progress)
  }

  private func discardFiles() {
    if let directory { try? FileManager.default.removeItem(at: directory) }
    directory = nil
  }
}
