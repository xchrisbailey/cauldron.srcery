#if os(macOS)
  import AppKit
  import PDFKit

  /// Sends a recipe to the Mac's print panel, as the PDF `RecipePDF` draws.
  enum RecipePrinting {
    @MainActor
    static func print(_ printout: RecipePrintout) {
      guard let document = PDFDocument(data: RecipePDF.render(printout)),
        let operation = document.printOperation(
          for: nil, scalingMode: .pageScaleNone, autoRotate: true)
      else { return }
      operation.jobTitle = printout.title
      operation.run()
    }
  }
#endif
