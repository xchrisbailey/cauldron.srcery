import CauldronKit
import SwiftData
import SwiftUI

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
