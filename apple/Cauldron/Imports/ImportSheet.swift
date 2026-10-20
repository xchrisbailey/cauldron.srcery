import CauldronImports
import CauldronKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Distill: a link or pasted text in, and the draft opens in the editor to review. One sheet
/// holds all of it, so the editor replaces the form in the same sheet; Cancel in the editor
/// closes the lot and nothing has been stored.
struct ImportSheet: View {
  let model: ImportModel
  /// How many more shared items wait for this one to finish, shown at the foot of the sheet.
  var waiting = 0
  /// Called with the saved recipe, just before the sheet closes.
  var onSaved: (RecipeRecord) -> Void = { _ in }
  /// Opens the recipe the draft duplicates; the sheet is closed by the caller.
  var onOpenDuplicate: (UUID) -> Void = { _ in }

  var body: some View {
    Group {
      if case .ready(let review) = model.phase {
        RecipeEditorSheet(
          recipe: nil, importing: review, onSaved: onSaved, onOpenDuplicate: onOpenDuplicate)
      } else {
        ImportStartSheet(model: model)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if waiting > 0 {
        if case .ready = model.phase {} else { SharedWaitingBadge(count: waiting) }
      }
    }
    // Closed any way at all, such as by a swipe: stop what is running.
    .onDisappear { model.discard() }
  }
}

/// "2 more shared": the items from the share sheet that open when this one is done.
struct SharedWaitingBadge: View {
  let count: Int

  var body: some View {
    Text(verbatim: Copy.importNative.moreShared(count).text)
      .brandText(.control)
      .foregroundStyle(Brand.Colors.subtext)
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .background(Brand.Colors.mantle, in: Capsule())
      .overlay(Capsule().strokeBorder(Brand.Colors.surface0))
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .combine)
  }
}

/// The form, the wait and the failure: everything before there is a draft.
struct ImportStartSheet: View {
  @Bindable var model: ImportModel
  @Environment(\.dismiss) private var dismiss
  @Environment(RecipeAIService.self) private var ai: RecipeAIService?
  @FocusState private var focus: Field?
  /// What the photo section's controls switch on. They live here, on the stack, rather than in
  /// the section (see `ImportPhotoSection`).
  @State private var picked: [PhotosPickerItem] = []
  @State private var scanning = false
  @State private var choosingFiles = false

  private enum Field { case link, paste }

  var body: some View {
    // Modifiers that run work hang off the stack, not its content: inside it they crash an
    // `ImageRenderer` on iOS when the render is torn down, which is how the tests draw this.
    NavigationStack {
      content
        .navigationTitle(Copy.imports.title.text)
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button {
              model.discard()
              dismiss()
            } label: {
              Text(verbatim: Copy.recipeView.cancel.text)
            }
          }
        }
    }
    .onChange(of: picked) { _, items in
      guard !items.isEmpty else { return }
      picked = []
      Task {
        let loaded = await Self.images(of: items)
        await model.addPages(loaded.images)
        // Said after the pages are added, which clears the last message.
        if loaded.failed { model.reportPhotoProblem(PhotoError.unreadable.message) }
      }
    }
    #if os(iOS)
      .fullScreenCover(isPresented: $scanning) {
        DocumentScanner(
          onPages: { pages in
            scanning = false
            Task { await model.addPages(pages) }
          },
          // Closing the scanner is the cook's choice, not an error.
          onCancel: { scanning = false },
          onFail: {
            scanning = false
            model.reportPhotoProblem(Copy.importNative.scannerStopped)
          }
        )
        .ignoresSafeArea()
      }
    #endif
    #if os(macOS)
      .fileImporter(
        isPresented: $choosingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true
      ) { result in
        if case .success(let urls) = result { addFiles(urls) }
      }
      .dropDestination(for: URL.self) { urls, _ in
        guard model.phase == .editing else { return false }
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return false }
        addFiles(files)
        return true
      }
    #endif
    #if os(macOS)
      .frame(minWidth: 480, idealWidth: 540, minHeight: 520, idealHeight: 620)
    #endif
  }

  /// The bytes of what was picked from the library, and whether any of it couldn't be loaded.
  private static func images(of items: [PhotosPickerItem]) async -> (images: [Data], failed: Bool) {
    var images: [Data] = []
    var failed = false
    for item in items {
      if let data = try? await item.loadTransferable(type: Data.self) {
        images.append(data)
      } else {
        failed = true
      }
    }
    return (images, failed)
  }

  #if os(macOS)
    private func addFiles(_ urls: [URL]) {
      Task {
        let read = await ImageFiles.read(urls)
        await model.addPages(read.images)
        // Said after the pages are added, which clears the last message.
        if let problem = read.problem { model.reportPhotoProblem(problem.message) }
      }
    }
  #endif

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .editing, .ready: form
    case .working: working
    case .failed(let notice): failed(notice)
    }
  }

  // MARK: The form

  private var form: some View {
    List {
      if let ai, ai.status.needsAttention {
        Section {
          AIStatusLine(status: ai.status)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
        }
        .listRowBackground(Brand.Colors.mantle)
      }

      Section {
        if let kept = model.pastingFor {
          Text(verbatim: Copy.importNative.pastingFor(kept).text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
            .fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: Copy.imports.link.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
          TextField(
            "", text: $model.link, prompt: Text(verbatim: Copy.imports.linkPlaceholder.text)
          )
          .textFieldStyle(.plain)
          .brandText(.body)
          .focused($focus, equals: .link)
          .autocorrectionDisabled()
          #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
          #endif
          .onSubmit { model.start() }
          .disabled(model.pagesAreOn)
          .accessibilityLabel(Text(verbatim: Copy.imports.link.text))
          if let error = model.linkError {
            Text(verbatim: error.text).brandText(.control).foregroundStyle(Brand.Colors.heat)
          }
        }
      } footer: {
        Text(verbatim: Copy.imports.linkHint.text)
      }
      .listRowBackground(Brand.Colors.mantle)

      Section {
        ZStack(alignment: .topLeading) {
          TextEditor(text: $model.text)
            .scrollContentBackground(.hidden)
            .brandText(.body)
            .focused($focus, equals: .paste)
            .frame(minHeight: 180)
            .disabled(model.pasteIsOff || model.pagesAreOn)
            .accessibilityLabel(Text(verbatim: Copy.imports.orPaste.text))
          if model.text.isEmpty {
            Text(verbatim: Copy.imports.pastePlaceholder.text)
              .brandText(.body)
              .foregroundStyle(Brand.Colors.overlay1)
              .padding(.top, 8)
              .padding(.leading, 5)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .opacity(model.pasteIsOff || model.pagesAreOn ? 0.4 : 1)
      } header: {
        Text(verbatim: Copy.imports.orPaste.text)
      } footer: {
        Text(verbatim: Copy.imports.pasteHint.text)
      }
      .listRowBackground(Brand.Colors.mantle)

      ImportPhotoSection(
        model: model, picked: $picked, scanning: $scanning, choosingFiles: $choosingFiles)

      Section {
        if model.stopped {
          Text(verbatim: Copy.imports.stopped.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
        }
        Button {
          model.start()
        } label: {
          Text(verbatim: Copy.imports.distill.text)
        }
        .buttonStyle(RecipeActionButtonStyle(.primary))
        .disabled(!model.canStart)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
      }
      .listRowBackground(Brand.Colors.mantle)

      #if DEBUG
        ImportLiveChecksSection(model: model)
      #endif
    }
    #if os(iOS)
      .listStyle(.insetGrouped)
    #else
      .listStyle(.inset)
    #endif
    .scrollContentBackground(.hidden)
    .background(Brand.Colors.base)
    .foregroundStyle(Brand.Colors.ink)
    .defaultFocus($focus, model.pastingFor == nil && !model.prefersPaste ? .link : .paste)
  }

  // MARK: Working and failed

  private var working: some View {
    VStack(spacing: 20) {
      ProgressView()
      if let reading = model.reading {
        Text(verbatim: Copy.importNative.readingPages.text)
          .brandText(.body)
          .foregroundStyle(Brand.Colors.subtext)
        Text(verbatim: Copy.importNative.pageOf(reading.page, reading.of).text)
          .brandText(.quantity)
          .foregroundStyle(Brand.Colors.subtext)
      } else {
        Text(verbatim: Copy.imports.distilling.text)
          .brandText(.body)
          .foregroundStyle(Brand.Colors.subtext)
      }
      Button {
        model.stop()
      } label: {
        Text(verbatim: Copy.imports.stop.text)
      }
      .buttonStyle(RecipeActionButtonStyle())
      .frame(maxWidth: 240)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.Colors.base)
    .accessibilityElement(children: .contain)
  }

  private func failed(_ notice: ImportFailureNotice) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      if let ai, ai.status.needsAttention {
        AIStatusLine(status: ai.status)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
      }
      Text(verbatim: notice.message.text)
        .brandText(.body)
        .foregroundStyle(Brand.Colors.heat)
        .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: 10) {
        if notice.canRetry {
          Button {
            model.retry()
          } label: {
            Text(verbatim: Copy.imports.tryAgain.text)
          }
          .buttonStyle(RecipeActionButtonStyle(notice.canPaste ? .secondary : .primary))
        }
        if notice.canChangePhotos {
          Button {
            model.changePhotos()
          } label: {
            Text(verbatim: Copy.imports.tryAgain.text)
          }
          .buttonStyle(RecipeActionButtonStyle(.secondary))
        }
        if notice.canPaste {
          Button {
            model.pasteInstead()
          } label: {
            Text(verbatim: Copy.imports.pasteInstead.text)
          }
          .buttonStyle(RecipeActionButtonStyle(.primary))
        }
        Button {
          model.another()
        } label: {
          Text(verbatim: Copy.imports.another.text)
        }
        .buttonStyle(RecipeActionButtonStyle())
      }
      .frame(maxWidth: 320)
      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Brand.Colors.base)
  }
}
