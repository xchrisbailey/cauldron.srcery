import CauldronKit
import SwiftData
import SwiftUI

/// The add sheet's "Recipe" way in (#180): search your recipes and tap one (tap one), then Log it
/// (tap two) for one serving, or change the servings first. Banished recipes aren't offered.
/// The recipe's per-serving numbers are copied onto the entry, with a link back to it.
struct AddRecipeTab: View {
  nonisolated static let isAvailable = true

  let context: AddContext

  @Query(filter: #Predicate<RecipeRecord> { $0.deletedAt == nil })
  private var recipes: [RecipeRecord]
  @State private var query = ""
  @State private var searchCache = RecipeSearchCache()
  @State private var picked: RecipeRecord?

  var body: some View {
    if let picked {
      RecipeLogForm(
        recipe: picked, draft: RecipeLogDraft(slot: context.slot, day: context.day),
        onBack: { self.picked = nil },
        onLog: { draft in
          guard let new = draft.entry(for: picked) else { return Copy.tracker.targets.fixThese }
          return context.log([new])
        })
    } else {
      list
    }
  }

  private var list: some View {
    let matches = RecipePicker.found(
      recipes, query: query, index: searchCache.index(for: recipes))
    return List {
      Section {
        TextField(Copy.tracker.logRecipe.search.text, text: $query)
          .brandText(.body)
          .autocorrectionDisabled()
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif
          .listRowBackground(Brand.Colors.mantle)
      }
      Section {
        ForEach(matches.exact) { match in row(match) }
        if matches.isEmpty {
          Text(verbatim: Copy.week.noMatches.text)
            .brandText(.control)
            .foregroundStyle(Brand.Colors.subtext)
            .listRowBackground(Color.clear)
        }
      }
      let close = matches.close
      if !close.isEmpty {
        Section {
          ForEach(close) { match in row(match) }
        } header: {
          CloseMatchesHeader()
        }
      }
    }
    .scrollContentBackground(.hidden)
  }

  private func row(_ match: RecipeMatch) -> some View {
    Button {
      picked = match.recipe
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: match.recipe.title).brandText(.body)
        if let reason = match.reasonLine { MatchReasonLine(text: reason) }
        Text(verbatim: RecipePicker.detail(match.recipe))
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(Brand.Colors.mantle)
  }
}
