import Testing

@testable import CauldronKit

@Suite("JavaScript trim")
struct JSTrimTests {
  @Test func stripsTheWhiteSpaceAndLineTerminatorSet() {
    let set: [Unicode.Scalar] =
      Array((0x09...0x0D).compactMap(Unicode.Scalar.init))
      + [0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF].compactMap(
        Unicode.Scalar.init)
      + (0x2000...0x200A).compactMap(Unicode.Scalar.init)
    for scalar in set {
      #expect("\(scalar)a b\(scalar)".jsTrimmed() == "a b", "U+\(String(scalar.value, radix: 16))")
    }
  }

  @Test func keepsEverythingElse() {
    for scalar in [0x85, 0x180E, 0x200B, 0x2060, 0x0].compactMap(Unicode.Scalar.init) {
      #expect("\(scalar)a\(scalar)".jsTrimmed() == "\(scalar)a\(scalar)")
    }
  }

  @Test func handlesEmptyAndAllWhitespace() {
    #expect("".jsTrimmed() == "")
    #expect(" \u{FEFF}\r\n\t".jsTrimmed() == "")
  }

  @Test func treatsCRLFAsTwoCharacters() {
    #expect("\r\nx\r\n".jsTrimmed() == "x")
  }
}
