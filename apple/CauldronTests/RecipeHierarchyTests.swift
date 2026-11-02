import CauldronKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

#if DEBUG
  @MainActor
  @Suite("Recipe hierarchy")
  struct RecipeHierarchyTests {
    @Test func aCardHasAThumbnailTileOnlyWhenTheRecipeHasAPhoto() throws {
      let container = try CauldronStore.container(.inMemory)
      let plain = RecipeRecord(title: "Toast")
      let withPhoto = RecipeRecord(title: "Shakshuka")
      withPhoto.photo = PhotoRecord(imageData: Data([1, 2, 3]), width: 1, height: 1)
      let emptyPhoto = RecipeRecord(title: "Soup")
      emptyPhoto.photo = PhotoRecord(imageData: nil, width: 0, height: 0)
      for recipe in [plain, withPhoto, emptyPhoto] { container.mainContext.insert(recipe) }

      #expect(!RecipeCardInfo(plain).hasPhoto)
      #expect(RecipeCardInfo(withPhoto).hasPhoto)
      #expect(!RecipeCardInfo(emptyPhoto).hasPhoto)
    }

    @Test func cardsRenderWithAndWithoutAPhotoInBothAppearances() throws {
      let container = try CauldronStore.container(.inMemory)
      let plain = RecipeRecord(title: "Toast with a very long name that wraps onto a second line")
      container.mainContext.insert(plain)
      for scheme in [ColorScheme.light, .dark] {
        for width in [360.0, 720.0] {
          let view = RecipeCardView(recipe: plain)
            .environment(\.colorScheme, scheme)
            .frame(width: width)
          #expect(ImageRenderer(content: view).cgImage != nil)
        }
      }
    }

    @Test func everyActionStyleRendersInBothAppearances() {
      for scheme in [ColorScheme.light, .dark] {
        let view = VStack {
          Button("a") {}.buttonStyle(RecipeActionButtonStyle(.primary))
          Button("b") {}.buttonStyle(RecipeActionButtonStyle(.secondary))
          Button("c") {}.buttonStyle(RecipeActionButtonStyle(.quiet))
          Button("d") {}.buttonStyle(RecipeActionButtonStyle(.quiet)).disabled(true)
        }
        .environment(\.colorScheme, scheme)
        .frame(width: 300, height: 300)
        #expect(ImageRenderer(content: view).cgImage != nil)
      }
    }

    @Test func aStepWithATimerAndARecipeWithATipRenderInBothAppearances() throws {
      let container = try CauldronStore.container(.inMemory)
      let recipe = RecipeRecord(title: "Shakshuka")
      recipe.notes = "Make the wells with the back of a spoon so the yolks stay put."
      container.mainContext.insert(recipe)
      for scheme in [ColorScheme.light, .dark] {
        let step = StepView(number: 1, text: "Soften the onion.", timer: "8 min")
          .environment(\.colorScheme, scheme)
          .frame(width: 360)
        #expect(ImageRenderer(content: step).cgImage != nil)
        let detail = RecipeDetailView(recipe: recipe) {}
          .modelContainer(container)
          .environment(\.colorScheme, scheme)
          .frame(width: 390, height: 800)
        #expect(ImageRenderer(content: detail).cgImage != nil)
      }
    }
  }
#endif
