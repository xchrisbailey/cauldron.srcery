import Foundation
import Testing

@testable import CauldronKit

/// The JavaScript rules the ports lean on, pinned to what the reference's engine answers.
@Suite("JavaScript compatibility")
struct JSCompatTests {
  @Test(
    arguments: [
      (0.125, 2, "0.13"), (0.375, 2, "0.38"), (2.5, 0, "3"), (0.5, 0, "1"), (1.005, 2, "1.00"),
      (0.024999999999999998, 2, "0.02"), (1.45, 1, "1.4"), (1e21, 2, "1e+21"),
      (-0.125, 2, "-0.13"), (0.045, 2, "0.04"), (10.005, 2, "10.01"), (99.95, 1, "100.0"),
      (0.05, 2, "0.05"), (5e-324, 2, "0.00"),
    ] as [(Double, Int, String)])
  func toFixedRoundsTheExactValueAndSendsTiesUp(x: Double, digits: Int, expected: String) {
    #expect(jsToFixed(x, digits) == expected)
  }

  @Test(
    arguments: [
      (1e21, "1e+21"), (1e-7, "1e-7"), (0.000001, "0.000001"),
      (123_456_789_012_345_680_000, "123456789012345680000"), (1.5e300, "1.5e+300"),
      (5e-324, "5e-324"), (100, "100"), (0.1 + 0.2, "0.30000000000000004"), (-0.0, "0"),
      (1e20, "100000000000000000000"), (12_345_678_901_234_567_890, "12345678901234567000"),
      (0.00001234, "0.00001234"), (.nan, "NaN"), (-.infinity, "-Infinity"), (-2.5, "-2.5"),
    ] as [(Double, String)])
  func stringOfANumber(x: Double, expected: String) {
    #expect(jsString(x) == expected)
  }

  @Test func roundsHalvesUp() {
    #expect(jsRound(2.5) == 3)
    #expect(jsRound(-2.5) == -2)
    #expect(jsRound(0.49999999999999994) == 0)
    #expect(jsRound(-0.4).sign == .minus)
  }

  @Test func maxIsNaNIfEitherIs() {
    #expect(jsMax(0.5, .nan).isNaN)
    #expect(jsMax(.nan, 0.5).isNaN)
    #expect(jsMax(0.5, 2) == 2)
  }

  @Test(
    arguments: [
      (" 6 ", 6.0), ("0x10", 16), ("1e3", 1000), ("Infinity", .infinity),
      ("-Infinity", -.infinity), ("+5", 5), ("", 0), ("5.", 5), (".5", 0.5), ("0b101", 5),
      ("0o17", 15), ("  ", 0),
    ] as [(String, Double)])
  func numberOfAString(text: String, expected: Double) {
    #expect(jsNumber(text) == expected)
  }

  @Test(arguments: ["abc", "1_000", ".", "-0x10", "1e", "1 2", "٣"])
  func numberOfAnythingElseIsNaN(text: String) {
    #expect(jsNumber(text).isNaN)
  }

  @Test func lowercasesLikeJavaScript() {
    #expect(jsLowercased("ΟΔΟΣ") == "οδος")
    #expect(jsLowercased("ΑΣ Β") == "ας β")
    #expect(jsLowercased("Σ") == "σ")
    #expect(jsLowercased("ΑΣ.") == "ας.")
    #expect(jsLowercased("İ") == "i\u{307}")
  }

  @Test(
    arguments: [
      (1249.6, "1,250"), (0.5, "1"), (-0.4, "-0"), (999.5, "1,000"),
      (1e21, "1,000,000,000,000,000,000,000"), (.nan, "NaN"), (-1234.5, "-1,234"),
      (1e25, "10,000,000,000,000,000,000,000,000"), (-0.0, "-0"),
    ] as [(Double, String)])
  func groupsARoundedNumberLikeToLocaleString(x: Double, expected: String) {
    #expect(jsGroupedRounded(x) == expected)
  }

  @Test func whitespaceIsJavaScriptsNotUnicodes() {
    #expect(Unicode.Scalar(0xFEFF)?.isJSSpace == true)
    #expect(Unicode.Scalar(0xA0)?.isJSSpace == true)
    #expect(Unicode.Scalar(0x2028)?.isJSSpace == true)
    #expect(Unicode.Scalar(0x85)?.isJSSpace == false)
    #expect(Unicode.Scalar(0x200B)?.isJSSpace == false)
    #expect(jsTrim("\u{FEFF}\t x \u{A0}\n") == "x")
    #expect(jsTrim("\u{85}x") == "\u{85}x")
  }
}

@Suite("compareBase")
struct CompareBaseTests {
  @Test func ignoresCaseAndAccents() {
    #expect(compareBase("Eclair", "éclair") == 0)
    #expect(compareBase("flour", "Flour") == 0)
  }

  @Test func ordersSpacesPunctuationDigitsThenLetters() {
    let sorted = ["a b", "a-b", "a1", "ab", "b"].sorted { compareBase($0, $1) < 0 }
    #expect(sorted == ["a b", "a-b", "a1", "ab", "b"])
  }

  @Test func readsLigaturesAndEszettAsTheirLetters() {
    #expect(compareBase("ß", "ss") == 0)
    #expect(compareBase("æ", "ae") == 0)
    #expect(compareBase("œ", "oe") == 0)
  }
}
