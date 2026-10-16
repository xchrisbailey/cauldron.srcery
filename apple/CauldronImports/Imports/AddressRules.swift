import Foundation

/// Which links the fetcher will open: `RemoteFetch.ts`'s address rules, sized for a device. A
/// page can point a redirect, or its cover image, at the cook's router or printer, and a GET
/// there can do something. These checks apply to the first request, every redirect hop and the
/// cover image alike, because they all go through `URLSessionPageFetcher.checked`.
///
/// What this does NOT cover: a public name that resolves to a private address (DNS rebinding,
/// or a name someone pointed at 192.168.0.1). Catching that needs the resolved address, and the
/// device has no resolver of its own to ask. The rules judge the link as written.
public enum AddressRules {
  /// Why a link isn't one to open, or nil when it is. The answer is `FetchError.blocked`'s
  /// `detail`.
  public static func refusal(for url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      return "scheme"
    }
    guard let host = url.host(percentEncoded: true), !host.isEmpty else { return "scheme" }
    if url.user != nil || url.password != nil { return "credentials" }
    if let port = url.port, port != (scheme == "https" ? 443 : 80) { return "port" }
    return refusal(forHost: host)
  }

  /// `host` as `URL.host` gives it: brackets removed from an IPv6 address, internationalised
  /// names already in punycode.
  public static func refusal(forHost host: String) -> String? {
    var host = host.lowercased()
    while host.hasSuffix(".") { host.removeLast() }
    if host.isEmpty { return "host" }
    if host.contains(":") {
      guard let bytes = ipv6(host) else { return "address" }
      return isPrivate(v6: bytes) ? "address" : nil
    }
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    // A host whose last label is a number is an IPv4 address in one of its spellings
    // (2130706433, 0x7f.1, 127.1, 0177.0.0.1), however `URL` wrote it down. One that doesn't
    // parse as such is refused rather than guessed at.
    if let last = labels.last, isNumeric(last) {
      guard let address = ipv4(labels) else { return "address" }
      return isPrivate(v4: address) ? "address" : nil
    }
    if host == "localhost" { return "host" }
    for suffix in [".local", ".localhost", ".internal", ".lan", ".home.arpa"]
    where host.hasSuffix(suffix) {
      return "host"
    }
    return nil
  }

  // MARK: IPv4

  private static func isNumeric(_ label: Substring) -> Bool {
    if label.isEmpty { return false }
    if label.hasPrefix("0x") { return label.dropFirst(2).allSatisfy(\.isHexDigit) }
    return label.allSatisfy(\.isASCIIDigit)
  }

  /// One part of a dotted address: hex after `0x`, octal after a leading `0`, else decimal.
  private static func number(_ part: Substring) -> UInt64? {
    if part.isEmpty { return nil }
    if part.hasPrefix("0x") { return part.count == 2 ? 0 : UInt64(part.dropFirst(2), radix: 16) }
    if part.count > 1, part.hasPrefix("0") { return UInt64(part.dropFirst(), radix: 8) }
    return UInt64(part, radix: 10)
  }

  /// The address a host of one to four numbers stands for, as `inet_aton` reads it: the last
  /// number fills the bytes that are left.
  public static func ipv4(_ labels: [Substring]) -> UInt32? {
    guard (1...4).contains(labels.count) else { return nil }
    let numbers = labels.compactMap(number)
    guard numbers.count == labels.count else { return nil }
    var address: UInt64 = 0
    for part in numbers.dropLast() {
      guard part <= 255 else { return nil }
      address = (address << 8) | part
    }
    let last = numbers[numbers.count - 1]
    let room = 8 * (5 - labels.count)
    guard last < (UInt64(1) << UInt64(room)) else { return nil }
    return UInt32(truncatingIfNeeded: (address << UInt64(room)) | last)
  }

  public static func isPrivate(v4 address: UInt32) -> Bool {
    func within(_ base: UInt32, _ bits: Int) -> Bool {
      let mask: UInt32 = bits == 0 ? 0 : ~UInt32(0) << UInt32(32 - bits)
      return address & mask == base & mask
    }
    return within(0x0000_0000, 8)  // unspecified and "this network"
      || within(0x0A00_0000, 8)  // 10/8
      || within(0x6440_0000, 10)  // 100.64/10, carrier-grade NAT
      || within(0x7F00_0000, 8)  // loopback
      || within(0xA9FE_0000, 16)  // 169.254/16, link-local
      || within(0xAC10_0000, 12)  // 172.16/12
      || within(0xC0A8_0000, 16)  // 192.168/16
      || within(0xE000_0000, 4)  // multicast
      || within(0xF000_0000, 4)  // reserved, with the broadcast address
  }

  // MARK: IPv6

  private static func ipv6(_ host: String) -> [UInt8]? {
    // A zone ("fe80::1%en0") only means something on this machine's own network.
    if host.contains("%") { return nil }
    var address = in6_addr()
    guard inet_pton(AF_INET6, host, &address) == 1 else { return nil }
    return withUnsafeBytes(of: &address) { Array($0) }
  }

  public static func isPrivate(v6 bytes: [UInt8]) -> Bool {
    guard bytes.count == 16 else { return true }
    func embedded(at offset: Int) -> UInt32 {
      bytes[offset...].prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }
    let leadingZeros = bytes[0..<10].allSatisfy { $0 == 0 }
    // :: and ::1.
    if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] <= 1 { return true }
    // IPv4-mapped (::ffff:a.b.c.d) and the old IPv4-compatible (::a.b.c.d) forms.
    if leadingZeros && bytes[10] == 0xFF && bytes[11] == 0xFF {
      return isPrivate(v4: embedded(at: 12))
    }
    if bytes[0..<12].allSatisfy({ $0 == 0 }) { return isPrivate(v4: embedded(at: 12)) }
    // NAT64 (64:ff9b::/96) carries an IPv4 address in the same place.
    if bytes[0] == 0x00, bytes[1] == 0x64, bytes[2] == 0xFF, bytes[3] == 0x9B,
      bytes[4..<12].allSatisfy({ $0 == 0 })
    {
      return isPrivate(v4: embedded(at: 12))
    }
    // 6to4 (2002::/16) carries one right after the prefix.
    if bytes[0] == 0x20, bytes[1] == 0x02 { return isPrivate(v4: embedded(at: 2)) }
    if bytes[0] & 0xFE == 0xFC { return true }  // fc00::/7, unique local
    if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return true }  // fe80::/10, link-local
    if bytes[0] == 0xFF { return true }  // multicast
    return false
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool { "0"..."9" ~= self }
}
