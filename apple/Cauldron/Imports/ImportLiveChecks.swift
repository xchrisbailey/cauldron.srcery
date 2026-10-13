#if DEBUG
  import CauldronKit
  import SwiftUI

  /// The links to tap through on a device to see Distill work on real sites. The first five are
  /// the old weekly import check's (`apps/api/test/live/`); the rest are the sites the ticket
  /// added. Debug builds only, and nothing fetches them but a tap: no test does.
  enum ImportLiveChecks {
    struct Check: Identifiable {
      var name: String
      var link: String
      /// What a good result looks like.
      var expect: String
      var id: String { link }
    }

    static let all: [Check] = [
      Check(
        name: "BBC Good Food", link: "https://www.bbcgoodfood.com/recipes/easy-pancakes",
        expect: "JSON-LD, no model"),
      Check(
        name: "RecipeTin Eats", link: "https://www.recipetineats.com/chicken-chasseur/",
        expect: "JSON-LD, no model"),
      Check(
        name: "Love and Lemons", link: "https://www.loveandlemons.com/hummus-recipe/",
        expect: "JSON-LD, no model"),
      Check(
        name: "Bon Appetit",
        link: "https://www.bonappetit.com/recipe/bas-best-chocolate-chip-cookies",
        expect: "JSON-LD, no model"),
      Check(
        name: "TikTok (oEmbed's own example)",
        link: "https://www.tiktok.com/@scout2015/video/6718335390845095173?is_from_webapp=1",
        expect: "a caption read by the model, or \"spoken only\""),
      Check(
        name: "Allrecipes",
        link: "https://www.allrecipes.com/recipe/10813/best-chocolate-chip-cookies/",
        expect: "the recipe, or the paste fallback"),
      Check(
        name: "Serious Eats",
        link: "https://www.seriouseats.com/the-food-labs-chocolate-chip-cookies-recipe",
        expect: "the recipe, or the paste fallback (link not checked)"),
      Check(
        name: "Instagram (no token on a device)", link: "https://www.instagram.com/p/C8QzE3fyN3J/",
        expect: "the paste fallback"),
    ]
  }

  /// A section of the import form that fills the link field from the list above and starts.
  struct ImportLiveChecksSection: View {
    let model: ImportModel

    var body: some View {
      Section {
        ForEach(ImportLiveChecks.all) { check in
          Button {
            model.link = check.link
            model.start()
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: check.name).brandText(.body)
              Text(verbatim: check.expect).brandText(.control).foregroundStyle(Brand.Colors.subtext)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
        }
      } header: {
        Text(verbatim: "Live checks (debug builds)")
      }
      .listRowBackground(Brand.Colors.mantle)
    }
  }
#endif
