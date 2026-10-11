import CauldronKit
import Foundation
import Observation
import SwiftData
import SwiftUI

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

/// The Export section for Settings: one action that writes the JSON file and the photos zip,
/// then offers them through the share sheet, which includes Save to Files. It reads the
/// container from the environment, so Settings only has to host it in a `Form` or `List`.
struct ExportSection: View {
  @Environment(\.modelContext) private var modelContext
  @State private var controller = ExportController()

  var body: some View {
    Section {
      switch controller.phase {
      case .idle:
        exportButton
      case .working(let progress):
        ProgressView(value: progress.fraction) {
          Text(Copy.export.working.text)
        }
      case .ready(let result):
        exportButton
        Text(Copy.export.ready(recipes: result.recipeCount, photos: result.photoCount).text)
          .foregroundStyle(Brand.Colors.subtext)
        if result.skipped > 0 {
          Text(Copy.export.skipped(result.skipped).text)
            .foregroundStyle(Brand.Colors.subtext)
        }
        ShareLink(items: result.urls) {
          Label(Copy.export.share.text, systemImage: "square.and.arrow.up")
        }
      case .failed:
        Label(Copy.export.failed.text, systemImage: "exclamationmark.triangle")
        exportButton
      }
    } header: {
      Text(Copy.export.title.text)
    } footer: {
      Text(Copy.export.explanation.text)
    }
  }

  private var exportButton: some View {
    Button(Copy.export.action.text) {
      let container = modelContext.container
      Task { await controller.start(container) }
    }
    .disabled(controller.isWorking)
  }
}

#if DEBUG
  #Preview {
    if let container = try? CauldronStore.container(.inMemory) {
      Form { ExportSection() }
        .modelContainer(container)
    }
  }
#endif
