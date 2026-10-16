import CauldronImports
import SwiftData
import SwiftUI

/// A recipe's photo, cropped to fill, or the quiet placeholder when it has none. The image is
/// decoded at the size it's shown, off the main thread, so a long list stays smooth.
struct RecipePhotoView: View {
  let photo: PhotoRecord?
  /// The longest side to decode, in pixels.
  var maxPixel: Int = 400
  @State private var image: CGImage?

  var body: some View {
    // The rectangle sets the size and the photo is laid over it. In a stack, a photo filling a
    // wide frame would be as wide as it fills, and push the whole page past the screen's edge.
    Rectangle().fill(Brand.Colors.crust)
      .overlay {
        if let image {
          Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
        } else {
          Image(systemName: AppDestination.recipes.systemImage)
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(Brand.Colors.magic)
            .accessibilityHidden(true)
        }
      }
      .clipped()
      .task(id: photo?.id) {
        let data = photo?.imageData
        let side = maxPixel
        image = await Task.detached { RecipePhotoView.thumbnail(of: data, maxPixel: side) }.value
      }
  }

  nonisolated static func thumbnail(of data: Data?, maxPixel: Int) -> CGImage? {
    PhotoProcessing.thumbnail(of: data, maxPixel: maxPixel)
  }

}
