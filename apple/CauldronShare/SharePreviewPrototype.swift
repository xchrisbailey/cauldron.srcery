// PROTOTYPE, throwaway. Debug builds only. Map #191, ticket #195.
//
// Question: what should the share sheet show while it reads a shared recipe, and once the draft
// is ready to save? Three structurally different variants of the sheet, switchable from the
// floating bar at the top, each driven through every state (reading, ready, already in the box,
// saved, failed, no AI key). The recipes are fake and nothing is saved: Save and Edit in
// Cauldron only show what would happen and close the sheet. Geist Mono stands in as the
// system monospaced font.
#if DEBUG

  import CauldronKit
  import SwiftUI

  // MARK: - Fake data

  struct ProtoRecipe {
    struct Line {
      var quantity: String
      var unit: String
      var item: String
      /// A line the parser wasn't sure of, shown in the tips colour.
      var toCheck = false
    }

    var title: String
    var source: String
    var hasPhoto: Bool
    var time: String
    var serves: Int
    var ingredients: [Line]
    var steps: [String]
    /// Calories, protein, carbs, fat per serving.
    var macros: (Int, Int, Int, Int)

    var linesToCheck: Int { ingredients.filter(\.toCheck).count }

    static let web = ProtoRecipe(
      title: "Crispy gnocchi with burst tomatoes",
      source: "seriouseats.com",
      hasPhoto: true,
      time: "35 min",
      serves: 4,
      ingredients: [
        .init(quantity: "500", unit: "g", item: "shelf-stable gnocchi"),
        .init(quantity: "3", unit: "tbsp", item: "olive oil, divided"),
        .init(quantity: "4", unit: "", item: "garlic cloves, thinly sliced"),
        .init(quantity: "600", unit: "g", item: "cherry tomatoes"),
        .init(quantity: "1/2", unit: "tsp", item: "red pepper flakes"),
        .init(quantity: "125", unit: "g", item: "fresh mozzarella, torn"),
        .init(quantity: "1", unit: "handful", item: "basil leaves"),
        .init(quantity: "", unit: "", item: "salt and pepper, to taste"),
      ],
      steps: [
        "Heat 2 tbsp oil in a large skillet over medium-high. Add gnocchi in one layer and cook, undisturbed, until golden underneath, about 5 minutes.",
        "Toss and cook until crisp all over, 3 to 4 minutes more. Move to a plate.",
        "Add the remaining oil, garlic and pepper flakes. Cook until fragrant, 1 minute.",
        "Add tomatoes and cook, stirring, until they burst and turn saucy, 8 to 10 minutes. Season.",
        "Return gnocchi, toss, and top with mozzarella and basil.",
      ],
      macros: (512, 17, 68, 19))

    static let caption = ProtoRecipe(
      title: "Hot honey halloumi bowls",
      source: "instagram.com/@cookwithmaya",
      hasPhoto: false,
      time: "20 min",
      serves: 2,
      ingredients: [
        .init(quantity: "225", unit: "g", item: "halloumi, sliced"),
        .init(quantity: "1", unit: "cup", item: "cooked rice"),
        .init(quantity: "", unit: "", item: "a big drizzle of hot honey", toCheck: true),
        .init(quantity: "1", unit: "", item: "cucumber, diced"),
        .init(quantity: "", unit: "", item: "pickled onions (link in bio)", toCheck: true),
        .init(quantity: "2", unit: "tbsp", item: "greek yoghurt"),
      ],
      steps: [
        "Fry the halloumi in a dry pan until golden on both sides.",
        "Pile rice, cucumber and pickled onions into bowls.",
        "Top with halloumi, yoghurt and hot honey.",
      ],
      macros: (640, 31, 58, 30))
  }

  // MARK: - State

  enum ProtoVariant: String, CaseIterable {
    case card = "A · Full recipe"
    case summary = "B · Summary"
    case tabs = "C · Tabs"
  }

  enum ProtoPhase: String, CaseIterable {
    case reading = "Reading"
    case ready = "Ready"
    case duplicate = "Already in box"
    case saved = "Saved"
    case failed = "Couldn't read"
    case noKey = "No AI key"
  }

  enum ProtoSource: String, CaseIterable {
    case web = "Web page"
    case caption = "Instagram caption"
  }

  // MARK: - Host

  /// The sheet's root while prototyping. `close` ends the extension.
  struct SharePreviewPrototype: View {
    let sharedLink: String?
    let close: () -> Void

    @State private var variant = ProtoVariant.card
    @State private var phase = ProtoPhase.reading
    @State private var source = ProtoSource.web
    /// What the last button pressed would have done, shown before the sheet closes.
    @State private var outcome: String?

    private var recipe: ProtoRecipe {
      var recipe = source == .web ? ProtoRecipe.web : ProtoRecipe.caption
      if source == .web, let host = sharedLink.flatMap({ URL(string: $0) })?.host() {
        recipe.source = host
      }
      return recipe
    }

    var body: some View {
      ZStack(alignment: .top) {
        Brand.Colors.base.ignoresSafeArea()
        Group {
          switch phase {
          case .reading: ProtoReading(variant: variant, source: source, cancel: close)
          case .ready, .duplicate:
            switch variant {
            case .card:
              VariantCard(
                recipe: recipe, duplicate: phase == .duplicate, save: save, edit: edit,
                cancel: close)
            case .summary:
              VariantSummary(
                recipe: recipe, duplicate: phase == .duplicate, save: save, edit: edit,
                cancel: close)
            case .tabs:
              VariantTabs(
                recipe: recipe, duplicate: phase == .duplicate, save: save, edit: edit,
                cancel: close)
            }
          case .saved: ProtoSaved(title: recipe.title)
          case .failed:
            ProtoFailed(
              message: "This page couldn't be read. It may be behind a login or blocked.",
              send: edit, cancel: close)
          case .noKey:
            ProtoFailed(
              message: "No AI key yet, so Cauldron can't read this here. Add one in Settings.",
              send: edit, cancel: close)
          }
        }
        .padding(.top, 56)
        ProtoSwitcher(variant: $variant, phase: $phase, source: $source)
          .padding(.top, 8)
        if let outcome {
          Text(verbatim: outcome)
            .font(ShareFonts.font(size: 14, weight: 500))
            .padding(12)
            .background(.black.opacity(0.85), in: .rect(cornerRadius: 12))
            .foregroundStyle(.white)
            .frame(maxHeight: .infinity, alignment: .center)
        }
      }
      // A real run reads for a few seconds, then shows the draft.
      .task(id: phase) {
        guard phase == .reading else { return }
        try? await Task.sleep(for: .seconds(2.5))
        if phase == .reading { phase = .ready }
      }
    }

    private func save() {
      phase = .saved
      finish("Would leave the finished recipe for Cauldron to add silently.")
    }

    private func edit() {
      finish("Would leave the link for Cauldron to open as a draft next launch.")
    }

    private func finish(_ message: String) {
      outcome = message
      Task {
        try? await Task.sleep(for: .seconds(2))
        close()
      }
    }
  }

  // MARK: - Shared bits

  private func brandFont(_ size: CGFloat, _ weight: CGFloat = 400) -> Font {
    ShareFonts.font(size: size, weight: weight)
  }

  private func monoFont(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }

  private struct ProtoPhoto: View {
    var height: CGFloat
    var body: some View {
      LinearGradient(
        colors: [Brand.Colors.heat.opacity(0.6), Brand.Colors.magic.opacity(0.5)],
        startPoint: .topLeading, endPoint: .bottomTrailing
      )
      .overlay(Image(systemName: "fork.knife").font(.system(size: 28)).foregroundStyle(.white))
      .frame(height: height)
      .frame(maxWidth: .infinity)
    }
  }

  private struct MacroLine: View {
    let macros: (Int, Int, Int, Int)
    var body: some View {
      HStack(spacing: 14) {
        Text(verbatim: "\(macros.0) kcal").foregroundStyle(MacroKey.calories.tint)
        Text(verbatim: "P \(macros.1)g").foregroundStyle(MacroKey.protein.tint)
        Text(verbatim: "C \(macros.2)g").foregroundStyle(MacroKey.carbs.tint)
        Text(verbatim: "F \(macros.3)g").foregroundStyle(MacroKey.fat.tint)
      }
      .font(monoFont(13))
    }
  }

  private struct IngredientRow: View {
    let line: ProtoRecipe.Line
    var body: some View {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(verbatim: line.quantity).font(monoFont(15)).foregroundStyle(Brand.Colors.ink)
          .frame(minWidth: 34, alignment: .trailing)
        Text(verbatim: line.unit).font(monoFont(13)).foregroundStyle(Brand.Colors.overlay1)
          .frame(minWidth: 40, alignment: .leading)
        Text(verbatim: line.item).font(brandFont(15))
          .foregroundStyle(line.toCheck ? Brand.Colors.tips : Brand.Colors.ink)
        Spacer(minLength: 0)
      }
    }
  }

  private struct StepRow: View {
    let number: Int
    let text: String
    var body: some View {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(verbatim: "\(number)").font(monoFont(14)).foregroundStyle(Brand.Colors.magic)
        Text(verbatim: text).font(brandFont(15)).foregroundStyle(Brand.Colors.ink)
      }
    }
  }

  private struct DuplicateBanner: View {
    var body: some View {
      Label {
        Text(verbatim: "You already have this one, saved from the same link.")
      } icon: {
        Image(systemName: "square.on.square")
      }
      .font(brandFont(14, 500))
      .foregroundStyle(Brand.Colors.tips)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Brand.Colors.surface0, in: .rect(cornerRadius: 10))
    }
  }

  private struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
      Button(action: action) {
        Text(verbatim: title).font(brandFont(17, 650)).frame(maxWidth: .infinity).padding(.vertical, 14)
      }
      .buttonStyle(.plain)
      .foregroundStyle(Brand.Colors.base)
      .background(Brand.Colors.magic, in: .rect(cornerRadius: 14))
    }
  }

  // MARK: - Variant A: the whole recipe, scrolling, with a pinned action bar

  /// Reads like the recipe page itself: photo, title, macros, every ingredient and step. Save
  /// and Edit sit pinned at the bottom.
  private struct VariantCard: View {
    let recipe: ProtoRecipe
    let duplicate: Bool
    let save: () -> Void
    let edit: () -> Void
    let cancel: () -> Void

    var body: some View {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if recipe.hasPhoto { ProtoPhoto(height: 180).clipShape(.rect(cornerRadius: 14)) }
            if duplicate { DuplicateBanner() }
            VStack(alignment: .leading, spacing: 6) {
              Text(verbatim: recipe.title).font(brandFont(26, 650)).foregroundStyle(Brand.Colors.ink)
              HStack(spacing: 10) {
                Text(verbatim: recipe.source)
                Text(verbatim: recipe.time).font(monoFont(13))
                Text(verbatim: "serves \(recipe.serves)").font(monoFont(13))
              }
              .font(brandFont(13)).foregroundStyle(Brand.Colors.subtext)
              MacroLine(macros: recipe.macros)
            }
            Text(verbatim: "Ingredients").font(brandFont(18, 650)).foregroundStyle(Brand.Colors.ink)
            VStack(alignment: .leading, spacing: 8) {
              ForEach(recipe.ingredients.indices, id: \.self) {
                IngredientRow(line: recipe.ingredients[$0])
              }
            }
            Text(verbatim: "Steps").font(brandFont(18, 650)).foregroundStyle(Brand.Colors.ink)
            VStack(alignment: .leading, spacing: 12) {
              ForEach(recipe.steps.indices, id: \.self) {
                StepRow(number: $0 + 1, text: recipe.steps[$0])
              }
            }
          }
          .padding(16)
        }
        VStack(spacing: 8) {
          PrimaryButton(title: duplicate ? "Save another copy" : "Save to recipes", action: save)
          HStack {
            Button("Cancel", action: cancel)
            Spacer()
            Button("Edit in Cauldron", action: edit)
          }
          .font(brandFont(15, 500))
          .foregroundStyle(Brand.Colors.magic)
          .buttonStyle(.plain)
        }
        .padding(16)
        .background(Brand.Colors.mantle)
      }
    }
  }

  // MARK: - Variant B: a short summary, details folded away

  /// Fits on one screen: what was found and anything to look at, with the full lists folded.
  /// Save is the obvious next step; editing is a quiet link.
  private struct VariantSummary: View {
    let recipe: ProtoRecipe
    let duplicate: Bool
    let save: () -> Void
    let edit: () -> Void
    let cancel: () -> Void
    @State private var showIngredients = false
    @State private var showSteps = false

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack(alignment: .top, spacing: 12) {
            if recipe.hasPhoto {
              ProtoPhoto(height: 72).frame(width: 72).clipShape(.rect(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 4) {
              Text(verbatim: recipe.title).font(brandFont(20, 650)).foregroundStyle(Brand.Colors.ink)
              Text(verbatim: recipe.source).font(brandFont(13)).foregroundStyle(Brand.Colors.subtext)
            }
          }
          HStack(spacing: 0) {
            stat("\(recipe.ingredients.count)", "ingredients")
            stat("\(recipe.steps.count)", "steps")
            stat(recipe.time, "total")
            stat("\(recipe.serves)", "serves")
          }
          .padding(.vertical, 10)
          .background(Brand.Colors.mantle, in: .rect(cornerRadius: 12))
          MacroLine(macros: recipe.macros)
          if duplicate { DuplicateBanner() }
          if recipe.linesToCheck > 0 {
            Label {
              Text(verbatim: "\(recipe.linesToCheck) ingredient lines to check in Cauldron")
            } icon: {
              Image(systemName: "exclamationmark.circle")
            }
            .font(brandFont(14, 500))
            .foregroundStyle(Brand.Colors.tips)
          }
          DisclosureGroup(isExpanded: $showIngredients) {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(recipe.ingredients.indices, id: \.self) {
                IngredientRow(line: recipe.ingredients[$0])
              }
            }
            .padding(.top, 8)
          } label: {
            Text(verbatim: "Ingredients").font(brandFont(16, 600)).foregroundStyle(Brand.Colors.ink)
          }
          DisclosureGroup(isExpanded: $showSteps) {
            VStack(alignment: .leading, spacing: 12) {
              ForEach(recipe.steps.indices, id: \.self) {
                StepRow(number: $0 + 1, text: recipe.steps[$0])
              }
            }
            .padding(.top, 8)
          } label: {
            Text(verbatim: "Steps").font(brandFont(16, 600)).foregroundStyle(Brand.Colors.ink)
          }
          .tint(Brand.Colors.magic)
          PrimaryButton(title: duplicate ? "Save another copy" : "Save to recipes", action: save)
            .padding(.top, 8)
          HStack {
            Button("Cancel", action: cancel)
            Spacer()
            Button(recipe.linesToCheck > 0 ? "Fix it in Cauldron" : "Edit in Cauldron", action: edit)
          }
          .font(brandFont(15, 500))
          .foregroundStyle(Brand.Colors.magic)
          .buttonStyle(.plain)
        }
        .tint(Brand.Colors.magic)
        .padding(16)
      }
    }

    private func stat(_ value: String, _ label: String) -> some View {
      VStack(spacing: 2) {
        Text(verbatim: value).font(monoFont(17)).foregroundStyle(Brand.Colors.ink)
        Text(verbatim: label).font(brandFont(12)).foregroundStyle(Brand.Colors.subtext)
      }
      .frame(maxWidth: .infinity)
    }
  }

  // MARK: - Variant C: system-style header, one section at a time

  /// Feels like Notes or Reminders' share sheet: Cancel and Save in a header row, the recipe
  /// under it with a segmented picker for ingredients, steps and macros. Edit lives in a menu.
  private struct VariantTabs: View {
    let recipe: ProtoRecipe
    let duplicate: Bool
    let save: () -> Void
    let edit: () -> Void
    let cancel: () -> Void

    enum Section: String, CaseIterable {
      case ingredients = "Ingredients"
      case steps = "Steps"
      case macros = "Macros"
    }

    @State private var section = Section.ingredients

    var body: some View {
      VStack(spacing: 0) {
        HStack {
          Button("Cancel", action: cancel)
          Spacer()
          Text(verbatim: "Cauldron").font(brandFont(17, 650)).foregroundStyle(Brand.Colors.ink)
          Spacer()
          Menu {
            Button("Save to recipes", action: save)
            Button("Edit in Cauldron", action: edit)
          } label: {
            Text(verbatim: "Save").font(brandFont(17, 650))
          } primaryAction: {
            save()
          }
        }
        .font(brandFont(17))
        .foregroundStyle(Brand.Colors.magic)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        Divider()
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 12) {
            if recipe.hasPhoto {
              ProtoPhoto(height: 56).frame(width: 56).clipShape(.rect(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: recipe.title).font(brandFont(18, 650)).foregroundStyle(Brand.Colors.ink)
                .lineLimit(2)
              Text(verbatim: "\(recipe.source) · \(recipe.time)").font(brandFont(13))
                .foregroundStyle(Brand.Colors.subtext)
            }
          }
          if duplicate { DuplicateBanner() }
          Picker("Section", selection: $section) {
            ForEach(Section.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
        }
        .padding(16)
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            switch section {
            case .ingredients:
              ForEach(recipe.ingredients.indices, id: \.self) {
                IngredientRow(line: recipe.ingredients[$0])
              }
            case .steps:
              ForEach(recipe.steps.indices, id: \.self) {
                StepRow(number: $0 + 1, text: recipe.steps[$0])
              }
            case .macros:
              Text(verbatim: "Per serving, estimated").font(brandFont(13))
                .foregroundStyle(Brand.Colors.subtext)
              MacroLine(macros: recipe.macros)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
        }
      }
    }
  }

  // MARK: - The other states

  private struct ProtoReading: View {
    let variant: ProtoVariant
    let source: ProtoSource
    let cancel: () -> Void

    var body: some View {
      VStack(spacing: 16) {
        Spacer()
        Image(systemName: "flame").font(.system(size: 40, weight: .light))
          .foregroundStyle(Brand.Colors.magic)
          .symbolEffect(.pulse)
        Text(verbatim: "Distilling…").font(brandFont(22, 650)).foregroundStyle(Brand.Colors.ink)
        Text(
          verbatim: source == .web
            ? "Reading the page, then the recipe." : "Reading the caption.")
          .font(brandFont(15)).foregroundStyle(Brand.Colors.subtext)
        ProgressView().tint(Brand.Colors.magic)
        Spacer()
        Button("Cancel", action: cancel).font(brandFont(15, 500)).foregroundStyle(Brand.Colors.magic)
          .buttonStyle(.plain)
          .padding(.bottom, 16)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private struct ProtoSaved: View {
    let title: String
    var body: some View {
      VStack(spacing: 12) {
        Image(systemName: "checkmark.circle").font(.system(size: 44, weight: .light))
          .foregroundStyle(Brand.Colors.fresh)
        Text(verbatim: "Saved").font(brandFont(22, 650)).foregroundStyle(Brand.Colors.ink)
        Text(verbatim: "\(title) is in your recipes.").font(brandFont(15))
          .foregroundStyle(Brand.Colors.subtext)
      }
      .multilineTextAlignment(.center)
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private struct ProtoFailed: View {
    let message: String
    let send: () -> Void
    let cancel: () -> Void
    var body: some View {
      VStack(spacing: 16) {
        Spacer()
        Image(systemName: "exclamationmark.circle").font(.system(size: 40, weight: .light))
          .foregroundStyle(Brand.Colors.heat)
        Text(verbatim: message).font(brandFont(15)).foregroundStyle(Brand.Colors.ink)
          .multilineTextAlignment(.center)
        PrimaryButton(title: "Send to Cauldron instead", action: send)
        Text(verbatim: "It opens as a draft next time you open Cauldron.").font(brandFont(13))
          .foregroundStyle(Brand.Colors.subtext)
        Spacer()
        Button("Cancel", action: cancel).font(brandFont(15, 500)).foregroundStyle(Brand.Colors.magic)
          .buttonStyle(.plain)
          .padding(.bottom, 16)
      }
      .padding(.horizontal, 24)
    }
  }

  // MARK: - The floating prototype bar (not part of the design)

  private struct ProtoSwitcher: View {
    @Binding var variant: ProtoVariant
    @Binding var phase: ProtoPhase
    @Binding var source: ProtoSource

    var body: some View {
      HStack(spacing: 10) {
        Button {
          variant = step(variant, by: -1)
        } label: {
          Image(systemName: "chevron.left")
        }
        Text(verbatim: variant.rawValue).font(.system(size: 13, weight: .semibold))
          .frame(minWidth: 110)
        Button {
          variant = step(variant, by: 1)
        } label: {
          Image(systemName: "chevron.right")
        }
        Divider().frame(height: 18).overlay(.white.opacity(0.4))
        Menu {
          Picker("State", selection: $phase) {
            ForEach(ProtoPhase.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
          }
          Picker("Recipe", selection: $source) {
            ForEach(ProtoSource.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
          }
        } label: {
          Text(verbatim: phase.rawValue).font(.system(size: 13, weight: .semibold))
        }
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(.black.opacity(0.85), in: .capsule)
      .shadow(radius: 6)
    }

    private func step<T: CaseIterable & Equatable>(_ value: T, by offset: Int) -> T
    where T.AllCases == [T] {
      let all = T.allCases
      let index = all.firstIndex(of: value) ?? 0
      return all[(index + offset + all.count) % all.count]
    }
  }

#endif
