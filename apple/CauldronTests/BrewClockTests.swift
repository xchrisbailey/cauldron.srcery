import Testing

@testable import Cauldron

@Suite("Brew clock")
struct BrewClockTests {
  @Test func aTimeReadsAsMinutesAndSeconds() {
    #expect(BrewClock.text(0) == "0:00")
    #expect(BrewClock.text(5) == "0:05")
    #expect(BrewClock.text(422) == "7:02")
    #expect(BrewClock.text(3599) == "59:59")
  }

  @Test func anHourOrMoreAddsHours() {
    #expect(BrewClock.text(3600) == "1:00:00")
    #expect(BrewClock.text(3905) == "1:05:05")
  }

  @Test func aNegativeTimeIsZero() {
    #expect(BrewClock.text(-3) == "0:00")
  }
}
