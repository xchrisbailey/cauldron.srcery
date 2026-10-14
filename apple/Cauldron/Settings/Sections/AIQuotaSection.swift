import CauldronKit
import SwiftData
import SwiftUI

/// Settings' section for the AI: which provider, its key and model, and a line that says how
/// things stand. A missing or refused key and a spent quota show here as a line that stays, never
/// as an alert.
struct AIQuotaSection: View {
  @Environment(RecipeAIService.self) private var ai
  @Environment(\.modelContext) private var context
  @Query private var jobs: [AIJobRecord]
  @Query private var recipes: [RecipeRecord]
  @State private var draft = ""

  private var waiting: Int {
    jobs.count { $0.status != .failed }
  }

  private var missing: Int {
    recipes.count(where: RecipeMacroEstimates.isMissingMacros)
  }

  var body: some View {
    Section {
      Picker(
        selection: Binding(
          get: { ai.provider },
          set: { provider in
            // The key being typed belongs to the provider it was typed for.
            draft = ""
            AIQueueRunner.switchProvider(to: provider, in: context, ai: ai)
          })
      ) {
        ForEach(AIProvider.allCases, id: \.self) { provider in
          Text(verbatim: provider.displayName).tag(provider)
        }
      } label: {
        Text(verbatim: Copy.settings.ai.providerLabel.text)
      }
      .listRowBackground(Brand.Colors.mantle)
      AIStatusLine(status: ai.status)
        .listRowBackground(Brand.Colors.mantle)
      #if DEBUG
        // Debug builds only: why the last answer couldn't be used, to tell a bug from a bad answer.
        if let failure = ai.lastFailure {
          Text(verbatim: failure)
            .brandText(.quantity)
            .foregroundStyle(Brand.Colors.heat)
            .listRowBackground(Brand.Colors.mantle)
        }
      #endif
      if waiting > 0 {
        Text(verbatim: Copy.settings.ai.waiting(waiting).text)
          .brandText(.quantity)
          .foregroundStyle(Brand.Colors.subtext)
          .listRowBackground(Brand.Colors.mantle)
      }
      if missing > 0 {
        Button {
          RecipeMacroEstimates.requestAllMissing(in: context)
          Task { await AIQueueRunner.drain(in: context, using: ai.estimator) }
        } label: {
          Text(verbatim: Copy.settings.ai.estimateMissing(missing).text)
        }
        .listRowBackground(Brand.Colors.mantle)
      } else if !recipes.isEmpty {
        Text(verbatim: Copy.settings.ai.nothingMissing.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.subtext)
          .listRowBackground(Brand.Colors.mantle)
      }
      SecureField(
        text: $draft,
        prompt: Text(
          verbatim: ai.hasKey
            ? Copy.settings.ai.keySaved.text : Copy.settings.ai.keyPlaceholder.text)
      ) {
        Text(verbatim: Copy.settings.ai.keyLabel(ai.provider).text)
      }
      .autocorrectionDisabled()
      .listRowBackground(Brand.Colors.mantle)
      if ai.keyNotSaved {
        Text(verbatim: Copy.settings.ai.keyNotSaved.text)
          .brandText(.control)
          .foregroundStyle(Brand.Colors.heat)
          .listRowBackground(Brand.Colors.mantle)
      }
      Button {
        guard ai.saveKey(draft) else { return }
        draft = ""
        // Whatever was waiting for a key can run now.
        Task { await AIQueueRunner.drain(in: context, using: ai.estimator) }
      } label: {
        Text(verbatim: Copy.settings.ai.saveKey.text)
      }
      .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .listRowBackground(Brand.Colors.mantle)
      if ai.hasKey {
        Button(role: .destructive) {
          ai.removeKey()
        } label: {
          Text(verbatim: Copy.settings.ai.removeKey.text)
        }
        .listRowBackground(Brand.Colors.mantle)
      }
      AIModelField(provider: ai.provider)
        .id(ai.provider)
        .listRowBackground(Brand.Colors.mantle)
    } header: {
      Text(verbatim: Copy.settings.ai.title.text)
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: Copy.settings.ai.modelHint(ai.provider.defaultModel).text)
        Text(verbatim: Copy.settings.ai.hint(ai.provider).text)
      }
    }
  }
}

/// The model field for one provider. Its key in `UserDefaults` is fixed when the view is made,
/// so the section makes a new one when the provider changes.
private struct AIModelField: View {
  let provider: AIProvider
  @AppStorage private var model: String

  init(provider: AIProvider) {
    self.provider = provider
    _model = AppStorage(wrappedValue: "", RecipeAIService.modelDefaultsKey(for: provider))
  }

  var body: some View {
    TextField(text: $model, prompt: Text(verbatim: provider.defaultModel)) {
      Text(verbatim: Copy.settings.ai.modelLabel.text)
    }
    .autocorrectionDisabled()
    #if os(iOS)
      .textInputAutocapitalization(.never)
    #endif
  }
}

extension RecipeAIStatus {
  /// What the status line says, naming `provider`.
  func message(for provider: AIProvider) -> CopyString {
    switch self {
    case .ready: Copy.settings.ai.ready(provider)
    case .missingKey: Copy.settings.ai.missingKey(provider)
    case .invalidKey: Copy.settings.ai.invalidKey(provider)
    case .rateLimited: Copy.settings.ai.rateLimited(provider)
    case .invalidModel: Copy.settings.ai.invalidModel(provider)
    }
  }

  var needsAttention: Bool { self != .ready }
}

/// How the AI stands, as one line. It sits in Settings and beside AI actions.
struct AIStatusLine: View {
  @Environment(RecipeAIService.self) private var ai
  let status: RecipeAIStatus

  var body: some View {
    Label {
      Text(verbatim: status.message(for: ai.provider).text)
        .brandText(.body)
    } icon: {
      Image(systemName: status.needsAttention ? "exclamationmark.circle" : "sparkles")
        .foregroundStyle(status.needsAttention ? Brand.Colors.heat : Brand.Colors.magic)
    }
    .accessibilityElement(children: .combine)
  }
}
