import CauldronKit
import Testing

/// Ported case for case from `packages/shared/test/timers.test.ts`.
struct DetectCase: Sendable {
  let text: String
  let seconds: Int?

  init(_ text: String, _ seconds: Int?) {
    self.text = text
    self.seconds = seconds
  }
}

@Suite("detectTimer")
struct DetectTimerTests {
  static let cases: [DetectCase] = [
    .init("Bake 25 minutes", 1500),
    .init("simmer for 1 hour", 3600),
    .init("Cook 1 1/2 hours", 5400),
    .init("Cook 1½ hours", 5400),
    .init("Cook 1.5 hrs", 5400),
    .init("Roast 1 hr 15 min", 4500),
    .init("Roast 1 hour and 15 minutes", 4500),
    .init("Bake 10-12 minutes", 720),
    .init("Bake 10 to 12 minutes", 720),
    .init("Bake 10–12 mins", 720),
    .init("Sear 30 seconds", 30),
    .init("Sear 30 secs", 30),
    .init("Sear 30s", 30),
    .init("Boil 45 min.", 2700),
    .init("Wait an hour", 3600),
    .init("Wait half an hour", 1800),
    .init("Wait a minute", 60),
    .init("Bake 1 minute 30 seconds", 90),
    .init("Bake 25 MINUTES", 1500),
    .init("Mix, then bake 20 minutes until golden", 1200),
    .init("Stir 2 minutes, then rest 10 minutes", 120),
    .init("Simmer 72 hours", 259_200),
    .init("Simmer 73 hours", nil),
    .init("Preheat oven to 200C", nil),
    .init("Add 2 cups flour", nil),
    .init("serves 4", nil),
    .init("Rest overnight", nil),
    .init("Line a 9-inch pan", nil),
    .init("Add 5 tbsp butter", nil),
    .init("Use a shallow dish", nil),
    .init("", nil),
  ]

  @Test("finds the first duration", arguments: cases)
  func detects(_ c: DetectCase) {
    #expect(detectTimer(c.text) == c.seconds)
  }
}

struct FormatCase: Sendable {
  let seconds: Int
  let label: String

  init(_ seconds: Int, _ label: String) {
    self.seconds = seconds
    self.label = label
  }
}

@Suite("formatTimer")
struct FormatTimerTests {
  static let cases: [FormatCase] = [
    .init(45, "45 s"),
    .init(60, "1 min"),
    .init(90, "1 min 30 s"),
    .init(1500, "25 min"),
    .init(3600, "1 h"),
    .init(4500, "1 h 15 min"),
    .init(7200, "2 h"),
  ]

  @Test("writes a short plain label", arguments: cases)
  func formats(_ c: FormatCase) {
    #expect(formatTimer(c.seconds) == c.label)
  }
}

/// Inputs outside the reference suite, with what the reference returns for them under Bun. They
/// pin down the regex lookbehind and sticky matching the TypeScript uses.
@Suite("detectTimer edge cases")
struct DetectTimerEdgeTests {
  static let cases: [DetectCase] = [
    // Spacing and range punctuation
    .init("Bake 10 -12 minutes", 720),
    .init("Bake 10—12 minutes", 720),
    .init("Bake 10 – 12 min", 720),
    .init("2 to 3 hours", 10800),
    .init("Boil for 5 - 10 minutes", 600),
    .init("Soak 1 1/2-2 hours", 7200),
    .init("Soak 3 – 4 hrs", 14400),
    .init("Bake 1.5-2 hrs", 7200),
    // Amounts
    .init("Cook 1 1/2 h", 5400),
    .init("Soak ½ hour", 1800),
    .init("Soak 1⅔ hours", 6000),
    .init("Soak 1/2 hour", 1800),
    .init("Cook 1 3/4 min", 105),
    .init("Cook 1 ¾ min", 105),
    .init("Cook 10 ½ min", 630),
    .init("Soak 5/0 minutes", nil),
    .init("Cook 1 1 /2 hours", nil),
    .init("Bake 3 / 4 hours", 14400),
    .init("Bake 3/ 4 hours", 14400),
    .init("Bake .5 hours", nil),
    .init("Bake 1,5 hours", 18000),
    .init("Bake 99999999999999999999 minutes", nil),
    .init("Wait half a hour", 1800),
    .init("Wait Half An Hour", 1800),
    .init("Wait a half hour", nil),
    .init("An hour", 3600),
    .init("A Minute", 60),
    .init("Wait an minute", 60),
    .init("Wait a hour 1 hour", 3600),
    .init("about ten minutes", nil),
    .init("an hour and a half", 3600),
    .init("a minute and a half", 60),
    // Units
    .init("Bake 5min", 300),
    .init("Dry 10s.", 10),
    .init("It's 3 mins.", 180),
    .init("Chop 1 hrs", 3600),
    .init("Boil 1 second", 1),
    .init("Take 2 s", 2),
    .init("Take 2 sec", 2),
    .init("5 s", 5),
    .init("5 sec.", 5),
    .init("5 sec..", 5),
    .init("Soak 45 Min", 2700),
    .init("Leave 8 H", 28800),
    .init("Leave 8 hours.", 28800),
    .init("Add 10 small onions", nil),
    .init("30 minutesx", nil),
    .init("30 minutes.5", 1800),
    .init("2 d", nil),
    // Single letter units need a number, not a word
    .init("Wait a s", nil),
    .init("Wait an h", nil),
    .init("Wait a h", nil),
    // The first match must not follow a word character, a dot or a slash
    .init("v1.30 min", nil),
    .init("x/10 minutes", nil),
    .init("x_30 min", nil),
    .init("é30 min", 1800),
    // Sums of smaller trailing units
    .init("Roast 1 hr 15 min 30 sec", 4530),
    .init("Bake 5 min 30 sec", 330),
    .init("Wait 1 hour, 15 minutes", 4500),
    .init("Wait 1 hour,15 minutes", 4500),
    .init("Wait 2 hours 30", 7200),
    .init("Wait 1 hour and 15", 3600),
    .init("Soak 24 hours and 5 min", 86700),
    .init("1 h 30 m 15 s", 3600),
    .init("1 h30m", 3600),
    .init("90 s 1 h", 90),
    .init("3 hours 1 hour", 10800),
    .init("1 hour 1 hour", 3600),
    .init("Bake 3 minutes 1 hour", 180),
    .init("5 minutes 5 hours 3", 300),
    .init("1 minute and 30 seconds and 10", 90),
    .init("10 hours 20 minutes 30 seconds 40 s", 37230),
    // Totals at the limit, and the shortest and zero durations
    .init("Cook 71 hours 59 minutes 59 seconds", 259_199),
    .init("Cook 72 hours 1 minute", nil),
    .init("Cook 0 minutes", nil),
    .init("Cook 0.4 seconds", nil),
    .init("Cook 0.5 seconds", 1),
    // Only the first duration counts
    .init("Bake 20-25 min (or 15 min if fan)", 1500),
    .init("Bake 12 mins, covered, then 5 mins", 720),
    // Whitespace the way JavaScript's `\s` sees it
    .init("Rest 25\u{00A0}minutes", 1500),
    .init("Rest 25\u{2009}min", 1500),
    .init("Rest 25\u{000B}min", 1500),
    .init("Rest 25\u{FEFF}min", 1500),
    .init("Rest 25\u{0085}min", nil),
    // Digits that are not ASCII
    .init("Soak ٣ minutes", nil),
    .init("Soak ２０ minutes", nil),
  ]

  @Test("matches the reference", arguments: cases)
  func detects(_ c: DetectCase) {
    #expect(detectTimer(c.text) == c.seconds)
  }
}

@Suite("formatTimer edge cases")
struct FormatTimerEdgeTests {
  static let cases: [FormatCase] = [
    .init(0, "0 s"),
    .init(1, "1 s"),
    .init(59, "59 s"),
    .init(61, "1 min 1 s"),
    .init(3599, "59 min 59 s"),
    .init(3661, "1 h 1 min"),
    .init(86400, "24 h"),
    .init(259_200, "72 h"),
    .init(-5, "0 s"),
  ]

  @Test("matches the reference", arguments: cases)
  func formats(_ c: FormatCase) {
    #expect(formatTimer(c.seconds) == c.label)
  }

  @Test func roundsFractionalSecondsLikeMathRound() {
    #expect(formatTimer(0.5) == "1 s")
    #expect(formatTimer(1.5) == "2 s")
    #expect(formatTimer(2.5) == "3 s")
    #expect(formatTimer(3599.5) == "1 h")
  }
}
