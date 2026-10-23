import XCTest

final class WeekTargetsUITests: XCTestCase {
  @MainActor
  func testTargetsRoundtrip() throws {
    let app = XCUIApplication()
    app.launchEnvironment["CAULDRON_UI_TEST_IN_MEMORY"] = "1"
    app.launch()
    navigateToWeek(in: app)

    let setTargets = app.buttons["week.setTargets"]
    XCTAssertTrue(setTargets.waitForExistence(timeout: 10))
    attachScreenshot(of: app, named: "week-no-targets-narrow-light")
    capturePlannerMeals(in: app, appearance: "light", targets: false)
    setTargets.tap()
    completeTargetSetup(in: app, appearance: "light")
  }

  @MainActor
  func testTargetComparisonInDarkAppearance() {
    let app = XCUIApplication()
    app.launchEnvironment["CAULDRON_UI_TEST_IN_MEMORY"] = "1"
    app.launchEnvironment["CAULDRON_UI_TEST_APPEARANCE"] = "dark"
    app.launch()
    navigateToWeek(in: app)
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
      NSPredicate(format: "label MATCHES %@", ".*\\b15\\b.*")
    ).firstMatch
    XCTAssertTrue(dateChoice.waitForExistence(timeout: 5), app.debugDescription)
    dateChoice.tap()
    birthDate.tap()
    attachScreenshot(of: app, named: "targets-about-narrow-\(appearance)")

    replaceText(app.textFields["targets.field.Height"], with: "175")
    XCTAssertEqual(app.textFields["targets.field.Height"].value as? String, "175")
    scrollSetup(in: app)
    replaceText(app.textFields["targets.field.Current weight"], with: "70")
    XCTAssertEqual(app.textFields["targets.field.Current weight"].value as? String, "70")
    dismissKeyboardAndScroll(in: app)
    XCTAssertTrue(app.buttons["targets.continue"].isHittable, app.debugDescription)
    app.buttons["targets.continue"].tap()
    XCTAssertTrue(app.staticTexts["Step 2 of 3"].waitForExistence(timeout: 5), app.debugDescription)
    scrollSetup(in: app)
    app.buttons["targets.continue"].tap()
    XCTAssertTrue(app.staticTexts["Step 3 of 3"].waitForExistence(timeout: 5), app.debugDescription)
    scrollSetup(in: app)
    XCTAssertTrue(app.buttons["targets.save"].waitForExistence(timeout: 5), app.debugDescription)
    attachScreenshot(of: app, named: "targets-narrow-\(appearance)")
    app.buttons["targets.save"].tap()
    let comparison = app.descendants(matching: .any)["week.weeklyComparison"]
    XCTAssertTrue(comparison.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertFalse(app.buttons["targets.save"].exists, "Targets sheet should dismiss after saving")
    XCTAssertTrue(comparison.label.contains("kcal target"), comparison.label)
    XCTAssertTrue(comparison.label.contains("g target"), comparison.label)
    attachScreenshot(of: app, named: "week-targets-narrow-\(appearance)")
    capturePlannerMeals(in: app, appearance: appearance, targets: true)
  }

  @MainActor
  func testWeekAppearanceScreenshots() {
    for appearance in ["light", "dark"] {
      let app = XCUIApplication()
      app.launchEnvironment["CAULDRON_UI_TEST_IN_MEMORY"] = "1"
      app.launchEnvironment["CAULDRON_UI_TEST_APPEARANCE"] = appearance
      app.launch()
      navigateToWeek(in: app)
      XCTAssertTrue(app.buttons["week.setTargets"].waitForExistence(timeout: 10))
      attachScreenshot(of: app, named: "week-no-targets-narrow-\(appearance)")
      capturePlannerMeals(in: app, appearance: appearance, targets: false)
      app.terminate()
    }
  }

  @MainActor
  private func attachScreenshot(of app: XCUIApplication, named name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    if name.hasPrefix("week-") {
      let width = Int(app.frame.width.rounded())
      let height = Int(app.frame.height.rounded())
      let measuredName =
        name.hasPrefix("week-planner-meals-")
        ? name.replacingOccurrences(
          of: "week-planner-meals-",
          with: "week-planner-\(width)ptx\(height)pt-meals-")
        : name.replacingOccurrences(
          of: "week-", with: "week-planner-\(width)ptx\(height)pt-")
      attachment.name = measuredName.replacingOccurrences(of: "-narrow", with: "")
    } else {
      attachment.name = name
    }
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func navigateToWeek(in app: XCUIApplication) {
    let week = app.descendants(matching: .any)["calendar"]
    XCTAssertTrue(week.waitForExistence(timeout: 10), app.debugDescription)
    week.tap()
  }

  @MainActor
  private func scrollSetup(in app: XCUIApplication) {
    #if os(iOS)
      app.collectionViews.firstMatch.swipeUp()
    #else
      app.scrollViews.firstMatch.swipeUp()
    #endif
  }

  @MainActor
  private func dismissKeyboardAndScroll(in app: XCUIApplication) {
    #if os(iOS)
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    #endif
    scrollSetup(in: app)
  }

  @MainActor
  private func capturePlannerMeals(in app: XCUIApplication, appearance: String, targets: Bool) {
    app.swipeUp()
    attachScreenshot(
      of: app,
      named:
        "week-planner-meals-\(targets ? "targets" : "no-targets")-narrow-\(appearance)")
    app.swipeDown()
  }

  @MainActor
  private func replaceText(_ field: XCUIElement, with value: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    field.typeText(value)
  }
}
