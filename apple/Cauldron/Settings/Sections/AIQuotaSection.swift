import CauldronKit
import SwiftData
import SwiftUI

/// Settings' section for the AI: the Gemini key, the model, and a line that says how things
/// stand. A missing or refused key and a spent quota show here as a line that stays, never
/// as an alert.
struct AIQuotaSection: View {
  @Environment(RecipeAIService.self) private var ai
  @Environment(\.modelContext) private var context
  @Query private var jobs: [AIJobRecord]
  @AppStorage(RecipeAIService.modelDefaultsKey) private var model = ""
  @State private var draft = ""

  private var waiting: Int {
    jobs.count { $0.status != .failed }
  }

  var body: some View {
    Section {
      AIStatusLine(status: ai.status)
        .listRowBackground(Brand.Colors.mantle)
      if waiting > 0 {
        Text(verbatim: Copy.settings.ai.waiting(waiting).text)
          .brandText(.quantity)
          .foregroundStyle(Brand.Colors.subtext)
          .listRowBackground(Brand.Colors.mantle)
      }
      SecureField(
        text: $draft,
        prompt: Text(
          verbatim: ai.hasKey
            ? Copy.settings.ai.keySaved.text : Copy.settings.ai.keyPlaceholder.text)
      ) {
        Text(verbatim: Copy.settings.ai.keyLabel.text)
      }
      .textContentType(.password)
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
        Task { await AIJobQueue.drain(in: context, using: ai.estimator) }
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
      TextField(
        text: $model, prompt: Text(verbatim: Gemini.defaultModel)
      ) {
        Text(verbatim: Copy.settings.ai.modelLabel.text)
      }
      .autocorrectionDisabled()
      #if os(iOS)
        .textInputAutocapitalization(.never)
      #endif
      .listRowBackground(Brand.Colors.mantle)
    } header: {
      Text(verbatim: Copy.settings.ai.title.text)
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: Copy.settings.ai.modelHint(Gemini.defaultModel).text)
        Text(verbatim: Copy.settings.ai.hint.text)
      }
    }
  }
}

extension RecipeAIStatus {
  /// What the status line says.
  var message: CopyString {
    switch self {
    case .ready: Copy.settings.ai.ready
    case .missingKey: Copy.settings.ai.missingKey
    case .invalidKey: Copy.settings.ai.invalidKey
    case .rateLimited: Copy.settings.ai.rateLimited
    }
  }

  var needsAttention: Bool { self != .ready }
}

/// How the AI stands, as one line. It sits in Settings and beside AI actions.
struct AIStatusLine: View {
  let status: RecipeAIStatus

  var body: some View {
    Label {
      Text(verbatim: status.message.text)
        .brandText(.body)
    } icon: {
      Image(systemName: status.needsAttention ? "exclamationmark.circle" : "sparkles")
        .foregroundStyle(status.needsAttention ? Brand.Colors.heat : Brand.Colors.magic)
    }
    .accessibilityElement(children: .combine)
  }
}
