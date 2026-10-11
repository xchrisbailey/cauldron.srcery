import CauldronKit
import SwiftData
import SwiftUI

/// Settings' Health section: what Cauldron does with Health, the switch that connects it (which
/// shows the system's permission prompt), and a check for new weights. Where Health can't be
/// used, a build without the setup or a device without Health, it says so instead. The work
/// is `HealthSync`.
struct HealthKitSection: View {
  @Environment(\.modelContext) private var context
  private let health = HealthSync.shared
  @State private var checking = false

  private let copy = Copy.settings.health

  var body: some View {
    Section {
      switch health.status {
      case .notSetUp:
        status(copy.notSetUp, systemImage: "heart.slash")
      case .unavailable:
        status(copy.unavailable, systemImage: "heart.slash")
      case .off, .on:
        Toggle(isOn: connected) {
          Text(verbatim: copy.connect.text)
        }
        .listRowBackground(Brand.Colors.mantle)
        if health.status == .on {
          Button(action: check) {
            Text(verbatim: copy.checkNow.text)
          }
          .disabled(checking)
          .listRowBackground(Brand.Colors.mantle)
          if let count = health.lastImportCount {
            Text(verbatim: (count == 0 ? copy.upToDate : copy.imported(count)).text)
              .brandText(.control)
              .foregroundStyle(Brand.Colors.subtext)
              .listRowBackground(Brand.Colors.mantle)
          }
        }
      }
      if let failure = health.failure {
        Label {
          Text(verbatim: failure.text).brandText(.body)
        } icon: {
          Image(systemName: "exclamationmark.triangle").foregroundStyle(Brand.Colors.heat)
        }
        .listRowBackground(Brand.Colors.mantle)
      }
    } header: {
      Text(verbatim: copy.title.text)
    } footer: {
      Text(verbatim: copy.explanation.text)
    }
  }

  private func status(_ text: CopyString, systemImage: String) -> some View {
    Label {
      Text(verbatim: text.text).brandText(.body)
    } icon: {
      Image(systemName: systemImage).foregroundStyle(Brand.Colors.subtext)
    }
    .listRowBackground(Brand.Colors.mantle)
  }

  private var connected: Binding<Bool> {
    Binding(
      get: { health.status == .on },
      set: { on in
        if on {
          Task {
            await health.connect()
            await checkNow()
          }
        } else {
          health.disconnect()
        }
      })
  }

  private func check() {
    Task { await checkNow() }
  }

  private func checkNow() async {
    guard let today = TargetsForm.today() else { return }
    checking = true
    await health.importWeights(into: context, today: today)
    checking = false
  }
}

#Preview {
  Form { HealthKitSection() }
}
