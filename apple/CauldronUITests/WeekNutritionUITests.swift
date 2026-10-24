import XCTest

final class WeekNutritionUITests: XCTestCase {
  @MainActor
  func testFallbackDayNutritionAndDismissalPreserveExplicitSelection() {
    let app = launchWeek(fixture: "breakfast")
    let nutrition = app.buttons["week.openDailyNutrition"]
    XCTAssertTrue(nutrition.waitForExistence(timeout: 10), app.debugDescription)

    nutrition.tap()
    XCTAssertTrue(app.navigationBars["Daily nutrition"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Selected day planned against daily target"].exists)
    let fallbackCalories = calorieRow(in: app)
    XCTAssertTrue(fallbackCalories.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertFalse(fallbackCalories.label.contains(": 0 "), fallbackCalories.label)
    closeSheet(in: app)

    let anotherDay = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "week.day.")
    ).element(boundBy: 1)
    XCTAssertTrue(anotherDay.waitForExistence(timeout: 5), app.debugDescription)
    anotherDay.tap()
    nutrition.tap()
    XCTAssertTrue(app.navigationBars["Daily nutrition"].waitForExistence(timeout: 5))
    XCTAssertTrue(calorieRow(in: app).label.contains("0 kcal planned"), app.debugDescription)
    closeSheet(in: app)
    XCTAssertTrue(anotherDay.isSelected, app.debugDescription)
    XCTAssertTrue(app.descendants(matching: .any)["week.weeklyComparison"].exists)
  }

  @MainActor
  func testDailyNutritionCanOpenTargetSetupAndReturnToItsDailyScope() {
    let app = launchWeek()
    let nutrition = app.buttons["week.openDailyNutrition"]
    XCTAssertTrue(nutrition.waitForExistence(timeout: 10), app.debugDescription)
    nutrition.tap()
    XCTAssertTrue(app.navigationBars["Daily nutrition"].waitForExistence(timeout: 5))

    let setup = app.buttons["week.setTargets"]
    XCTAssertTrue(setup.waitForExistence(timeout: 5), app.debugDescription)
    setup.tap()
    XCTAssertTrue(app.descendants(matching: .any)["targets.birthDate"].waitForExistence(timeout: 5))
    closeSheet(in: app)
    XCTAssertTrue(
      app.navigationBars["Daily nutrition"].waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(app.staticTexts["Set daily targets to compare this plan."].exists)
  }

  @MainActor
  private func launchWeek(fixture: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["CAULDRON_UI_TEST_IN_MEMORY"] = "1"
    if let fixture { app.launchEnvironment["CAULDRON_UI_TEST_WEEK"] = fixture }
    app.launch()
    let week = app.buttons["calendar"]
    XCTAssertTrue(week.waitForExistence(timeout: 10), app.debugDescription)
    week.tap()
    return app
  }

  @MainActor
  private func closeSheet(in app: XCUIApplication) {
    let close = app.buttons["Close"]
    XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
    close.tap()
  }

  @MainActor
  private func calorieRow(in app: XCUIApplication) -> XCUIElement {
    app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Calories:"))
      .firstMatch
  }
}
