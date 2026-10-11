import CauldronKit
import Foundation
import Observation
import SwiftData

/// The folders exports are written to. Each holds a full copy of the cook's data, so none is
/// left lying in the temporary directory longer than it has to be.
enum ExportFiles {
  static let folderPrefix = "CauldronExport-"

  /// A new, unused folder name for one export.
  static func newFolder(
    in temporary: URL = FileManager.default.temporaryDirectory
  ) -> URL {
    temporary.appending(
      path: "\(folderPrefix)\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  /// Removes every export folder in `temporary`. Call it at launch (nothing from the last run
  /// is wanted), and it runs again at the start of each export.
  static func sweep(in temporary: URL = FileManager.default.temporaryDirectory) {
    let fileManager = FileManager.default
    let names =
      (try? fileManager.contentsOfDirectory(atPath: temporary.path(percentEncoded: false))) ?? []
    for name in names where name.hasPrefix(folderPrefix) {
      try? fileManager.removeItem(at: temporary.appending(path: name))
    }
  }
}

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

  /// Saves `context`, so the export sees what is on screen, then exports its store into a
  /// fresh folder in the temporary directory, replacing the folder of the last export. Does
  /// nothing while one is running.
  func start(_ context: ModelContext) async {
    guard !isWorking else { return }
    ExportFiles.sweep()
    directory = nil
    phase = .working(ExportProgress(completed: 0, total: 2))
    do {
      // The exporter reads through a context of its own, which sees only what is saved.
      if context.hasChanges { try context.save() }
    } catch {
      phase = .failed
      return
    }
    let container = context.container
    let folder = ExportFiles.newFolder()
    directory = folder
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
