import ImageIO
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
    ZStack {
      Rectangle().fill(Brand.Colors.crust)
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
    guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }
}
