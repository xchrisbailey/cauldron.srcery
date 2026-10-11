import CauldronKit
import Foundation
import SwiftData

/// How far an export has got, as steps: reading the store, each photo, then writing the file.
struct ExportProgress: Sendable, Equatable {
  var completed: Int
  var total: Int

  var fraction: Double { total == 0 ? 1 : Double(completed) / Double(total) }
}

struct ExportResult: Sendable, Equatable {
  /// The versioned JSON file.
  var jsonURL: URL
  /// The zip of photos; nil when no recipe has an image.
  var photosURL: URL?
  /// Recipes that aren't banished.
  var recipeCount: Int
  /// Images written to the zip.
  var photoCount: Int
  /// Rows and values left out because they couldn't be written (see `ExportMapping`).
  var skipped: Int

  /// The files to hand to the share sheet.
  var urls: [URL] { [jsonURL] + (photosURL.map { [$0] } ?? []) }
}

/// Writes an export of the store: one JSON file, and a zip beside it with the photos.
///
/// The zip is the in-house `ZipWriter` (stored entries, no compression) rather than
/// `NSFileCoordinator`'s `.forUploading` or a package. It needs nothing but Foundation, writes
/// one photo at a time so a big box never sits in memory, and the same code runs under the
/// Linux tests. Photos are JPEG or HEIC already, so compressing them would gain nothing.
enum StoreExporter {
  /// Reads the saved store through a context of its own, so it is safe to run off the main
  /// actor, and writes the files into `directory`. A failure removes what it wrote.
  static func export(
    from container: ModelContainer, into directory: URL, now: Date = .now,
    appVersion: String? = nil, timeZone: TimeZone = .current,
    progress: @Sendable (ExportProgress) -> Void = { _ in }
  ) throws -> ExportResult {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let stamp = dayStamp(now, in: timeZone)
    let jsonURL = directory.appending(path: "cauldron-export-\(stamp).json")
    let photosURL = directory.appending(path: "cauldron-photos-\(stamp).zip")

    do {
      progress(ExportProgress(completed: 0, total: 2))
      var mapped = try ExportMapping.document(
        from: ModelContext(container), exportedAt: now, appVersion: appVersion)
      let total = mapped.document.photos.count + 2
      progress(ExportProgress(completed: 1, total: total))

      // Photos one at a time, each read through a context that is dropped straight after, so
      // the image data is released instead of piling up on the context.
      var writer: ZipWriter?
      var written = 0
      for index in mapped.document.photos.indices {
        let id = mapped.document.photos[index].id
        if let data = try imageData(of: id, in: container), !data.isEmpty {
          let zip = try writer ?? ZipWriter(writingTo: photosURL, modified: now)
          writer = zip
          let name = "photos/\(id.uuidString).\(ImageFileType.fileExtension(of: data))"
          try zip.add(name, contents: data)
          mapped.document.photos[index].file = name
          written += 1
        }
        progress(ExportProgress(completed: index + 2, total: total))
      }
      try writer?.finish()

      try mapped.document.encoded().write(to: jsonURL, options: .atomic)
      progress(ExportProgress(completed: total, total: total))
      return ExportResult(
        jsonURL: jsonURL, photosURL: writer == nil ? nil : photosURL,
        recipeCount: mapped.document.recipes.filter { $0.deletedAt == nil }.count,
        photoCount: written, skipped: mapped.skipped)
    } catch {
      try? fileManager.removeItem(at: jsonURL)
      try? fileManager.removeItem(at: photosURL)
      throw error
    }
  }

  private static func imageData(of id: UUID, in container: ModelContainer) throws -> Data? {
    let context = ModelContext(container)
    var descriptor = FetchDescriptor<PhotoRecord>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first?.imageData
  }

  /// The day the export was made, for the file names. It is always a Gregorian date, so a
  /// device set to the Buddhist or Japanese calendar still gets a date a person can read.
  private static func dayStamp(_ date: Date, in timeZone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day,
      let local = LocalDate(year: year, month: month, day: day)
    else { return "backup" }
    return local.description
  }
}
