import XCTest

final class BatchManagementUITests: XCTestCase {
  #if os(iOS)
    @MainActor
    func testDuplicateRowsOpenTheirOwnEditorAndSaveReturnsToUpdatedList() {
      let app = launchWeek()
      let entry = app.buttons["week.batches"]
      XCTAssertTrue(entry.waitForExistence(timeout: 10), app.debugDescription)
      XCTAssertTrue(entry.label.contains("7 batches"))
      XCTAssertTrue(entry.label.contains("2 servings unassigned"))
      entry.tap()

      let completeDuplicate = batchRow(
        in: app, title: "Breakfast bowl", allocation: "1 of 1 servings planned")
      XCTAssertTrue(completeDuplicate.waitForExistence(timeout: 5), app.debugDescription)
      completeDuplicate.tap()
      XCTAssertTrue(app.staticTexts["All servings assigned"].waitForExistence(timeout: 5))
      setPicker("week.batchEditor.total", option: "week.batchEditor.totalOption.2", in: app)
      app.buttons["week.batchEditor.save"].tap()

      let updatedDuplicate = batchRow(
        in: app, title: "Breakfast bowl", allocation: "1 of 2 servings planned")
      XCTAssertTrue(updatedDuplicate.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(updatedDuplicate.label.contains("1 serving unassigned"))
      let partialDuplicate = batchRow(
        in: app, title: "Breakfast bowl", allocation: "1 of 3 servings planned")
      XCTAssertTrue(partialDuplicate.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(partialDuplicate.label.contains("2 servings unassigned"))
      app.buttons["week.batches.done"].tap()
      XCTAssertTrue(app.buttons["week.batches"].label.contains("3 servings unassigned"))
      app.terminate()
    }

    @MainActor
    func testAssignmentCommitSurvivesDraftCancelAndKeepsSelectedDay() {
      let app = launchWeek()
      let selectedDay = selectedDayTab(in: app)
      XCTAssertFalse(selectedDay.isEmpty, app.debugDescription)
      assertWeeklyCalories("3,500", in: app)
      app.buttons["week.batches"].tap()

      let batch = batchRow(
        in: app, title: "Breakfast bowl", allocation: "1 of 3 servings planned")
      XCTAssertTrue(batch.waitForExistence(timeout: 5), app.debugDescription)
      batch.tap()
      let selectedDate = String(selectedDay.dropFirst("week.day.".count))
      setPicker("week.batchEditor.total", option: "week.batchEditor.totalOption.5", in: app)
      setPicker(
        "week.batchEditor.day", option: "week.batchEditor.dayOption.\(selectedDate)", in: app)
      setPicker(
        "week.batchEditor.slot", option: "week.batchEditor.slotOption.breakfast", in: app)
      setPicker(
        "week.batchEditor.servings", option: "week.batchEditor.servingsOption.2", in: app)
      app.buttons["week.batchEditor.assign"].tap()
      app.buttons["week.batchEditor.cancel"].tap()

      let updated = batchRow(
        in: app, title: "Breakfast bowl", allocation: "3 of 5 servings planned")
      XCTAssertTrue(updated.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(updated.label.contains("2 servings unassigned"))
      app.buttons["week.batches.done"].tap()
      XCTAssertEqual(selectedDayTab(in: app), selectedDay)
      XCTAssertTrue(app.buttons["week.batches"].label.contains("2 servings unassigned"))
      assertWeeklyCalories("4,500", in: app)

      let committedMeal = app.buttons.matching(
        NSPredicate(
          format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
          "Breakfast bowl", "2 servings", "1,000 kcal")
      )
      for _ in 0..<8 {
        if committedMeal.count == 1 && committedMeal.firstMatch.isHittable { break }
        app.swipeUp()
      }
      XCTAssertEqual(committedMeal.count, 1, app.debugDescription)
      XCTAssertTrue(committedMeal.firstMatch.isHittable, app.debugDescription)
      app.terminate()
    }

    @MainActor
    func testFinalAssignmentRemovesOnlyAttentionAndConfirmedRemovalRefreshesList() {
      let app = launchWeek()
      app.buttons["week.batches"].tap()
      let batch = batchRow(
        in: app, title: "Breakfast bowl", allocation: "1 of 3 servings planned")
      XCTAssertTrue(batch.waitForExistence(timeout: 5), app.debugDescription)
      batch.tap()
      setPicker(
        "week.batchEditor.servings", option: "week.batchEditor.servingsOption.2", in: app)
      app.buttons["week.batchEditor.assign"].tap()
      app.buttons["week.batchEditor.cancel"].tap()

      let complete = batchRow(
        in: app, title: "Breakfast bowl", allocation: "3 of 3 servings planned")
      XCTAssertTrue(complete.waitForExistence(timeout: 5), app.debugDescription)
      app.buttons["week.batches.done"].tap()
      let entry = app.buttons["week.batches"]
      XCTAssertTrue(entry.exists)
      XCTAssertFalse(entry.label.contains("unassigned"))
      XCTAssertTrue(entry.label.contains("7 batches"))

      entry.tap()
      let removable = batchRow(
        in: app, title: "Planned recipe 7", allocation: "1 of 1 servings planned")
      XCTAssertTrue(removable.waitForExistence(timeout: 5), app.debugDescription)
      removable.tap()
      app.buttons["week.batchEditor.remove"].tap()
      let dialog = app.sheets["Remove this batch and all its planned meals?"]
      XCTAssertTrue(dialog.waitForExistence(timeout: 5), app.debugDescription)
      let confirm = dialog.buttons["week.batchEditor.confirmRemove"].firstMatch
      XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
      confirm.tap()

      XCTAssertTrue(
        batchRow(in: app, title: "Planned recipe 7", allocation: "1 of 1 servings planned")
          .waitForNonExistence(timeout: 5), app.debugDescription)
      app.buttons["week.batches.done"].tap()
      XCTAssertTrue(app.buttons["week.batches"].label.contains("6 batches"))
      app.terminate()
    }

    @MainActor
    private func launchWeek() -> XCUIApplication {
      let app = XCUIApplication()
      app.launchEnvironment["CAULDRON_UI_TEST_IN_MEMORY"] = "1"
      app.launchEnvironment["CAULDRON_UI_TEST_WEEK"] = "breakfast"
      app.launch()
      let week = app.buttons["calendar"]
      XCTAssertTrue(week.waitForExistence(timeout: 10), app.debugDescription)
      week.tap()
      return app
    }

    @MainActor
    private func batchRow(in app: XCUIApplication, title: String, allocation: String)
      -> XCUIElement
    {
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", title, allocation)
      ).firstMatch
    }

    @MainActor
    private func setPicker(_ identifier: String, option: String, in app: XCUIApplication) {
      let picker = app.descendants(matching: .any)[identifier]
      XCTAssertTrue(picker.waitForExistence(timeout: 5), app.debugDescription)
      picker.tap()
      let choice = app.descendants(matching: .any)[option]
      XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
      choice.tap()
    }

    @MainActor
    private func assertWeeklyCalories(
      _ amount: String, in app: XCUIApplication, file: StaticString = #filePath,
      line: UInt = #line
    ) {
      let modernMetric = app.descendants(matching: .any)["week.weeklyMetric.calories"]
      let legacyWeeklyTally = app.descendants(matching: .any)["week.tally.week"]
      let metric = modernMetric.exists ? modernMetric : legacyWeeklyTally
      XCTAssertTrue(
        metric.waitForExistence(timeout: 5),
        "The weekly calories metric must be present.", file: file, line: line)
      XCTAssertTrue(
        metric.label.contains(amount), metric.label, file: file, line: line)
      XCTAssertTrue(
        metric.label.localizedCaseInsensitiveContains("kcal"), metric.label, file: file,
        line: line)
    }

    @MainActor
    private func selectedDayTab(in app: XCUIApplication) -> String {
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "week.day."))
        .allElementsBoundByIndex.first(where: \.isSelected)?.identifier ?? ""
    }
  #endif
}
