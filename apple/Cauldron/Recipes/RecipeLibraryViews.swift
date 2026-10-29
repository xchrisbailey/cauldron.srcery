import CauldronKit
import SwiftUI

/// What the library says when a search or a tag matches no recipe, with the way back.
struct NoMatchesView: View {
  /// How many recipes are still being read for search, while that is going on (the runner's
  /// `stillReading`), and what is typed: with both, the view says so, since the recipe that
  /// would match may be one of them.
  var stillReading: Int?
  var search = ""
  let onClear: () -> Void

  /// The line about recipes still being read, under a search that found nothing.
  var readingNotice: CopyString? {
    RecipeLibrary.readingNotice(stillReading: stillReading, search: search)
  }

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(Brand.Colors.magic)
        .accessibilityHidden(true)
      Text(verbatim: Copy.library.noMatches.text)
        .brandText(.body)
        .foregroundStyle(Brand.Colors.subtext)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
      if let notice = readingNotice {
        Text(verbatim: notice.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 360)
      }
      Button(action: onClear) {
        Text(verbatim: Copy.library.clearFilters.text)
      }
      .buttonStyle(.brandProminent)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.Colors.base)
  }
}

/// The heading over the results that needed forgiving: a typo, another name or a missing word.
/// Library lists show it as a section header and ⌘K as a label.
struct CloseMatchesHeader: View {
  var body: some View {
    Text(verbatim: Copy.libraryNative.closeMatches.text)
      .brandText(.control)
      .foregroundStyle(Brand.Colors.subtext)
      .textCase(nil)
      .accessibilityAddTraits(.isHeader)
  }
}

/// The close and partial matches under their Close matches heading, or nothing when there are
/// none. Every surface that lists matches uses it after its exact rows: library lists, the Log
/// and Stir sheets lay it out as a list section, ⌘K as rows in a stack.
struct CloseMatchesSection<Row: View>: View {
  enum Layout {
    /// A `Section` with the heading as its header, for a `List`.
    case section
    /// The heading, then the rows, for a stack.
    case stack
  }

  /// The matches as found; the exact ones are left to the caller.
  let matches: [RecipeMatch]
  var layout = Layout.section
  @ViewBuilder let row: (RecipeMatch) -> Row

  var body: some View {
    let close = matches.close
    if !close.isEmpty {
      switch layout {
      case .section:
        Section {
          ForEach(close) { match in row(match) }
        } header: {
          CloseMatchesHeader()
        }
      case .stack:
        CloseMatchesHeader()
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 10)
          .padding(.top, 8)
        ForEach(close) { match in row(match) }
      }
    }
  }
}

/// The one line under a close match that says what it matched.
struct MatchReasonLine: View {
  let text: String
  var lines = 2

  var body: some View {
    Text(verbatim: text)
      .brandText(.control)
      .foregroundStyle(Brand.Colors.subtext)
      .lineLimit(lines)
      .multilineTextAlignment(.leading)
  }
}

/// The last line of a search's results while recipes are still being read for search.
struct SearchReadingFooter: View {
  let count: Int

  var body: some View {
    Text(verbatim: Copy.libraryNative.stillReading(count).text)
      .brandText(.control)
      .foregroundStyle(Brand.Colors.subtext)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A tag's new name. It stays open with what is wrong with the name until the name is good.
struct TagRenameSheet: View {
  /// The tag's name now.
  let name: String
  /// Renames the tag; what went wrong, or nil when it worked.
  let onRename: (String) -> RecipeTagRename.Failure?
  @State private var text = ""
  @State private var failure: RecipeTagRename.Failure?
  @FocusState private var focused: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(verbatim: Copy.libraryNative.renameTagTitle(name).text)
        .brandText(.section)
      TextField(Copy.libraryNative.renameTagField.text, text: $text)
        .brandText(.body)
        .textFieldStyle(.plain)
        .padding(12)
        .background(Brand.Colors.mantle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(failure == nil ? Brand.Colors.surface0 : Brand.Colors.heat, lineWidth: 1)
        )
        .focused($focused)
        .autocorrectionDisabled()
        .onSubmit(save)
        .onChange(of: text) { failure = nil }
      if let failure {
        Text(verbatim: failure.message.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.heat)
      }
      HStack {
        Spacer()
        Button(role: .cancel) {
          dismiss()
        } label: {
          Text(verbatim: Copy.recipeView.cancel.text)
        }
        .keyboardShortcut(.cancelAction)
        Button(action: save) {
          Text(verbatim: Copy.libraryNative.renameTagSave.text)
        }
        .buttonStyle(.brandProminent)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .background(Brand.Colors.base)
    #if os(macOS)
      .frame(minWidth: 380)
    #else
      .presentationDetents([.height(240)])
    #endif
    .onAppear {
      text = name
      focused = true
    }
  }

  private func save() {
    if let failure = onRename(text) {
      self.failure = failure
    } else {
      dismiss()
    }
  }
}
