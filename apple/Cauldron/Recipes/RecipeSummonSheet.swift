import CauldronKit
import SwiftData
import SwiftUI

/// ⌘K: type to find a recipe and open it. Arrow keys move through the matches and Return opens
/// the one that is lit; the first is lit until an arrow key says otherwise. A match is by name,
/// ingredient, tag or description, as in the library's search, with a title that starts with
/// what was typed first. What needed a typo goes after those, under Close matches, each with a
/// short line saying what it matched.
struct RecipeSummonSheet: View {
  /// The recipes that can be found; the sheet leaves out any that were banished.
  let recipes: [RecipeRecord]
  let onOpen: (RecipeRecord) -> Void
  /// The index for `recipes`; the library passes the one it keeps, so opening the sheet doesn't
  /// build another. Without one the sheet keeps a cache of its own for as long as it is open.
  let searchCache: RecipeSearchCache?
  @State private var ownCache = RecipeSearchCache()
  @State private var query = ""
  @State private var lit: UUID?
  @FocusState private var focused: Bool

  init(
    recipes: [RecipeRecord], searchCache: RecipeSearchCache? = nil,
    onOpen: @escaping (RecipeRecord) -> Void
  ) {
    self.recipes = recipes
    self.searchCache = searchCache
    self.onOpen = onOpen
  }

  private var results: [RecipeMatch] {
    RecipeLibrary.summonMatches(
      recipes, matching: query, index: (searchCache ?? ownCache).index(for: recipes))
  }

  var body: some View {
    let results = results
    let current = (results.first { $0.id == lit } ?? results.first)?.recipe
    VStack(alignment: .leading, spacing: 12) {
      TextField(Copy.recipes.summon.text, text: $query)
        .brandText(.body)
        .textFieldStyle(.plain)
        .padding(12)
        .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.Colors.surface0, lineWidth: 1))
        .focused($focused)
        .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
        .onSubmit { if let current { onOpen(current) } }
        .onKeyPress(.downArrow) { step(1, in: results, from: current) }
        .onKeyPress(.upArrow) { step(-1, in: results, from: current) }
        .accessibilityLabel(Text(verbatim: Copy.recipes.summon.text))
      Text(verbatim: heading(results))
        .brandText(.control)
        .foregroundStyle(Brand.Colors.subtext)
      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(results.exact) { match in
            row(match, lit: match.id == current?.id)
          }
          CloseMatchesSection(matches: results, layout: .stack) { match in
            row(match, lit: match.id == current?.id)
          }
        }
      }
      #if os(macOS)
        Text(verbatim: Copy.library.summonHelp.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
      #endif
    }
    .padding(16)
    .background(Brand.Colors.base)
    #if os(macOS)
      .frame(minWidth: 460, minHeight: 360)
    #else
      .presentationDetents([.medium, .large])
    #endif
    .onAppear { focused = true }
    .onChange(of: query) { lit = nil }
  }

  /// What sits above the matches: how to search until something is typed, then what the
  /// matches are, or that there are none.
  private func heading(_ results: [RecipeMatch]) -> String {
    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return Copy.recipes.summonHint.text
    }
    return (results.isEmpty ? Copy.library.noResults : Copy.library.results).text
  }

  private func row(_ match: RecipeMatch, lit: Bool) -> some View {
    let recipe = match.recipe
    return Button {
      onOpen(recipe)
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: recipe.title)
            .brandText(.body)
            .lineLimit(1)
          if let reason = match.shortReasonLine {
            MatchReasonLine(text: reason, lines: 1)
          }
        }
        Spacer(minLength: 0)
        if let time = RecipeTimes(recipe).total {
          Text(verbatim: time)
            .brandText(.quantity)
            .foregroundStyle(Brand.Colors.subtext)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        lit ? Brand.Colors.magic.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8)
      )
      .contentShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(lit ? .isSelected : [])
  }

  private func step(
    _ delta: Int, in results: [RecipeMatch], from current: RecipeRecord?
  ) -> KeyPress.Result {
    guard !results.isEmpty else { return .ignored }
    let index = results.firstIndex { $0.id == current?.id } ?? 0
    lit = results[(index + delta + results.count) % results.count].id
    return .handled
  }
}

#if DEBUG
  #Preview("Summon") {
    let container = RecipePreviewData.container()
    RecipeSummonPreview().modelContainer(container)
  }

  private struct RecipeSummonPreview: View {
    @Query private var recipes: [RecipeRecord]
    var body: some View { RecipeSummonSheet(recipes: recipes) { _ in } }
  }
#endif
