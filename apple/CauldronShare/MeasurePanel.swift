// MEASUREMENT, throwaway. Debug builds only. Ticket #197.
//
// What does reading a recipe cost inside the share extension? For the shared link: whether the
// on-device model answers here, and the extension's peak memory while it fetches and distills
// the page. No cloud model call and no keychain read: the AI key stays where the app keeps it.
// Everything shown is also logged (subsystem computer.srcery.cauldron.share, category measure).
#if DEBUG

  import CauldronKit
  import Darwin
  import Foundation
  import FoundationModels
  import OSLog
  import Synchronization
  import SwiftUI

  // MARK: - Memory

  enum MemoryProbe {
    /// The process's `phys_footprint`, what jetsam counts against the extension's limit.
    static func footprint() -> UInt64 {
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
      let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
      }
      return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// How much more the extension may use before it is killed. iOS only.
    static func available() -> UInt64? {
      #if os(iOS)
        UInt64(os_proc_available_memory())
      #else
        nil
      #endif
    }
  }

  /// Samples the footprint every 100 ms and keeps the peak.
  final class PeakSampler: Sendable {
    struct Peak: Sendable {
      var footprint: UInt64 = 0
      var availableAtPeak: UInt64?
    }

    private let peak = Mutex(Peak())
    private let running = Mutex<Task<Void, Never>?>(nil)

    func start() {
      sample()
      let task = Task.detached { [self] in
        while !Task.isCancelled {
          sample()
          try? await Task.sleep(for: .milliseconds(100))
        }
      }
      running.withLock { $0 = task }
    }

    func stop() -> Peak {
      running.withLock { $0?.cancel() }
      sample()
      return peak.withLock { $0 }
    }

    private func sample() {
      let now = MemoryProbe.footprint()
      peak.withLock {
        if now > $0.footprint {
          $0.footprint = now
          $0.availableAtPeak = MemoryProbe.available()
        }
      }
    }
  }

  // MARK: - Fetching

  /// A plain fetcher for the measurement: ephemeral session, body capped at `maxBytes`.
  final class MeasureFetcher: PageFetcher {
    let bytesRead = Mutex(0)

    private static let session: URLSession = {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 15
      configuration.timeoutIntervalForResource = 30
      return URLSession(configuration: configuration)
    }()

    func fetch(_ request: CauldronKit.FetchRequest) async throws(FetchError) -> FetchedPage {
      guard let url = URL(string: request.url) else { throw .blocked(detail: "scheme") }
      var urlRequest = URLRequest(url: url)
      urlRequest.setValue(request.accept, forHTTPHeaderField: "Accept")
      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await Self.session.data(for: urlRequest)
      } catch {
        if error is CancellationError { throw .cancelled }
        if (error as? URLError)?.code == .timedOut { throw .timeout }
        throw .unreachable()
      }
      let http = response as? HTTPURLResponse
      let status = http?.statusCode ?? 0
      guard (200...299).contains(status) else { throw .status(status) }
      guard data.count <= request.maxBytes else { throw .tooLarge }
      bytesRead.withLock { $0 += data.count }
      return FetchedPage(
        bytes: data, contentType: http?.value(forHTTPHeaderField: "Content-Type"),
        url: response.url?.absoluteString ?? request.url)
    }
  }

  private func elapsed(since start: ContinuousClock.Instant) -> String {
    let parts = (ContinuousClock.now - start).components
    return "\(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000) ms"
  }

  private func megabytes(_ bytes: UInt64?) -> String {
    guard let bytes else { return "n/a" }
    return String(format: "%.1f MB", Double(bytes) / 1_048_576)
  }

  // MARK: - Run

  @MainActor @Observable
  final class Measurement {
    var lines: [String] = []
    var running = false

    @ObservationIgnored
    private let log = Logger(subsystem: "computer.srcery.cauldron.share", category: "measure")

    private func say(_ line: String) {
      lines.append(line)
      log.notice("\(line, privacy: .public)")
    }

    func run(link: String?) async {
      guard !running else { return }
      running = true
      defer { running = false }
      lines = []
      say("link: \(link ?? "none")")
      say(
        "start: footprint \(megabytes(MemoryProbe.footprint())), "
          + "available \(megabytes(MemoryProbe.available()))")
      await foundationModels()
      if let link { await importCost(link) }
      say("done")
    }

    /// Whether the on-device model is available here, and one tiny prompt.
    private func foundationModels() async {
      say("FM availability: \(SystemLanguageModel.default.availability)")
      let started = ContinuousClock.now
      do {
        let session = LanguageModelSession()
        let response = try await session.respond(to: "Reply with the single word: ready")
        say("FM ok: \"\(response.content.prefix(40))\" in \(elapsed(since: started))")
      } catch {
        let detail = String(describing: error)
        let rate = detail.localizedCaseInsensitiveContains("rateLimited") ? " [RATE LIMITED]" : ""
        say("FM error\(rate): \(detail) after \(elapsed(since: started))")
      }
    }

    /// Fetches and distills the page with no model, sampling the footprint throughout.
    private func importCost(_ link: String) async {
      let sampler = PeakSampler()
      let fetcher = MeasureFetcher()
      sampler.start()
      let started = ContinuousClock.now
      do {
        let distilled = try await Distill.url(link, fetcher: fetcher, extractor: nil)
        say(
          "distill ok via \(distilled.extractor.rawValue): \"\(distilled.draft.title.prefix(50))\", "
            + "\(distilled.draft.ingredients.count) ingredients, \(elapsed(since: started))")
      } catch {
        say("distill failed \(error) after \(elapsed(since: started))")
      }
      say("fetched \(fetcher.bytesRead.withLock { $0 }) bytes")
      let peak = sampler.stop()
      say(
        "peak footprint \(megabytes(peak.footprint)), available at peak "
          + "\(megabytes(peak.availableAtPeak)), available now \(megabytes(MemoryProbe.available()))"
      )
    }
  }

  // MARK: - Panel

  struct MeasurePanel: View {
    let link: String?
    let close: () -> Void
    @State private var measurement = Measurement()

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(verbatim: "Measure · #197").font(.headline)
          Spacer()
          Button {
            Task { await measurement.run(link: link) }
          } label: {
            Text(verbatim: measurement.running ? "Running…" : "Measure")
          }
          .disabled(measurement.running)
          Button(action: close) { Text(verbatim: "Close") }
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(measurement.lines.enumerated()), id: \.offset) { _, line in
              Text(verbatim: line)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }
      .padding(16)
      .foregroundStyle(Brand.Colors.ink)
      .background(Brand.Colors.base)
    }
  }

#endif
