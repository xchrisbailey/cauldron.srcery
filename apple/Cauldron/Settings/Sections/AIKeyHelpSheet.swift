import CauldronKit
import SwiftUI

/// How to make an API key for a provider: a few steps and a link to its key page.
struct AIKeyHelpSheet: View {
  let provider: AIProvider
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          ForEach(Array(Copy.settings.ai.keySteps(provider).enumerated()), id: \.offset) {
            index, step in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text(index + 1, format: .number)
                .brandText(.quantity)
                .foregroundStyle(Brand.Colors.magic)
              Text(verbatim: step.text)
                .brandText(.body)
                .foregroundStyle(Brand.Colors.ink)
            }
            .listRowBackground(Brand.Colors.mantle)
          }
        } footer: {
          Text(verbatim: Copy.settings.ai.keyPrivacy.text)
        }
        if let page = provider.keyPage {
          Section {
            Link(destination: page) {
              Label {
                Text(verbatim: Copy.settings.ai.openKeyPage(provider).text)
              } icon: {
                Image(systemName: "arrow.up.right.square")
              }
            }
            .brandText(.control)
            .listRowBackground(Brand.Colors.mantle)
          }
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
      .navigationTitle(Copy.settings.ai.keyHelpTitle(provider).text)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text(verbatim: Copy.settings.ai.done.text)
          }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 360)
    #endif
  }
}

#Preview {
  AIKeyHelpSheet(provider: .anthropic)
}
