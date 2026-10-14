import CauldronKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Cauldron

/// What the share extension leaves, how the app routes it and queues it, and how the extension
/// reads what the share sheet gives it. Nothing here touches the real inbox or the network.
@MainActor
@Suite("Shared imports")
struct SharedImportTests {
  private let reel = "https://www.instagram.com/reel/Cabc123/"
  private let tiktok = "https://www.tiktok.com/@ada/video/7234567890123456789"
  private let caption = "Garlic pasta: boil 200g spaghetti. Fry 4 cloves garlic in oil. Toss."

  // MARK: Routes

  @Test func aWebLinkTakesTheLinkPathWhateverTextCameWithIt() {
    #expect(
      SharedImportRoute(SharedItem(url: "https://cook.example/soup"))
        == .link(
          "https://cook.example/soup"))
    // Safari shares the page's title as text; the page is what is read.
    #expect(
      SharedImportRoute(SharedItem(url: "https://cook.example/soup", text: "Soup - Cook"))
        == .link("https://cook.example/soup"))
  }

  @Test func aPostWithItsCaptionTakesThePastedTextPathAndKeepsThePost() {
    #expect(
      SharedImportRoute(SharedItem(url: reel, text: caption)) == .caption(caption, post: reel))
    #expect(
      SharedImportRoute(SharedItem(url: tiktok, text: caption)) == .caption(caption, post: tiktok))
  }

  @Test func theLinkInsideACaptionIsTakenOutOfIt() {
    let item = SharedItem(url: tiktok, text: "\(caption) \(tiktok)")
    #expect(SharedImportRoute(item) == .caption(caption, post: tiktok))
  }

  @Test func aPostWithNoCaptionTakesTheLinkPath() {
    #expect(SharedImportRoute(SharedItem(url: reel)) == .link(reel))
    #expect(SharedImportRoute(SharedItem(url: reel, text: "  \n")) == .link(reel))
    // The text is only the link again.
    #expect(SharedImportRoute(SharedItem(url: reel, text: reel)) == .link(reel))
  }

  @Test func textAloneTakesThePastePathUnlessItIsOnlyALink() {
    #expect(
      SharedImportRoute(SharedItem(text: "  2 eggs. Fry them. ")) == .text("2 eggs. Fry them."))
    #expect(
      SharedImportRoute(SharedItem(text: " https://cook.example/soup\n"))
        == .link(
          "https://cook.example/soup"))
    #expect(
      SharedImportRoute(SharedItem(text: "Try https://cook.example/soup tonight"))
        == .text("Try https://cook.example/soup tonight"))
  }

  @Test func anEmptyItemHasNoRoute() {
    #expect(SharedImportRoute(SharedItem()) == nil)
    #expect(SharedImportRoute(SharedItem(url: " ", text: "\n ")) == nil)
  }

  // MARK: The flow

  private func model(_ fetcher: ScriptedFetcher, extractor: (any RecipeExtracting)? = nil)
    -> ImportModel
  {
    ImportModel(fetcher: fetcher, extractor: extractor, options: ImportFixtures.quick)
  }

  @Test func aSharedLinkRunsLikeATypedOne() async throws {
    let fetcher = ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)])
    let flow = model(fetcher)
    flow.start(sharing: .link(ImportFixtures.tacosLink))
    #expect(flow.phase == .working)
    await flow.finished()
    guard case .ready(let review) = flow.phase else {
      Issue.record("should be ready: \(flow.phase)")
      return
    }
    #expect(review.draft.title == "Smoky black bean tacos")
    #expect(review.draft.sourceURL == ImportFixtures.tacosLink)
  }

  @Test func aSharedLinkThatCantBeReadOffersThePasteFallback() async throws {
    let flow = model(ScriptedFetcher(["https://down.example/a": .fail(.status(404))]))
    flow.start(sharing: .link("https://down.example/a"))
    await flow.finished()
    guard case .failed(let notice) = flow.phase else {
      Issue.record("should fail: \(flow.phase)")
      return
    }
    #expect(notice.canPaste)
  }

  @Test func aSharedLinkAlreadyInTheBoxIsFlaggedAsADuplicate() async throws {
    let flow = ImportModel(
      fetcher: ScriptedFetcher([ImportFixtures.tacosLink: ImportFixtures.tacos(image: false)]),
      extractor: nil, options: ImportFixtures.quick,
      findDuplicate: { _ in ImportReview.Duplicate(id: UUID(), title: "Tacos") })
    flow.start(sharing: .link(ImportFixtures.tacosLink))
    await flow.finished()
    guard case .ready(let review) = flow.phase else {
      Issue.record("should be ready: \(flow.phase)")
      return
    }
    #expect(review.duplicate?.title == "Tacos")
  }

  @Test func aCaptionIsReadAsPastedTextWithThePostAsItsSource() async throws {
    let fetcher = ScriptedFetcher()
    let extractor = ScriptedExtractor(recipe: readRecipe(title: "Garlic pasta"))
    let flow = model(fetcher, extractor: extractor)
    flow.start(sharing: .caption(caption, post: reel))
    await flow.finished()
    guard case .ready(let review) = flow.phase else {
      Issue.record("should be ready: \(flow.phase)")
      return
    }
    // No request went out for the post: the caption is all that was read.
    #expect(fetcher.requests.isEmpty)
    #expect(extractor.inputs.count == 1)
    #expect(review.draft.title == "Garlic pasta")
    #expect(review.draft.sourceURL == "https://www.instagram.com/reel/Cabc123")
    #expect(review.draft.imported?.platform == .instagram)
  }

  @Test func sharedTextWithNoLinkHasNoSource() async throws {
    let flow = model(ScriptedFetcher(), extractor: ScriptedExtractor(recipe: readRecipe()))
    flow.start(sharing: .text(caption))
    await flow.finished()
    guard case .ready(let review) = flow.phase else {
      Issue.record("should be ready: \(flow.phase)")
      return
    }
    #expect(review.draft.sourceURL.isEmpty)
  }

  @Test func aSharedItemNeverReplacesWhatTheCookHasTyped() {
    let flow = model(ScriptedFetcher())
    flow.text = "my own notes"
    flow.start(sharing: .link("https://cook.example/soup"))
    #expect(flow.phase == .editing)
    #expect(flow.link.isEmpty && flow.text == "my own notes")
  }

  // MARK: The queue

  private func inbox() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "SharedImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func files(in folder: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: folder.path())) ?? []
  }

  @Test func itemsAreTakenOutOfTheInboxAndQueueOldestFirst() throws {
    let folder = try inbox()
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = Date.now
    try ShareInbox.add(
      SharedItem(url: "https://b.example/two", sharedAt: now.addingTimeInterval(10)), in: folder)
    try ShareInbox.add(SharedItem(text: "1 egg. Fry it.", sharedAt: now), in: folder)
    try ShareInbox.add(SharedItem(), in: folder)

    let queue = SharedImportQueue(folder: folder, enabled: true)
    queue.pickUp()
    #expect(files(in: folder).isEmpty)
    // The empty item is dropped.
    #expect(queue.waiting == 2)

    #expect(queue.next() == .text("1 egg. Fry it."))
    queue.pickUp()
    #expect(queue.waiting == 1)
    #expect(queue.next() == .link("https://b.example/two"))
    #expect(queue.next() == nil)
  }

  @Test func itemsOpenOneAtATimeAndTheNextWaitsForTheSheetToClose() throws {
    let folder = try inbox()
    defer { try? FileManager.default.removeItem(at: folder) }
    try ShareInbox.add(SharedItem(text: "first", sharedAt: .now), in: folder)
    try ShareInbox.add(SharedItem(text: "second", sharedAt: .now.addingTimeInterval(1)), in: folder)
    let queue = SharedImportQueue(folder: folder, enabled: true)
    queue.pickUp()
    #expect(queue.readyToOpen)

    #expect(queue.next() == .text("first"))
    queue.importOpen = true
    #expect(queue.waiting == 1)
    #expect(!queue.readyToOpen)
    #expect(queue.next() == nil)

    queue.importOpen = false
    #expect(queue.readyToOpen)
    #expect(queue.next() == .text("second"))
    #expect(queue.waiting == 0 && !queue.readyToOpen)
  }

  @Test func anItemThatArrivesDuringAnImportOrAnEditorWaits() throws {
    let folder = try inbox()
    defer { try? FileManager.default.removeItem(at: folder) }
    let queue = SharedImportQueue(folder: folder, enabled: true)
    queue.importOpen = true
    try ShareInbox.add(SharedItem(text: "later"), in: folder)
    queue.pickUp()
    #expect(queue.waiting == 1 && !queue.readyToOpen && queue.next() == nil)

    queue.importOpen = false
    let editor = UUID()
    queue.editorOpened(editor)
    #expect(!queue.readyToOpen && queue.next() == nil)
    // Closing an editor twice, or one that never opened, changes nothing.
    queue.editorClosed(UUID())
    #expect(!queue.readyToOpen)
    queue.editorClosed(editor)
    queue.editorClosed(editor)
    #expect(queue.readyToOpen)
    #expect(queue.next() == .text("later"))
  }

  @Test func nothingIsPickedUpWhenItIsSwitchedOff() throws {
    let folder = try inbox()
    defer { try? FileManager.default.removeItem(at: folder) }
    try ShareInbox.add(SharedItem(text: "waiting"), in: folder)
    let queue = SharedImportQueue(folder: folder, enabled: false)
    queue.pickUp()
    #expect(queue.waiting == 0)
    #expect(files(in: folder).count == 1)
  }

  // MARK: The extension's reading

  private func item(_ providers: [NSItemProvider], contentText: String? = nil) -> NSExtensionItem {
    let item = NSExtensionItem()
    item.attachments = providers
    if let contentText { item.attributedContentText = NSAttributedString(string: contentText) }
    return item
  }

  private func link(_ string: String) -> NSItemProvider {
    NSItemProvider(item: URL(string: string)! as NSURL, typeIdentifier: UTType.url.identifier)
  }

  private func text(_ string: String) -> NSItemProvider {
    NSItemProvider(item: string as NSString, typeIdentifier: UTType.plainText.identifier)
  }

  @Test func theExtensionKeepsALink() async {
    let read = await SharedItemReader.read([item([link("https://cook.example/soup")])])
    #expect(read?.url == "https://cook.example/soup")
    #expect(read?.text == nil)
  }

  @Test func theExtensionReadsEveryShapeAProviderHandsOver() async {
    // The same link as a URL, a string and bytes; text as a string and as an attributed string.
    let address = "https://cook.example/soup"
    for shape: any NSSecureCoding in [
      URL(string: address)! as NSURL, address as NSString, Data(address.utf8) as NSData,
    ] {
      let provider = NSItemProvider(item: shape, typeIdentifier: UTType.url.identifier)
      #expect(await SharedItemReader.read([item([provider])])?.url == address)
    }
    let attributed = NSItemProvider(
      item: NSAttributedString(string: caption), typeIdentifier: UTType.plainText.identifier)
    #expect(await SharedItemReader.read([item([attributed])])?.text == caption)
  }

  @Test func theExtensionReadsAProviderMadeFromAnObject() async {
    // Made this way the provider hands over archived bytes on a phone and UTF-8 on a Mac.
    let provider = NSItemProvider(object: URL(string: reel)! as NSURL)
    #expect(await SharedItemReader.read([item([provider])])?.url == reel)
    let words = NSItemProvider(object: caption as NSString)
    #expect(await SharedItemReader.read([item([words])])?.text == caption)
  }

  @Test func theExtensionKeepsTextAlone() async {
    let read = await SharedItemReader.read([item([text(caption)])])
    #expect(read?.text == caption)
    #expect(read?.url == nil)
  }

  @Test func theExtensionKeepsALinkAndItsTextTogether() async {
    let read = await SharedItemReader.read([item([link(reel), text(caption)])])
    #expect(read?.url == reel && read?.text == caption)
    let reversed = await SharedItemReader.read([item([text(caption)]), item([link(reel)])])
    #expect(reversed?.url == reel && reversed?.text == caption)
  }

  @Test func theExtensionTakesTheFirstLinkAndTheFirstText() async {
    let read = await SharedItemReader.read([
      item([link("https://a.example/one"), link("https://b.example/two"), text("one"), text("two")])
    ])
    #expect(read?.url == "https://a.example/one" && read?.text == "one")
  }

  @Test func theExtensionIgnoresALinkThatIsNotOnTheWeb() async {
    #expect(await SharedItemReader.read([item([link("mailto:ada@example.com")])]) == nil)
    #expect(await SharedItemReader.read([item([link("file:///tmp/recipe.pdf")])]) == nil)
    let read = await SharedItemReader.read([item([link("ftp://host/x"), text(caption)])])
    #expect(read?.url == nil && read?.text == caption)
  }

  @Test func theExtensionFallsBackToTheItemsOwnText() async {
    let read = await SharedItemReader.read([item([link(reel)], contentText: caption)])
    #expect(read?.url == reel && read?.text == caption)
  }

  @Test func theExtensionKeepsNothingWhenThereIsNothing() async {
    #expect(await SharedItemReader.read([]) == nil)
    #expect(await SharedItemReader.read([item([])]) == nil)
    #expect(await SharedItemReader.read([item([text("  \n ")], contentText: " ")]) == nil)
  }

  // MARK: The extension's look

  @Test func theAppFolderIsFoundFromTheExtensionOnBothPlatforms() {
    let iPhone = URL(
      filePath:
        "/private/var/containers/Bundle/Application/X/Cauldron.app/PlugIns/CauldronShare.appex")
    #expect(ShareFonts.containingApp(of: iPhone)?.lastPathComponent == "Cauldron.app")
    let mac = URL(filePath: "/Applications/Cauldron.app/Contents/PlugIns/CauldronShare.appex")
    #expect(ShareFonts.containingApp(of: mac)?.lastPathComponent == "Cauldron.app")
    let app = URL(filePath: "/Applications/Cauldron.app")
    #expect(ShareFonts.containingApp(of: app) == app)
    #expect(ShareFonts.containingApp(of: URL(filePath: "/tmp/other/place")) == nil)
  }

  @Test func theBrandsTypeCanBeLoadedFromTheApp() {
    // Under test the app is the main bundle, as it is the extension's container on a device.
    #expect(ShareFonts.isAvailable)
  }
}
