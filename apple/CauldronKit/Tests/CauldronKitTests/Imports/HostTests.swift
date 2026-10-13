import Foundation
import Testing

@testable import CauldronKit

/// Hosts as `new URL` writes them, pinned under Bun: IPv4 in every spelling, IPv6, and
/// internationalised names. The app decides whether a link points at the cook's own network
/// from the host, so a spelling of 127.0.0.1 that stays literal would defeat it.
@Suite("Hosts against the reference")
struct HostTests {
  static let hosts: [JSONValue] = (try? Fixtures.json("pinned/hosts.json").items) ?? []

  @Test func hasAtLeastFortyHosts() {
    #expect(Self.hosts.count >= 40)
  }

  @Test(arguments: hosts)
  func writesTheHostLikeTheReference(entry: JSONValue) throws {
    let host = try #require(entry["in"].string)
    let got = WebURL.parse("https://\(host)/p?q=1")?.string
    #expect(got == entry["out"].string, "host \(host.debugDescription)")
  }

  @Test func foldsAFullwidthSocialHostSoItClassifies() {
    #expect(Distill.classify("https://ｉｎｓｔａｇｒａｍ.com/p/abc") == .instagram)
    #expect(Distill.classify("https://0x7f.1/") == .web)
    #expect(WebURL.parse("https://2130706433/")?.host == "127.0.0.1")
  }
}
