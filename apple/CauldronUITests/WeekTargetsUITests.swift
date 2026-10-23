import XCTest

final class WeekTargetsUITests: XCTestCase {
  @MainActor
  func testTargetsRoundtrip() throws {
    let app = XCUIApplication()
    app.launchEnvironment["CAULDRON_UI_TEST_IN_MEMORY"] = "1"
    app.launchEnvironment["CAULDRON_UI_TEST_APPEARANCE"] = "light"
    app.launch()
    navigateToWeek(in: app)

    let setTargets = app.buttons["week.setTargets"]
    XCTAssertTrue(setTargets.waitForExistence(timeout: 10))
    attachScreenshot(of: app, named: "week-no-targets-narrow-light")
    capturePlannerMeals(in: app, appearance: "light", targets: false)
    activate(setTargets)
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
    activate(setTargets)
    completeTargetSetup(in: app, appearance: "dark")
  }

  @MainActor
  private func completeTargetSetup(in app: XCUIApplication, appearance: String) {
    #if os(macOS)
      let female = app.radioButtons["Female"]
    #else
      let female = app.buttons["Female"]
    #endif
    XCTAssertTrue(female.waitForExistence(timeout: 5), app.debugDescription)
    activate(female)
    let birthDate = app.descendants(matching: .any)["targets.birthDate"]
    XCTAssertTrue(birthDate.waitForExistence(timeout: 5))
    #if os(macOS)
      activate(birthDate)
      let focusedDatePicker = app.datePickers.element(boundBy: 1)
      XCTAssertTrue(focusedDatePicker.waitForExistence(timeout: 5), app.debugDescription)
      focusedDatePicker.typeText("01/15/2000\n")
      XCTAssertFalse(app.dialogs.firstMatch.exists, "Date picker should close after selection")
    #else
      activate(birthDate)
      let calendar = app.datePickers.firstMatch
      XCTAssertTrue(calendar.waitForExistence(timeout: 5), app.debugDescription)
      let dateChoice = calendar.buttons.matching(
        NSPredicate(format: "label MATCHES %@", ".*\\b15\\b.*")
      ).firstMatch
      XCTAssertTrue(dateChoice.waitForExistence(timeout: 5), app.debugDescription)
      activate(dateChoice)
      activate(birthDate)
    #endif
    attachScreenshot(of: app, named: "targets-about-narrow-\(appearance)")

    replaceText(app.textFields["targets.field.Height"], with: "175")
    XCTAssertEqual(app.textFields["targets.field.Height"].value as? String, "175")
    scrollSetup(in: app)
    replaceText(app.textFields["targets.field.Current weight"], with: "70")
    XCTAssertEqual(app.textFields["targets.field.Current weight"].value as? String, "70")
    dismissKeyboardAndScroll(in: app)
    XCTAssertTrue(app.buttons["targets.continue"].isHittable, app.debugDescription)
    activate(app.buttons["targets.continue"])
    XCTAssertTrue(app.staticTexts["Step 2 of 3"].waitForExistence(timeout: 5), app.debugDescription)
    scrollSetup(in: app)
    activate(app.buttons["targets.continue"])
    XCTAssertTrue(app.staticTexts["Step 3 of 3"].waitForExistence(timeout: 5), app.debugDescription)
    scrollSetup(in: app)
    let save = app.buttons["targets.save"]
    XCTAssertTrue(save.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(save.isEnabled, app.debugDescription)
    #if os(macOS)
      let sheetScrollView = app.sheets.firstMatch.scrollViews.firstMatch
      XCTAssertTrue(sheetScrollView.exists, app.debugDescription)
      XCTAssertTrue(save.isHittable, app.debugDescription)
      XCTAssertGreaterThanOrEqual(save.frame.minY, sheetScrollView.frame.minY)
      XCTAssertLessThanOrEqual(save.frame.maxY, sheetScrollView.frame.maxY)
    #endif
    attachScreenshot(of: app, named: "targets-narrow-\(appearance)")
    activate(save)
    let comparison = app.descendants(matching: .any)["week.weeklyComparison"]
    XCTAssertTrue(comparison.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertFalse(app.buttons["targets.save"].exists, "Targets sheet should dismiss after saving")
    XCTAssertTrue(comparison.isHittable, app.debugDescription)
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
    #if os(macOS)
      let window = app.windows.firstMatch
      let screenshot = window.screenshot()
    #else
      let screenshot = app.screenshot()
    #endif
    let attachment = XCTAttachment(screenshot: screenshot)
    if name.hasPrefix("week-") {
      #if os(macOS)
        let frame = app.windows.firstMatch.frame
      #else
        let frame = app.frame
      #endif
      let width = Int(frame.width.rounded())
      let height = Int(frame.height.rounded())
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
    #if os(macOS)
      let week = app.staticTexts["calendar"]
      XCTAssertTrue(week.waitForExistence(timeout: 10), app.debugDescription)
      activate(week)
    #else
      let week = app.buttons["calendar"]
      XCTAssertTrue(week.waitForExistence(timeout: 10), app.debugDescription)
      activate(week)
    #endif
  }

  @MainActor
  private func scrollSetup(in app: XCUIApplication) {
    #if os(iOS)
      app.collectionViews.firstMatch.swipeUp()
    #else
      let scrollView = app.sheets.firstMatch.scrollViews.firstMatch
      XCTAssertTrue(scrollView.waitForExistence(timeout: 5), app.debugDescription)
      scrollView.swipeUp()
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
    #if os(iOS)
      app.collectionViews.firstMatch.swipeUp()
      attachScreenshot(
        of: app,
        named:
          "week-planner-meals-\(targets ? "targets" : "no-targets")-narrow-\(appearance)")
      app.collectionViews.firstMatch.swipeDown()
    #endif
  }

  @MainActor
  private func replaceText(_ field: XCUIElement, with value: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    activate(field)
    field.typeText(value)
  }

  @MainActor
  private func activate(_ element: XCUIElement) {
    #if os(macOS)
      element.click()
    #else
      element.tap()
    #endif
  }
}
