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
    completeTargetSetup(in: app, appearance: "light")
  }

  @MainActor
  func testTargetComparisonInDarkAppearance() {
    let app = XCUIApplication()
    app.launchEnvironment["CAULDRON_UI_TEST_IN_MEMORY"] = "1"
    app.launchEnvironment["CAULDRON_UI_TEST_APPEARANCE"] = "dark"
    app.launch()
    app.buttons["calendar"].tap()
    let setTargets = app.buttons["week.setTargets"]
    XCTAssertTrue(setTargets.waitForExistence(timeout: 10))
    setTargets.tap()
    completeTargetSetup(in: app, appearance: "dark")
  }

  @MainActor
  private func completeTargetSetup(in app: XCUIApplication, appearance: String) {
    XCTAssertTrue(app.buttons["Female"].waitForExistence(timeout: 5))
    app.buttons["Female"].tap()
    let birthDate = app.descendants(matching: .any)["targets.birthDate"]
    XCTAssertTrue(birthDate.waitForExistence(timeout: 5))
    birthDate.tap()
    let calendar = app.datePickers.firstMatch
    XCTAssertTrue(calendar.waitForExistence(timeout: 5), app.debugDescription)
    let dateChoice = calendar.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Wednesday, October 16")
    )
    .firstMatch
    XCTAssertTrue(dateChoice.waitForExistence(timeout: 5), app.debugDescription)
    dateChoice.tap()
    birthDate.tap()
    attachScreenshot(of: app, named: "targets-about-narrow-\(appearance)")

    replaceText(app.textFields["targets.field.Height"], with: "175")
    XCTAssertEqual(app.textFields["targets.field.Height"].value as? String, "175")
    app.swipeUp()
    replaceText(app.textFields["targets.field.Current weight"], with: "70")
    XCTAssertEqual(app.textFields["targets.field.Current weight"].value as? String, "70")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    app.collectionViews.firstMatch.swipeUp()
    XCTAssertTrue(app.buttons["targets.continue"].isHittable, app.debugDescription)
    app.buttons["targets.continue"].tap()
    XCTAssertTrue(app.staticTexts["Step 2 of 3"].waitForExistence(timeout: 5), app.debugDescription)
    app.swipeUp()
    app.buttons["targets.continue"].tap()
    XCTAssertTrue(app.staticTexts["Step 3 of 3"].waitForExistence(timeout: 5), app.debugDescription)
    app.collectionViews.firstMatch.swipeUp()
    XCTAssertTrue(app.buttons["targets.save"].waitForExistence(timeout: 5), app.debugDescription)
    attachScreenshot(of: app, named: "targets-narrow-\(appearance)")
    app.buttons["targets.save"].tap()
    let comparison = app.descendants(matching: .any)["week.weeklyComparison"]
    XCTAssertTrue(comparison.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertFalse(app.buttons["targets.save"].exists, "Targets sheet should dismiss after saving")
    XCTAssertTrue(comparison.label.contains("kcal target"), comparison.label)
    XCTAssertTrue(comparison.label.contains("g target"), comparison.label)
    attachScreenshot(of: app, named: "week-targets-narrow-\(appearance)")
  }

  @MainActor
  func testWeekAppearanceScreenshots() {
    for appearance in ["light", "dark"] {
      let app = XCUIApplication()
      app.launchEnvironment["CAULDRON_UI_TEST_IN_MEMORY"] = "1"
      app.launchEnvironment["CAULDRON_UI_TEST_APPEARANCE"] = appearance
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

  @MainActor
  private func replaceText(_ field: XCUIElement, with value: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    field.typeText(value)
  }
}
