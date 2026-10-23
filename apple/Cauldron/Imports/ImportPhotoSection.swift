import CauldronImports
import CauldronKit
import PhotosUI
import SwiftUI

/// The third way into Distill: a photo of the recipe. The cook scans pages (iPhone and iPad),
/// chooses pictures from the library, or on the Mac chooses image files or drops them on the
/// sheet. The pages show here as a strip, and the Distill button below reads them.
///
/// The things that take over the screen or load in the background (the picker's selection, the
/// scanner, the file panel) are presented by `ImportStartSheet`, from the navigation stack itself:
/// a modifier that does work, inside the stack's content, crashes an `ImageRenderer` at teardown.
/// This view only flips the switches.
struct ImportPhotoSection: View {
  @Bindable var model: ImportModel
  @Binding var picked: [PhotosPickerItem]
  @Binding var scanning: Bool
  @Binding var choosingFiles: Bool

  private var room: Int { max(0, ImportModel.pageLimit - model.pages.count) }

  var body: some View {
    Section {
      if !model.pages.isEmpty {
        pageStrip
        Toggle(isOn: $model.keepFirstPage) {
          Text(verbatim: Copy.importNative.keepFirstPage.text)
            .brandText(.control)
        }
        .tint(Brand.Colors.magic)
      }
      HStack(spacing: 16) {
        #if os(iOS)
          Button {
            if let message = ScannerAvailability.current.message {
              model.reportPhotoProblem(message)
            } else {
              model.reportPhotoProblem(nil)
              scanning = true
            }
          } label: {
            Label {
              Text(verbatim: Copy.importNative.scanPages.text)
            } icon: {
              Image(systemName: "doc.viewfinder")
            }
          }
          .disabled(room == 0)
        #endif
        PhotosPicker(selection: $picked, maxSelectionCount: max(1, room), matching: .images) {
          Label {
            Text(verbatim: Copy.importNative.choosePhotos.text)
          } icon: {
            Image(systemName: "photo.on.rectangle")
          }
        }
        .disabled(room == 0)
        #if os(macOS)
          Button {
            choosingFiles = true
          } label: {
            Label {
              Text(verbatim: Copy.importNative.chooseFiles.text)
            } icon: {
              Image(systemName: "folder")
            }
          }
          .disabled(room == 0)
        #endif
      }
      .buttonStyle(.borderless)
      .brandText(.control)
      .tint(Brand.Colors.magic)
      if let message = model.photoMessage {
        Text(verbatim: message.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.heat)
          .fixedSize(horizontal: false, vertical: true)
      }
    } header: {
      Text(verbatim: Copy.importNative.fromPhoto.text)
    } footer: {
      #if os(macOS)
        Text(verbatim: Copy.importNative.macPhotoHint.text)
      #else
        Text(verbatim: Copy.importNative.photoHint.text)
      #endif
    }
    .listRowBackground(Brand.Colors.mantle)
  }

  private var pageStrip: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: Copy.importNative.pageCount(model.pages.count).text)
        .brandText(.quantity)
        .foregroundStyle(Brand.Colors.subtext)
      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
            PageThumbnail(page: page, number: index + 1) { model.removePage(page.id) }
          }
        }
        .padding(.vertical, 2)
      }
      .scrollIndicators(.hidden)
    }
  }
}

/// One captured page, small, with a button to take it out.
private struct PageThumbnail: View {
  let page: ScannedPage
  let number: Int
  let remove: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      ZStack {
        Rectangle().fill(Brand.Colors.crust)
        if let image = page.thumbnail {
          Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else {
          Image(systemName: "doc.text")
            .foregroundStyle(Brand.Colors.overlay1)
        }
      }
      .frame(width: 64, height: 84)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(alignment: .bottomLeading) {
        Text(verbatim: Copy.display.number(number).text)
          .brandText(.quantity)
          .foregroundStyle(Brand.Colors.ink)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(Brand.Colors.mantle.opacity(0.85), in: Capsule())
          .padding(3)
          .accessibilityHidden(true)
      }
      .accessibilityElement()
      .accessibilityLabel(Text(verbatim: Copy.importNative.page(number).text))

      Button(action: remove) {
        Image(systemName: "xmark.circle.fill")
          .symbolRenderingMode(.palette)
          .foregroundStyle(Brand.Colors.ink, Brand.Colors.mantle)
          .font(.system(size: 18))
      }
      .buttonStyle(.borderless)
      .offset(x: 6, y: -6)
      .accessibilityLabel(Text(verbatim: Copy.importNative.removePage(number).text))
    }
    .padding(.top, 6)
    .padding(.trailing, 6)
  }
}
