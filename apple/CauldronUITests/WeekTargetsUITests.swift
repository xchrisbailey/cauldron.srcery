import XCTest

final class WeekTargetsUITests: XCTestCase {
  @MainActor
  func testTargetsRoundtrip() throws {
    let app = XCUIApplication()
    app.launchEnvironment["CAULDRON_UI_TEST_IN_MEMORY"] = "1"
    app.launch()
    app.buttons["calendar"].tap()

    let setTargets = app.buttons["week.setTargets"]
    XCTAssertTrue(setTargets.waitForExistence(timeout: 10))
    attachScreenshot(of: app, named: "week-no-targets-narrow-light")
    setTargets.tap()

    let continueButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Continue"))
    XCTAssertTrue(continueButton.firstMatch.waitForExistence(timeout: 5))
    XCTAssertGreaterThan(app.textFields.count, 0)
  }

  @MainActor
  func testWeekAppearanceScreenshots() {
    for appearance in ["light", "dark"] {
      let app = XCUIApplication()
      app.launchEnvironment["CAULDRON_UI_TEST_IN_MEMORY"] = "1"
      app.launchArguments += ["-ui-testing-appearance", appearance]
      app.launch()
      app.buttons["calendar"].tap()
      XCTAssertTrue(app.buttons["week.setTargets"].waitForExistence(timeout: 10))
      attachScreenshot(of: app, named: "week-no-targets-narrow-\(appearance)")
      app.terminate()
    }
  }

  @MainActor
  private func attachScreenshot(of app: XCUIApplication, named name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
