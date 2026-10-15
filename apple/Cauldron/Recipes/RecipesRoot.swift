import CauldronKit
import SwiftData
import SwiftUI

/// The recipes section: the library as a list of cards with search and sort, and the recipe
/// beside it. Where there is room (a Mac, an iPad) the two sit side by side; on iPhone a recipe
/// opens over the list. The shell already has a sidebar, so this doesn't nest a split view in it.
struct RecipesRoot: View {
  @Query(filter: #Predicate<RecipeRecord> { $0.deletedAt == nil })
  private var recipes: [RecipeRecord]
  @State private var search = ""
  @State private var sort = RecipeSort.recent
  /// The recipe open beside the list.
  @State private var selection: UUID?
  /// The recipes open over the list, on iPhone.
  @State private var path: [UUID] = []
  @State private var banishing: RecipeRecord?
  /// Whether the editor is open on a new recipe.
  @State private var conjuring = false
  /// Distill, while its sheet is open.
  @State private var distilling: ImportModel?
  @Environment(\.modelContext) private var context
  @Environment(\.pageFetcher) private var fetcher
  @Environment(\.recipeTextReader) private var reader
  @Environment(RecipeAIService.self) private var ai: RecipeAIService?
  /// What was shared to Cauldron and waits to be imported; nil under test and in previews.
  @Environment(SharedImportQueue.self) private var sharing: SharedImportQueue?
  /// What the banner at the bottom says, and a count that restarts its timer.
  @State private var notice: RecipeNotice?
  @State private var noticeCount = 0
  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #else
    @Environment(\.openWindow) private var openWindow
    @FocusState private var searchFocused: Bool
  #endif

  private var sideBySide: Bool {
    #if os(iOS)
      horizontalSizeClass != .compact
    #else
      true
    #endif
  }

  var body: some View {
    Group {
      if sideBySide {
        split
      } else {
        stack
      }
    }
    .sheet(isPresented: $conjuring) {
      RecipeEditorSheet(recipe: nil) { open($0) }
    }
    .sheet(item: $distilling, onDismiss: { sharing?.importOpen = false }) { model in
      ImportSheet(
        model: model, waiting: sharing?.waiting ?? 0, onSaved: { open($0) },
        onOpenDuplicate: { id in
          distilling = nil
          if let existing = recipes.first(where: { $0.id == id }) { open(existing) }
        })
    }
    #if os(macOS)
      .focusedSceneValue(
        \.libraryCommands,
        LibraryCommands(
          newRecipe: { conjuring = true }, find: { searchFocused = true },
          importRecipe: startDistilling))
    #endif
    .overlay(alignment: .bottom) {
      if let notice {
        RecipeNoticeBanner(notice: notice, onUndo: undo)
          .padding(16)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    // Something shared waits for its turn: once nothing else is open, its import opens here.
    // The pause lets a sheet that has just closed finish going.
    .task(id: sharing?.readyToOpen ?? false) {
      guard sharing?.readyToOpen == true else { return }
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      startShared()
    }
    .task(id: noticeCount) {
      guard let shown = notice else { return }
      let seconds = shown.undoLabel == nil ? 3 : 6
      try? await Task.sleep(for: .seconds(seconds))
      if !Task.isCancelled { withAnimation { notice = nil } }
    }
    .confirmationDialog(
      Text(verbatim: banishing.map { Copy.recipes.banishConfirm($0.title).verb.text } ?? ""),
      isPresented: Binding(get: { banishing != nil }, set: { if !$0 { banishing = nil } }),
      titleVisibility: .visible, presenting: banishing
    ) { recipe in
      Button(role: .destructive) {
        banish(recipe)
      } label: {
        Text(verbatim: Copy.recipes.banishConfirm(recipe.title).verb.text)
      }
      Button(role: .cancel) {
      } label: {
        Text(verbatim: Copy.recipeView.cancel.text)
      }
    } message: { recipe in
      Text(verbatim: Copy.recipes.banishConfirm(recipe.title).confirm.text)
    }
  }

  // MARK: Layouts

  private var split: some View {
    HStack(spacing: 0) {
      library(opening: .beside)
        .frame(width: 380)
      Divider()
      detail(of: selection)
    }
    .background(Brand.Colors.base)
    .searchable(
      text: $search, placement: .automatic,
      prompt: Text(verbatim: Copy.library.searchPlaceholder.text)
    )
    #if os(macOS)
      .searchFocused($searchFocused)
    #endif
    .toolbar { libraryTools }
    .navigationTitle(AppDestination.recipes.title.text)
  }

  private var stack: some View {
    NavigationStack(path: $path) {
      library(opening: .over)
        .searchable(
          text: $search, placement: searchPlacement,
          prompt: Text(verbatim: Copy.library.searchPlaceholder.text)
        )
        .toolbar { libraryTools }
        .navigationTitle(AppDestination.recipes.title.text)
        .navigationDestination(for: UUID.self) { id in
          detail(of: id)
            .navigationTitle(recipes.first { $0.id == id }?.title ?? "")
        }
    }
  }

  private var searchPlacement: SearchFieldPlacement {
    #if os(iOS)
      .navigationBarDrawer(displayMode: .always)
    #else
      .automatic
    #endif
  }

  private var libraryTools: some ToolbarContent {
    ToolbarItemGroup {
      Button {
        conjuring = true
      } label: {
        Label {
          Text(verbatim: Copy.recipes.conjure.text)
        } icon: {
          Image(systemName: "plus")
        }
      }
      Button(action: startDistilling) {
        Label {
          Text(verbatim: Copy.recipes.distillFromLink.text)
        } icon: {
          Image(systemName: "square.and.arrow.down")
        }
      }
      Menu {
        Picker(selection: $sort) {
          ForEach(RecipeSort.allCases) { choice in
            Text(verbatim: choice.label.text).tag(choice)
          }
        } label: {
          Text(verbatim: Copy.library.sort.text)
        }
      } label: {
        Label {
          Text(verbatim: Copy.library.sort.text)
        } icon: {
          Image(systemName: "arrow.up.arrow.down")
        }
      }
    }
  }

  // MARK: Library

  /// Where a tapped card opens its recipe.
  private enum Opening { case beside, over }

  @ViewBuilder
  private func library(opening: Opening) -> some View {
    let visible = RecipeLibrary.visible(recipes, matching: search, sort: sort)
    if recipes.isEmpty {
      EmptyState(systemImage: AppDestination.recipes.systemImage, message: Copy.recipes.empty)
    } else if visible.isEmpty {
      EmptyState(systemImage: "magnifyingglass", message: Copy.library.noResults)
    } else {
      list(visible, opening: opening)
    }
  }

  @ViewBuilder
  private func list(_ visible: [RecipeRecord], opening: Opening) -> some View {
    switch opening {
    case .beside:
      // The list's selection is the recipe shown beside it.
      macLibraryMenus(
        List(selection: $selection) { rows(visible, opening: opening) }
          .libraryListStyle())
    case .over:
      // No selection here: a list with a selection binding, even a constant one, takes the
      // tap for selecting, so a link in the row never fires. Each row pushes its recipe.
      List { rows(visible, opening: opening) }
        .libraryListStyle()
    }
  }

  private func rows(_ visible: [RecipeRecord], opening: Opening) -> some View {
    ForEach(visible) { recipe in
      row(recipe, opening: opening)
    }
  }

  @ViewBuilder
  private func row(_ recipe: RecipeRecord, opening: Opening) -> some View {
    switch opening {
    case .beside:
      card(recipe, selected: selection == recipe.id).tag(recipe.id)
    case .over:
      Button {
        path.append(recipe.id)
      } label: {
        card(recipe, selected: false)
      }
      .buttonStyle(.plain)
    }
  }

  private func card(_ recipe: RecipeRecord, selected: Bool) -> some View {
    RecipeCardView(recipe: recipe, selected: selected)
      .contentShape(Rectangle())
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
      .swipeActions(edge: .trailing) { banishButton(recipe) }
      #if os(iOS)
        .contextMenu { banishButton(recipe) }
      #else
        // Drag it onto a day in the week, in another window.
        .draggable(RecipeDrag(id: recipe.id))
      #endif
  }
}

extension View {
  fileprivate func libraryListStyle() -> some View {
    self
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
  }
}

extension RecipesRoot {
  fileprivate func macLibraryMenus(_ list: some View) -> some View {
    list
      #if os(macOS)
        // Double-click opens a recipe in a window of its own; so does the menu.
        .contextMenu(forSelectionType: UUID.self) { ids in
          if let id = ids.first, let recipe = recipes.first(where: { $0.id == id }) {
            Button {
              openWindow(value: RecipeWindowRequest(recipeID: id))
            } label: {
              Text(verbatim: Copy.macMenu.openInNewWindow.text)
            }
            Divider()
            banishButton(recipe)
          }
        } primaryAction: { ids in
          for id in ids { openWindow(value: RecipeWindowRequest(recipeID: id)) }
        }
        .onDeleteCommand {
          if let id = selection, let recipe = recipes.first(where: { $0.id == id }) {
            banishing = recipe
          }
        }
      #endif
  }

  private func banishButton(_ recipe: RecipeRecord) -> some View {
    Button(role: .destructive) {
      banishing = recipe
    } label: {
      Text(verbatim: Copy.recipes.banishConfirm(recipe.title).verb.text)
    }
    .tint(Brand.Colors.heat)
  }

  // MARK: Detail

  @ViewBuilder
  private func detail(of id: UUID?) -> some View {
    if let id, let recipe = recipes.first(where: { $0.id == id }) {
      RecipeDetailView(recipe: recipe) { banishing = recipe }
        .id(recipe.id)
    } else {
      Image(systemName: AppDestination.recipes.systemImage)
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(Brand.Colors.magic)
        .accessibilityHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.Colors.base)
    }
  }

  /// Opens Distill on a clean form.
  private func startDistilling() {
    guard distilling == nil else { return }
    sharing?.importOpen = true
    distilling = makeImportModel()
  }

  /// Opens Distill running the next thing that was shared, if it may open now.
  private func startShared() {
    guard distilling == nil, let route = sharing?.next() else { return }
    let model = makeImportModel()
    model.start(sharing: route)
    sharing?.importOpen = true
    distilling = model
  }

  private func makeImportModel() -> ImportModel {
    let context = context
    return ImportModel(
      fetcher: fetcher, extractor: ai?.extractor, estimator: ai?.estimator, reader: reader,
      findDuplicate: { links in
        let saved = (try? context.fetch(FetchDescriptor<RecipeRecord>())) ?? []
        return DuplicateLinks.find(in: saved, links: links).map {
          ImportReview.Duplicate(id: $0.id, title: $0.title)
        }
      })
  }

  /// Shows a recipe that was just made, whatever the search says.
  private func open(_ recipe: RecipeRecord) {
    search = ""
    if sideBySide { selection = recipe.id } else { path = [recipe.id] }
  }

  private func banish(_ recipe: RecipeRecord) {
    RecipeLibrary.banish(recipe)
    if selection == recipe.id { selection = nil }
    path.removeAll { $0 == recipe.id }
    banishing = nil
    show(.banished(recipe))
  }

  /// Takes back the banish the banner is offering.
  private func undo() {
    guard case .banished(let recipe) = notice else { return }
    RecipeLibrary.restore(recipe)
    show(.restored)
  }

  private func show(_ next: RecipeNotice) {
    withAnimation { notice = next }
    noticeCount += 1
    AccessibilityNotification.Announcement(next.text).post()
  }
}

#if DEBUG
  #Preview("Library") {
    let container = RecipePreviewData.container()
    RecipesRoot()
      .modelContainer(container)
  }
#endif
