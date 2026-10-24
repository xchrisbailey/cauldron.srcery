#if os(iOS)
  import XCTest

  final class WeekNutritionUITests: XCTestCase {
    @MainActor
    func testFallbackDayNutritionAndDismissalPreserveExplicitSelection() throws {
      let app = launchWeek(fixture: "breakfast")
      let nutrition = app.buttons["week.openDailyNutrition"]
      reveal(nutrition, in: app, direction: .up)

      nutrition.tap()
      let content = dailyNutritionContent(in: app)
      XCTAssertTrue(content.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(content.staticTexts["Selected day planned against daily target"].exists)
      let fallbackCalories = calorieRow(in: content)
      XCTAssertTrue(fallbackCalories.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertFalse(fallbackCalories.label.contains(": 0 "), fallbackCalories.label)
      closeSheet(in: app)

      let dayButtons = app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "week.day.")
      )
      reveal(dayButtons.firstMatch, in: app, direction: .down)
      let dayElements = dayButtons.allElementsBoundByIndex
      let selectedDay = try XCTUnwrap(dayElements.first { $0.isSelected }, app.debugDescription)
      let anotherDay = try XCTUnwrap(
        dayElements.first { $0.identifier != selectedDay.identifier }, app.debugDescription)
      reveal(anotherDay, in: app, direction: .down)
      anotherDay.tap()
      reveal(nutrition, in: app, direction: .up)
      nutrition.tap()

      let selectedContent = dailyNutritionContent(in: app)
      XCTAssertTrue(selectedContent.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(
        calorieRow(in: selectedContent).label.contains("0 kcal planned"), app.debugDescription)
      closeSheet(in: app)
      XCTAssertTrue(anotherDay.isSelected, app.debugDescription)
      XCTAssertTrue(app.descendants(matching: .any)["week.weeklyComparison"].exists)
    }

    @MainActor
    func testDailyNutritionCanOpenTargetSetupAndReturnToItsDailyScope() {
      let app = launchWeek()
      let nutrition = app.buttons["week.openDailyNutrition"]
      reveal(nutrition, in: app, direction: .up)
      nutrition.tap()

      let content = dailyNutritionContent(in: app)
      XCTAssertTrue(content.waitForExistence(timeout: 5), app.debugDescription)
      let setup = content.buttons["week.dailySetTargets"]
      XCTAssertTrue(setup.waitForExistence(timeout: 5), app.debugDescription)
      setup.tap()
      XCTAssertTrue(
        app.descendants(matching: .any)["targets.birthDate"].waitForExistence(timeout: 5))
      closeSheet(in: app)
      let returnedContent = dailyNutritionContent(in: app)
      XCTAssertTrue(returnedContent.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(returnedContent.staticTexts["Set daily targets to compare this plan."].exists)
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
    private func dailyNutritionContent(in app: XCUIApplication) -> XCUIElement {
      app.descendants(matching: .any)["week.dailyNutritionContent"]
    }

    @MainActor
    private func closeSheet(in app: XCUIApplication) {
      let close = app.buttons["Close"]
      XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
      close.tap()
    }

    @MainActor
    private func calorieRow(in content: XCUIElement) -> XCUIElement {
      content.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Calories:"))
        .firstMatch
    }

    @MainActor
    private func reveal(
      _ element: XCUIElement, in app: XCUIApplication, direction: ScrollDirection
    ) {
      let list = app.collectionViews.firstMatch
      for _ in 0..<8 {
        if element.exists && element.isHittable { return }
        if direction == .up {
          list.swipeUp()
        } else {
          list.swipeDown()
        }
      }
      XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private enum ScrollDirection: Equatable {
      case up
      case down
    }
  }
#endif
