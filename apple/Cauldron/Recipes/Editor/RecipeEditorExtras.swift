import CauldronKit
import PhotosUI
import SwiftData
import SwiftUI

/// Tags: the ones on the recipe as removable chips, a field to add one, and the tags that
/// already exist to pick from. A tag typed with the same name as an existing one, in any case,
/// is that tag (`RecipeSaver`).
struct RecipeTagsSection: View {
  @Binding var draft: RecipeDraft
  let error: CopyString?
  @Query(sort: \TagRecord.name) private var existing: [TagRecord]
  @State private var typed = ""

  var body: some View {
    Section {
      if !draft.tags.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(draft.tags, id: \.self) { name in
            Button {
              draft.removeTag(name)
            } label: {
              HStack(spacing: 4) {
                Text(verbatim: name).brandText(.control)
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Brand.Colors.surface0, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: Copy.editor.removeTag(name).text))
          }
        }
      }
      TextField("", text: $typed)
        .textFieldStyle(.plain)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandText(.body)
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
        .autocorrectionDisabled()
        .accessibilityLabel(Text(verbatim: Copy.editor.tags.text))
        .onSubmit(addTyped)
        .onChange(of: typed) { _, value in
          // A comma ends a tag.
          if value.contains(",") { addTyped() }
        }
      if !suggestions.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(suggestions, id: \.self) { name in
            Button {
              draft.addTag(name)
              typed = ""
            } label: {
              Text(verbatim: name)
                .brandText(.control)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(Capsule().stroke(Brand.Colors.surface1, lineWidth: 1))
            }
            .buttonStyle(.plain)
          }
        }
      }
      if let error {
        Text(verbatim: error.text).brandText(.control).foregroundStyle(Brand.Colors.heat)
      }
    } header: {
      Text(verbatim: Copy.editor.tags.text)
    } footer: {
      Text(verbatim: Copy.editor.tagsHint.text).fixedSize(horizontal: false, vertical: true)
    }
    .listRowBackground(Brand.Colors.mantle)
  }

  private func addTyped() {
    for part in typed.split(separator: ",", omittingEmptySubsequences: true) {
      draft.addTag(String(part))
    }
    typed = ""
  }

  /// Existing tags not already on the recipe, narrowed by what's typed.
  private var suggestions: [String] {
    let have = Set(draft.tags.map { $0.lowercased() })
    let query = typed.trimmingCharacters(in: .whitespaces).lowercased()
    var seen = Set<String>()
    return existing.map(\.name).filter { name in
      let key = name.lowercased()
      return !have.contains(key) && (query.isEmpty || key.contains(query))
        && seen.insert(key).inserted
    }.prefix(10).map { $0 }
  }
}

/// The cover photo: the picker (and the camera, where it's offered), a preview, and Remove.
/// A chosen photo is downscaled and compressed off the main thread before it joins the draft.
struct RecipePhotoSection: View {
  @Binding var draft: RecipeDraft
  let recipe: RecipeRecord?
  @State private var picked: PhotosPickerItem?
  @State private var message: CopyString?
  @State private var working = false
  @State private var preview: CGImage?

  private var shownData: Data? {
    switch draft.photo {
    case .keep: recipe?.photo?.imageData
    case .replace(let photo): photo.data
    case .remove: nil
    }
  }

  var body: some View {
    Section {
      ZStack {
        Rectangle().fill(Brand.Colors.crust)
        if let preview {
          Image(decorative: preview, scale: 1).resizable().scaledToFill()
        } else {
          Image(systemName: AppDestination.recipes.systemImage)
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(Brand.Colors.magic)
            .accessibilityHidden(true)
        }
        if working { ProgressView() }
      }
      .frame(height: 180)
      .frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .accessibilityElement()
      .accessibilityLabel(
        Text(
          verbatim: Copy.photos.alt(draft.title.isEmpty ? Copy.editor.title.text : draft.title).text
        )
      )
      .task(id: shownData?.count) {
        let data = shownData
        preview = await Task.detached { RecipePhotoView.thumbnail(of: data, maxPixel: 800) }.value
      }

      HStack {
        PhotosPicker(selection: $picked, matching: .images) {
          Label {
            Text(verbatim: (shownData == nil ? Copy.photos.add : Copy.photos.replace).text)
          } icon: {
            Image(systemName: "photo")
          }
        }
        RecipeCameraButton { data in process(data) }
        if shownData != nil {
          Button(role: .destructive) {
            draft.photo = recipe?.photo == nil ? .keep : .remove
            message = nil
          } label: {
            Text(verbatim: Copy.photos.remove.text)
          }
        }
      }
      .buttonStyle(.borderless)
      .brandText(.control)
      .tint(Brand.Colors.magic)
      .disabled(working)

      if let message {
        Text(verbatim: message.text).brandText(.control).foregroundStyle(Brand.Colors.heat)
      }
    }
    .listRowBackground(Brand.Colors.mantle)
    .onChange(of: picked) { _, item in
      guard let item else { return }
      Task {
        working = true
        let data = try? await item.loadTransferable(type: Data.self)
        picked = nil
        if let data {
          process(data)
        } else {
          message = PhotoError.unreadable.message
          working = false
        }
      }
    }
  }

  private func process(_ data: Data) {
    working = true
    message = nil
    Task {
      let result = await Task.detached { PhotoProcessing.process(data) }.value
      switch result {
      case .success(let photo): draft.photo = .replace(photo)
      case .failure(let error): message = error.message
      }
      working = false
    }
  }
}
