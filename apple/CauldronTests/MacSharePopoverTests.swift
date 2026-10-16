import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron
@testable import CauldronImports

/// The Mac share popover (#205): the sheet at the popover's size in every state, and the app
/// picking up a recipe the popover leaves while the app is already open. Folders are temporary
/// and the store is in memory; the real inbox is never touched.
@MainActor
@Suite("Mac share popover")
struct MacSharePopoverTests {
  private let container: ModelContainer
  private let context: ModelContext
  private let finished: URL
  private let drafts: URL

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
    finished = try Self.folder("finished")
    drafts = try Self.folder("drafts")
  }

  private static func folder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "MacSharePopoverTests-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func tidy() {
    try? FileManager.default.removeItem(at: finished)
    try? FileManager.default.removeItem(at: drafts)
  }

  private func files(in folder: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: folder.path()))?.sorted() ?? []
  }

  private func recipes() throws -> [RecipeRecord] {
    try ModelContext(container).fetch(FetchDescriptor<RecipeRecord>())
  }

  /// Waits, up to `seconds`, for `condition`; the folder watch reports from another thread.
  private func eventually(
    _ seconds: Double = 5, _ condition: () async throws -> Bool
  ) async throws -> Bool {
    let end = Date.now.addingTimeInterval(seconds)
    while Date.now < end {
      if try await condition() { return true }
      try await Task.sleep(for: .milliseconds(20))
    }
    return try await condition()
  }

  private func payload(_ title: String = "Shakshuka") throws -> FinishedRecipe {
    var draft = RecipeDraft()
    draft.title = title
    draft.servings = "4"
    draft.sourceURL = "https://eats.example/\(title)"
    draft.setIngredientText(draft.ingredients[0].id, "2 tbsp olive oil")
    draft.setStepText(draft.steps[0].id, "Simmer for 10 minutes.")
    let recipe = FinishedRecipe(draft: draft, id: UUID(), sharedAt: .now)
    try FinishedInbox.add(recipe, in: finished)
    return recipe
  }

  // MARK: The folder watch

  /// Reads a folder's watch in a task of its own, so a watch that says nothing fails a test
  /// instead of waiting for ever.
  private func watch(_ folder: URL) -> (task: Task<Void, Never>, looks: Looks) {
    let looks = Looks()
    let task = Task {
      for await _ in FolderWatcher.changes(in: folder) { await looks.add(0) }
      await looks.end()
    }
    return (task, looks)
  }

  @Test func aWatchedFolderSaysSoAtTheStartAndWhenAFileIsAdded() async throws {
    defer { tidy() }
    let (task, looks) = watch(finished)
    defer { task.cancel() }
    // At the start, for whatever came before the watch.
    #expect(try await eventually { await looks.count == 1 })
    try Data("x".utf8).write(to: finished.appending(path: "a.json"), options: [.atomic])
    #expect(try await eventually { await looks.count >= 2 })
  }

  @Test func aWatchedFolderSaysSoWhenAFileIsRemoved() async throws {
    defer { tidy() }
    let file = finished.appending(path: "a.json")
    try Data("x".utf8).write(to: file)
    let (task, looks) = watch(finished)
    defer { task.cancel() }
    #expect(try await eventually { await looks.count == 1 })
    try FileManager.default.removeItem(at: file)
    #expect(try await eventually { await looks.count >= 2 })
  }

  @Test func aFolderThatCantBeOpenedEndsTheWatch() async throws {
    let missing = FileManager.default.temporaryDirectory.appending(
      path: "MacSharePopoverTests-missing-\(UUID().uuidString)", directoryHint: .isDirectory)
    let (task, looks) = watch(missing)
    defer { task.cancel() }
    #expect(try await eventually { await looks.ended })
    #expect(await looks.count == 0)
  }

  @Test func aFolderThatGoesEndsTheWatch() async throws {
    let (task, looks) = watch(finished)
    defer { task.cancel() }
    #expect(try await eventually { await looks.count == 1 })
    tidy()
    #expect(try await eventually { await looks.ended })
  }

  // MARK: The app, already open

  @Test func aRecipeThatArrivesWhileTheAppIsOpenIsSavedWithoutAScenceChange() async throws {
    defer { tidy() }
    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: true)
    let looks = Looks()
    let watching = Task { @MainActor in
      await queue.receiveWhileOpen(in: context) { added in await looks.add(added) }
    }
    defer { watching.cancel() }
    // The app is open and idle: the first look, at the start, found nothing.
    #expect(try await eventually { await looks.count >= 1 })
    #expect(try recipes().isEmpty)

    let arrived = try payload()

    #expect(try await eventually { try recipes().count == 1 })
    #expect(try recipes().first?.id == arrived.id)
    #expect(try recipes().first?.title == "Shakshuka")
    #expect(try await eventually { files(in: finished).isEmpty })
    #expect(try await eventually { await looks.added == 1 })
  }

  @Test func eachRecipeThatArrivesWhileTheAppIsOpenIsSavedOnce() async throws {
    defer { tidy() }
    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: true)
    let watching = Task { @MainActor in
      await queue.receiveWhileOpen(in: context) { _ in }
    }
    defer { watching.cancel() }

    try payload("One")
    #expect(try await eventually { try recipes().count == 1 })
    try payload("Two")
    try payload("Three")

    #expect(try await eventually { try recipes().count == 3 })
    #expect(try recipes().map(\.title).sorted() == ["One", "Three", "Two"])
    // The removals the app makes itself are changes too; they add nothing.
    try await Task.sleep(for: .milliseconds(200))
    #expect(try recipes().count == 3)
  }

  @Test func aRecipeAlreadyWaitingWhenTheWatchStartsIsTakenToo() async throws {
    defer { tidy() }
    try payload()
    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: true)
    let watching = Task { @MainActor in
      await queue.receiveWhileOpen(in: context) { _ in }
    }
    defer { watching.cancel() }
    #expect(try await eventually { try recipes().count == 1 })
  }

  @Test func linksAndTextForADraftWaitForTheAppToComeForward() async throws {
    defer { tidy() }
    try ShareInbox.add(SharedItem(text: "1 egg. Fry it."), in: drafts)
    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: true)
    let watching = Task { @MainActor in
      await queue.receiveWhileOpen(in: context) { _ in }
    }
    defer { watching.cancel() }

    try payload()

    #expect(try await eventually { try recipes().count == 1 })
    #expect(queue.waiting == 0)
    #expect(files(in: drafts).count == 1)
    // Coming forward takes them, as before.
    queue.pickUp(in: context)
    #expect(queue.waiting == 1)
  }

  @Test func aQueueThatIsntEnabledWatchesNothing() async throws {
    defer { tidy() }
    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: false)
    try payload()
    // Returns at once rather than watching.
    await queue.receiveWhileOpen(in: context) { _ in }
    #expect(try recipes().isEmpty)
    #expect(files(in: finished).count == 1)
  }

  @Test func aCoverIsNotFetchedTwiceWhenTwoLooksOverlap() async throws {
    defer { tidy() }
    var draft = RecipeDraft()
    draft.title = "Tacos"
    draft.sourceURL = ImportFixtures.tacosLink
    draft.setIngredientText(draft.ingredients[0].id, "1 tortilla")
    draft.setStepText(draft.steps[0].id, "Warm it.")
    try FinishedInbox.add(
      FinishedRecipe(draft: draft, id: UUID(), coverLink: ImportFixtures.tacosImage), in: finished)
    // The photo never comes, so the first fetch is still going when the second look begins.
    let fetcher = ScriptedFetcher([ImportFixtures.tacosImage: .hold])
    let queue = SharedImportQueue(folder: drafts, finishedFolder: finished, enabled: true)

    #expect(queue.pickUp(in: context, includingDrafts: false) == 1)
    let first = Task { @MainActor in await queue.fetchCovers(into: context, using: fetcher) }
    #expect(try await eventually { fetcher.startedCount == 1 })
    // The next look finds the same payload, still waiting for its photo.
    #expect(queue.pickUp(in: context, includingDrafts: false) == 0)
    let second = Task { @MainActor in await queue.fetchCovers(into: context, using: fetcher) }
    try await Task.sleep(for: .milliseconds(150))

    #expect(fetcher.startedCount == 1)
    first.cancel()
    second.cancel()
    await first.value
    await second.value
    // Stopped where it was: the file waits for the next time.
    #expect(files(in: finished).count == 1)
  }

  // MARK: The popover's size

  private let size = ShareSheetView.popoverSize

  @Test func theCauldronPopoverIsAFixedSizeThatTheExtensionAsks() {
    #expect(size == CGSize(width: 380, height: 520))
  }

  /// The popover's contents as drawn. On the Mac they are drawn in a real window, which is how
  /// the popover shows them: `ImageRenderer` leaves a scroll view's contents out.
  private func image(_ view: some View, scheme: ColorScheme) -> CGImage? {
    #if os(macOS)
      let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
      host.frame = NSRect(origin: .zero, size: size)
      let window = NSWindow(
        contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
      window.contentView = host
      host.layoutSubtreeIfNeeded()
      guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
      host.cacheDisplay(in: host.bounds, to: rep)
      return rep.cgImage
    #else
      let renderer = ImageRenderer(
        content: view.frame(width: size.width, height: size.height)
          .environment(\.colorScheme, scheme))
      renderer.scale = 1
      return renderer.cgImage
    #endif
  }

  /// Whether anything is drawn in the picture's top half, over the background: the part the
  /// recipe's heading, picture and numbers are in, and a scroll view's contents are.
  private func hasContent(_ image: CGImage) -> Bool {
    guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
      return false
    }
    let pixel = image.bitsPerPixel / 8
    let row = image.bytesPerRow
    let background = (0..<pixel).map { bytes[$0] }
    for y in 0..<(image.height / 2) {
      for x in 0..<image.width {
        let at = y * row + x * pixel
        if (0..<pixel).contains(where: { bytes[at + $0] != background[$0] }) { return true }
      }
    }
    return false
  }

  /// How tall the view wants to be at the popover's width.
  private func neededHeight(_ view: some View) -> CGFloat? {
    let renderer = ImageRenderer(content: view.frame(width: size.width))
    renderer.scale = 1
    return renderer.cgImage.map { CGFloat($0.height) }
  }

  private func sheet(
    _ item: SharedItem, _ replies: [String: ScriptedFetcher.Reply] = [:],
    extractor: (any RecipeExtracting)? = nil, estimator: (any RecipeAI)? = nil,
    keyMissing: Bool = false, duplicate: Bool = false,
    cover: ImportModel.CoverMode = .photo
  ) -> ShareSheetModel {
    ShareSheetModel(
      item: item,
      importer: ImportModel(
        fetcher: ScriptedFetcher(replies), extractor: extractor, estimator: estimator,
        options: ImportFixtures.quick,
        findDuplicate: { _ in duplicate ? ImportReview.Duplicate(id: UUID(), title: "Tacos") : nil
        },
        cover: cover),
      finishedFolder: finished, inboxFolder: drafts, closeDelay: .seconds(60),
      keyMissing: { keyMissing }, close: { _ in })
  }

  /// A recipe with everything the summary can show, and then some: a title that wraps, a note
  /// on the lines to check, the rough note and many lines.
  private func longRecipe() -> ExtractedRecipe {
    ExtractedRecipe(
      title: "Slow-roasted halloumi, hot honey and charred sweetcorn grain bowls for a crowd",
      servings: 6, totalMinutes: 95, tags: [],
      ingredients: (1...30).map {
        ExtractedLine(
          line: "\($0) g of an ingredient with a rather long name, finely chopped",
          section: $0 < 15 ? "For the bowls" : "To finish", unsure: $0 % 7 == 0)
      },
      steps: (1...20).map {
        ExtractedStep(
          text: "Step \($0): do the thing for a good while, then leave it be.", section: nil,
          unsure: $0 == 3)
      })
  }

  /// Every state the sheet can be in, by name.
  private func states() async -> [(String, ShareSheetModel)] {
    let tacos = [
      ImportFixtures.tacosLink: ImportFixtures.tacos(nutrition: true, image: true),
      ImportFixtures.tacosImage: ScriptedFetcher.Reply.image(ImportFixtures.imageData(64, 48)),
    ]
    let reading = sheet(
      SharedItem(url: ImportFixtures.tacosLink), [ImportFixtures.tacosLink: .hold])
    let plain = sheet(
      SharedItem(url: ImportFixtures.tacosLink),
      [ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)])
    let everything = sheet(
      SharedItem(url: ImportFixtures.tacosLink), tacos, duplicate: true, cover: .sheetThumbnail)
    let rough = sheet(
      SharedItem(url: "https://www.instagram.com/reel/Cabc123/", text: "Halloumi bowls"),
      extractor: ScriptedExtractor(recipe: longRecipe(), rough: true))
    let saved = sheet(
      SharedItem(url: ImportFixtures.tacosLink),
      [ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)])
    let sent = sheet(SharedItem(url: "https://down.example/a"))
    let noKey = sheet(
      SharedItem(url: ImportFixtures.soupLink),
      [ImportFixtures.soupLink: .html("<article><p>A story.</p></article>")],
      extractor: ScriptedExtractor(failing: .missingKey), keyMissing: true)
    let unreadable = sheet(SharedItem(url: "https://down.example/a"))
    let nothing = sheet(SharedItem(url: "", text: ""))

    for model in [reading, plain, everything, rough, saved, noKey, unreadable, nothing] {
      model.start()
    }
    for model in [plain, everything, rough, saved, noKey, unreadable] {
      await model.finished()
    }
    saved.save()
    sent.sendToCauldron()
    return [
      ("reading", reading), ("ready", plain), ("ready with everything", everything),
      ("ready, rough and long", rough), ("saved", saved), ("sent", sent), ("no key", noKey),
      ("unreadable", unreadable), ("nothing to read", nothing),
    ]
  }

  @Test func everyStateIsTheStateItShouldBe() async throws {
    let phases = await states().map { name, model in (name, model.phase) }
    func kind(_ phase: ShareSheetModel.Phase) -> String {
      switch phase {
      case .reading: "reading"
      case .ready: "ready"
      case .saved: "saved"
      case .sent: "sent"
      case .failed(let notice): "failed \(notice.kind)"
      }
    }
    #expect(
      phases.map { kind($0.1) } == [
        "reading", "ready", "ready", "ready", "saved", "sent", "failed noKey",
        "failed unreadable", "failed other",
      ])
    if case .ready(let review) = phases[2].1 {
      #expect(review.duplicate && review.thumbnail != nil && review.macros != nil)
    } else {
      Issue.record("the full sheet should be ready")
    }
    if case .ready(let review) = phases[3].1 {
      #expect(review.rough && review.linesToCheck > 0)
    } else {
      Issue.record("the rough sheet should be ready")
    }
    for (_, model) in await states() where model.phase == .reading { model.cancel() }
  }

  @Test func everyStateDrawsAtThePopoversSizeInBothAppearances() async throws {
    let all = await states()
    for (name, model) in all {
      for scheme in [ColorScheme.light, .dark] {
        for unfolded in [false, true] {
          let drawn = image(ShareSheetView(model: model, unfolded: unfolded), scheme: scheme)
          #expect(drawn != nil, "\(name) in \(scheme), unfolded \(unfolded)")
          if let drawn {
            // The popover's shape, at whatever scale the display draws it.
            #expect(drawn.width * Int(size.height) == drawn.height * Int(size.width))
            #if os(macOS)
              // iPhone's `ImageRenderer` leaves a scroll view's contents out, so only the Mac
              // is drawn for real.
              #expect(hasContent(drawn), "\(name) in \(scheme), unfolded \(unfolded) is blank")
            #endif
          }
        }
      }
    }
    for (_, model) in all where model.phase == .reading { model.cancel() }
  }

  @Test func theStatesThatDontScrollFitInsideThePopover() async throws {
    let all = await states()
    for (name, model) in all {
      switch model.phase {
      case .ready: continue
      default:
        let needed = try #require(neededHeight(ShareSheetView(model: model)), "\(name)")
        #expect(needed <= size.height, "\(name) needs \(needed) of \(size.height)")
      }
    }
    for (_, model) in all where model.phase == .reading { model.cancel() }
  }

  @Test func theExtensionsOwnNothingToShareNoticeFitsToo() throws {
    let notice = ShareConfirmation(outcome: .failed(Copy.importNative.nothingToSend.text))
    for scheme in [ColorScheme.light, .dark] {
      #expect(image(notice, scheme: scheme) != nil)
    }
    #expect(try #require(neededHeight(notice)) <= size.height)
  }
}

/// What each look at the finished-recipe folder came to, from a task that isn't the test's.
private actor Looks {
  private(set) var count = 0
  private(set) var added = 0
  private(set) var ended = false

  func end() { ended = true }

  func add(_ added: Int) {
    count += 1
    self.added += added
  }
}
