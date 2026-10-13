import CauldronKit
import SwiftUI

/// Settings: appearance, the iCloud status, and one section for each feature that adds its own
/// (export, HealthKit, AI quota). Those three are views of their own in `Sections/`, so
/// replacing one doesn't touch this file.
struct SettingsView: View {
  @AppStorage(AppearanceChoice.storageKey) private var appearance = AppearanceChoice.system
  @Environment(SyncStatusModel.self) private var sync

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker(selection: $appearance) {
            ForEach(AppearanceChoice.allCases) { choice in
              Text(verbatim: choice.label.text).tag(choice)
            }
          } label: {
            Text(verbatim: Copy.settings.appearance.title.text)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .listRowBackground(Brand.Colors.mantle)
        } header: {
          Text(verbatim: Copy.settings.appearance.title.text)
        } footer: {
          Text(verbatim: Copy.settings.appearance.hint.text)
        }

        Section {
          SyncStatusRow(status: sync.status)
            .listRowBackground(Brand.Colors.mantle)
        } header: {
          Text(verbatim: Copy.settings.iCloud.title.text)
        }

        ExportSection()
        HealthKitSection()
        AIQuotaSection()
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(Brand.Colors.base)
      .navigationTitle(Copy.settings.title.text)
    }
  }
}

/// The iCloud status line.
struct SyncStatusRow: View {
  let status: ICloudStatus

  var body: some View {
    Label {
      Text(verbatim: status.message.text)
        .brandText(.body)
    } icon: {
      Image(systemName: status.systemImage)
        .foregroundStyle(status.needsAttention ? Brand.Colors.heat : Brand.Colors.magic)
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  SettingsView()
    .environment(SyncStatusModel(account: LiveICloudAccount(mode: .inMemory)))
    .environment(RecipeAIService.offline())
}
