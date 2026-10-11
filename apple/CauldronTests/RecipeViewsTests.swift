import CauldronKit
import ImageIO
import SwiftData
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import Cauldron

#if DEBUG
  @MainActor
  @Suite("Recipe views")
  struct RecipeViewsTests {
    private func seeded() throws -> (container: ModelContainer, recipes: [RecipeRecord]) {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      try DebugSeed.populate(context, today: DebugSeed.today())
      return (container, try context.fetch(FetchDescriptor<RecipeRecord>()))
    }

    @Test func theLibraryRendersEmptyAndSeededInBothAppearances() throws {
      let empty = try CauldronStore.container(.inMemory)
      let (full, _) = try seeded()
      for container in [empty, full] {
        for scheme in [ColorScheme.light, .dark] {
          let view = RecipesRoot()
            .modelContainer(container)
            .environment(\.colorScheme, scheme)
            .frame(width: 900, height: 700)
          #expect(ImageRenderer(content: view).cgImage != nil)
        }
      }
    }

    @Test func everySeededRecipeRendersItsDetailInBothAppearances() throws {
      let (container, recipes) = try seeded()
      for recipe in recipes {
        for scheme in [ColorScheme.light, .dark] {
          let view = RecipeDetailView(recipe: recipe) {}
            .modelContainer(container)
            .environment(\.colorScheme, scheme)
            .frame(width: 390, height: 800)
          #expect(ImageRenderer(content: view).cgImage != nil, "\(recipe.title) in \(scheme)")
        }
      }
    }

    @Test func aRecipeWithNothingButATitleStillRenders() throws {
      let container = try CauldronStore.container(.inMemory)
      let recipe = RecipeRecord(title: "Toast")
      ModelContext(container).insert(recipe)
      let view = RecipeDetailView(recipe: recipe) {}.modelContainer(container)
        .frame(width: 390, height: 800)
      #expect(ImageRenderer(content: view).cgImage != nil)
    }

    // MARK: Photos

    private func png(width: Int, height: Int) throws -> Data {
      let space = CGColorSpaceCreateDeviceRGB()
      let context = try #require(
        CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      let image = try #require(context.makeImage())
      let data = NSMutableData()
      let destination = try #require(
        CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      #expect(CGImageDestinationFinalize(destination))
      return data as Data
    }

    @Test func aPhotoIsDecodedNoLargerThanAsked() throws {
      let thumbnail = try #require(
        RecipePhotoView.thumbnail(of: try png(width: 800, height: 400), maxPixel: 100))
      #expect(max(thumbnail.width, thumbnail.height) == 100)
      #expect(thumbnail.width == 2 * thumbnail.height)
    }

    @Test func missingOrBrokenPhotoDataGivesNoImage() {
      #expect(RecipePhotoView.thumbnail(of: nil, maxPixel: 100) == nil)
      #expect(RecipePhotoView.thumbnail(of: Data("not an image".utf8), maxPixel: 100) == nil)
    }
  }
#endif
