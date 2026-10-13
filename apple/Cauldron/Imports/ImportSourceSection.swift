import CauldronKit
import SwiftUI

/// The top of the editor for a draft from Distill (`Source` and the review line in the web
/// app's distill route): a warning when the on-device model read it, a line to check the
/// highlighted fields, where it came from, and the recipe already saved from the same link.
struct ImportSourceSection: View {
  let draft: RecipeDraft
  let imported: ImportedFrom
  let duplicate: ImportReview.Duplicate?
  let onOpenDuplicate: () -> Void

  private var link: URL? {
    let address = draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    return address.isEmpty ? nil : URL(string: address)
  }

  /// The site and the author, as the web app joined them.
  private var byline: String {
    [imported.siteName, imported.author].compactMap { $0 }.filter { !$0.isEmpty }
      .joined(separator: " · ")
  }

  var body: some View {
    Section {
      if imported.rough {
        Label {
          Text(verbatim: Copy.importNative.rough.text)
            .brandText(.control)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(Brand.Colors.tips)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.Colors.tips.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.Colors.tips.opacity(0.45)))
      }
      if draft.needsReview {
        Text(verbatim: Copy.imports.review.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: Copy.imports.source.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
        if let link {
          Link(destination: link) {
            Text(verbatim: draft.sourceURL).brandText(.body).multilineTextAlignment(.leading)
          }
          .tint(Brand.Colors.magic)
        } else {
          Text(verbatim: Copy.imports.pasted.text).brandText(.body)
        }
        if !byline.isEmpty {
          Text(verbatim: byline).brandText(.control).foregroundStyle(Brand.Colors.subtext)
        }
      }
      if let duplicate {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            verbatim:
              "\(Copy.imports.duplicate(duplicate.title).text) \(Copy.imports.saveAnyway.text)"
          )
          .brandText(.control)
          .fixedSize(horizontal: false, vertical: true)
          Button(action: onOpenDuplicate) {
            Text(verbatim: Copy.imports.openDuplicate.text)
          }
          .buttonStyle(.borderless)
          .brandText(.control)
          .tint(Brand.Colors.magic)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.Colors.tips.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.Colors.tips.opacity(0.45)))
      }
    }
    .listRowBackground(Brand.Colors.mantle)
  }
}
