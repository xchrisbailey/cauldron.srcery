import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Cauldron
@testable import CauldronImports

@Suite("Photo processing")
struct PhotoProcessingTests {
  /// An image of `width` x `height`, filled with a colour, encoded as `type`.
  private func image(
    _ width: Int, _ height: Int, as type: UTType = .png, alpha: Bool = false
  ) throws -> Data {
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    if !alpha {
      context.setFillColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    let data = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
  }

  private func processed(_ data: Data, maxPixel: Int = PhotoProcessing.maxPixel) throws
    -> ProcessedPhoto
  {
    try PhotoProcessing.process(data, maxPixel: maxPixel).get()
  }

  private func decoded(_ photo: ProcessedPhoto) throws -> (type: String, width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithData(photo.data as CFData, nil))
    let type = try #require(CGImageSourceGetType(source)) as String
    let properties = try #require(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    return (
      type, properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
      properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    )
  }

  @Test func aLargePhotoIsScaledToTheLimitKeepingItsShape() throws {
    let photo = try processed(try image(3000, 1500), maxPixel: 1000)
    #expect(photo.width == 1000 && photo.height == 500)
    let result = try decoded(photo)
    #expect(result.type == UTType.jpeg.identifier)
    #expect(result.width == 1000 && result.height == 500)
  }

  @Test func theDefaultLimitIs2048OnTheLongSide() throws {
    let photo = try processed(try image(4096, 3072))
    #expect(photo.width == 2048 && photo.height == 1536)
  }

  @Test func aSmallPhotoIsNotEnlarged() throws {
    let photo = try processed(try image(120, 80))
    #expect(photo.width == 120 && photo.height == 80)
  }

  @Test func aTallPhotoIsLimitedByItsHeight() throws {
    let photo = try processed(try image(500, 2000), maxPixel: 1000)
    #expect(photo.height == 1000 && photo.width == 250)
  }

  @Test func theOutputIsJPEGWhateverWentIn() throws {
    for type in [UTType.png, .jpeg, .tiff, .gif] {
      let photo = try processed(try image(64, 64, as: type))
      #expect(try decoded(photo).type == UTType.jpeg.identifier, "\(type)")
    }
  }

  @Test func aTransparentPhotoIsFlattenedOntoWhite() throws {
    let photo = try processed(try image(32, 32, alpha: true))
    let source = try #require(CGImageSourceCreateWithData(photo.data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let context = try #require(
      CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: -16, y: -16, width: 32, height: 32))
    let pixel = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    #expect(pixel[0] > 240 && pixel[1] > 240 && pixel[2] > 240)
  }

  @Test func aLargeSolidPhotoIsSmallerAfterwards() throws {
    let source = try image(3000, 2000)
    let photo = try processed(source)
    #expect(photo.data.count < source.count + 20_000)
    #expect(photo.width == 2048)
  }

  // MARK: Failures

  @Test func bytesThatAreNotAnImageAreUnsupported() {
    #expect(PhotoProcessing.process(Data("not an image".utf8)) == .failure(.unsupported))
    #expect(PhotoProcessing.process(Data()) == .failure(.unsupported))
    #expect(PhotoProcessing.process(Data("%PDF-1.4 hello".utf8)) == .failure(.unsupported))
  }

  @Test func aPhotoOverFifteenMegabytesIsTooLarge() {
    let big = Data(count: PhotoProcessing.maxBytes + 1)
    #expect(PhotoProcessing.process(big) == .failure(.tooLarge))
  }

  @Test func anImageHeaderWithNothingUsableAfterItCantBeRead() {
    let png = Data(
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 7, count: 64))
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 7, count: 64))
    for data in [png, jpeg] {
      let result = PhotoProcessing.process(data)
      #expect(result == .failure(.unreadable) || result == .failure(.unsupported))
    }
  }

  @Test func everyFailureHasAPlainMessageFromTheCopyModule() {
    let errors: [PhotoError] = [.unsupported, .tooLarge, .tooBig, .unreadable]
    #expect(
      errors.map(\.message.text) == [
        "Use a JPEG, PNG, WebP or AVIF photo.",
        "That photo is over 15 MB. Try a smaller one.",
        "That photo is too large to process. Try a smaller one.",
        "We couldn't read that photo. Try another one.",
      ])
    #expect(errors.allSatisfy { $0.message.tone == .plain })
  }
}

@Suite("Camera")
struct CameraTests {
  @Test func theCameraIsOfferedOnlyWithADeviceCameraAndAUsageDescription() {
    #expect(RecipeCamera.isOffered(hasUsageDescription: true, cameraAvailable: true))
    #expect(!RecipeCamera.isOffered(hasUsageDescription: false, cameraAvailable: true))
    #expect(!RecipeCamera.isOffered(hasUsageDescription: true, cameraAvailable: false))
  }
}
