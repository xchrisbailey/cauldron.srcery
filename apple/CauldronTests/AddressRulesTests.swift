import CauldronKit
import Foundation
import Testing

@testable import Cauldron

/// Which links the fetcher refuses to open, judged on the link as written.
@Suite("Address rules")
struct AddressRulesTests {
  private func refusal(_ link: String) -> String? {
    guard let url = URL(string: link) else { return "unparseable" }
    return AddressRules.refusal(for: url)
  }

  @Test(
    "refuses links to this machine and the cook's own network",
    arguments: [
      // Names.
      "http://localhost/", "http://LOCALHOST./", "https://localhost/admin",
      "http://printer.local/", "http://router.localhost/", "https://nas.internal/",
      "http://box.lan/", "http://router.home.arpa/", "http://a.b.printer.local./",
      // IPv4, plainly written.
      "http://127.0.0.1/", "http://127.255.255.254/", "http://0.0.0.0/", "http://10.0.0.1/",
      "http://10.255.255.255/", "http://172.16.0.1/", "http://172.31.255.255/",
      "http://192.168.1.1/", "http://169.254.169.254/", "http://100.64.0.1/",
      "http://100.127.255.255/", "http://224.0.0.1/", "http://239.255.255.250/",
      "http://255.255.255.255/",
      // IPv4, however URL keeps the spelling: decimal, hex, octal, shortened.
      "http://2130706433/", "http://0x7f000001/", "http://0x7f.1/", "http://127.1/",
      "http://0177.0.0.1/", "http://0300.0250.0.1/", "http://3232235777/", "http://10.1/",
      "http://0/", "http://0x0a.0.0.1/",
      // IPv6.
      "http://[::1]/", "http://[::]/", "http://[fc00::1]/", "http://[fd12:3456::1]/",
      "http://[fe80::1]/", "http://[febf::1]/", "http://[ff02::1]/",
      "http://[::ffff:127.0.0.1]/", "http://[::ffff:7f00:1]/", "http://[::ffff:192.168.0.1]/",
      "http://[::ffff:10.0.0.1]/", "http://[::127.0.0.1]/", "http://[64:ff9b::7f00:1]/",
      "http://[2002:7f00:1::]/",
      // Other ports, whichever the scheme.
      "http://example.com:8080/", "https://example.com:8443/", "https://example.com:80/",
      "http://example.com:443/", "https://example.com:0/",
      // Not a web link, or credentials.
      "ftp://example.com/", "file:///etc/hosts", "https://user:pass@example.com/",
      "https://user@example.com/",
    ])
  func refuses(_ link: String) {
    #expect(refusal(link) != nil, "\(link)")
  }

  @Test(
    "allows public sites, in any spelling URL keeps",
    arguments: [
      "https://www.bbcgoodfood.com/recipes/easy-pancakes", "http://example.com/",
      "https://example.com:443/x", "http://example.com:80/x", "https://sub.example.co.uk/a?b=c",
      "https://xn--e1afmkfd.xn--p1ai/x", "https://bad.cafe/", "https://a.face.b/",
      "https://localhost.example.com/", "https://mylocal.com/", "https://lan.example.org/",
      "http://8.8.8.8/", "http://172.15.0.1/", "http://172.32.0.1/", "http://100.63.255.255/",
      "http://100.128.0.1/", "http://169.253.0.1/", "http://192.167.1.1/", "http://11.0.0.1/",
      "http://[2606:4700:4700::1111]/", "http://[2001:db8::1]/", "http://[::ffff:8.8.8.8]/",
      "http://0x08080808/", "http://134744072/",
    ])
  func allows(_ link: String) {
    #expect(refusal(link) == nil, "\(link) was refused: \(refusal(link) ?? "")")
  }

  @Test func theReasonIsTheMostUsefulOneAndNeverEmpty() {
    #expect(refusal("http://127.0.0.1/") == "address")
    #expect(refusal("http://localhost/") == "host")
    #expect(refusal("http://example.com:8080/") == "port")
    #expect(refusal("https://u:p@example.com/") == "credentials")
    #expect(refusal("ftp://example.com/") == "scheme")
  }

  @Test func aNumericHostThatIsNotAnAddressIsRefusedNotGuessedAt() {
    for host in ["1.2.3.4.5", "256.1.1.1", "999999999999", "0x1ffffffff", "08.1.1.1", "1..2"] {
      #expect(AddressRules.refusal(forHost: host) != nil, "\(host)")
    }
  }

  @Test func theFetcherAppliesTheSameRuleAsTheFirstGate() {
    for link in ["http://127.0.0.1/", "http://localhost/", "https://example.com:9999/"] {
      #expect(throws: FetchError.self) { try URLSessionPageFetcher.checked(link) }
    }
    #expect(throws: Never.self) { try URLSessionPageFetcher.checked("https://example.com/") }
  }
}
