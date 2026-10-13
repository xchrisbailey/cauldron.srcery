import CauldronKit
import Testing

/// Every string and its tone, by dotted path, read off the catalogue by reflection. A
/// section holds only `CopyString`s and nested groups; anything else is reported as a stray.
private struct Walk {
  var strings: [String: CopyString] = [:]
  var strays: [String] = []
}

private func walk(_ value: Any, path: String, into result: inout Walk) {
  for child in Mirror(reflecting: value).children {
    guard let label = child.label else { continue }
    let childPath = path.isEmpty ? label : "\(path).\(label)"
    if let string = child.value as? CopyString {
      result.strings[childPath] = string
    } else if Mirror(reflecting: child.value).displayStyle == .struct {
      walk(child.value, path: childPath, into: &result)
    } else {
      result.strays.append(childPath)
    }
  }
}

private let catalogue: Walk = {
  var result = Walk()
  walk(Copy.catalogue, path: "", into: &result)
  return result
}()

/// Sections that exist only in the native app, so the TypeScript reference has no copy of them.
private let nativeOnlyPrefixes = [
  "settings.", "export.", "recipeEditor.", "brewMode.", "macMenu.", "describeNative.",
]

private func isNativeOnly(_ path: String) -> Bool {
  nativeOnlyPrefixes.contains { path.hasPrefix($0) }
}

@Suite("Copy module")
struct CopyTests {
  @Test func everyEntryIsAMarkedCopyString() {
    #expect(catalogue.strays.isEmpty, "not CopyStrings: \(catalogue.strays)")
    #expect(catalogue.strings.count > 400)
    for (path, string) in catalogue.strings {
      #expect(!string.text.isEmpty, "\(path) is empty")
    }
  }

  @Test func holdsExactlyTheReferenceStringsWithoutArguments() {
    let expected = Set(CopyReference.strings.map(\.path))
    let actual = Set(catalogue.strings.keys.filter { !isNativeOnly($0) })
    #expect(actual.subtracting(expected).sorted() == [], "extra strings")
    #expect(expected.subtracting(actual).sorted() == [], "missing strings")
  }

  @Test("keeps each string's text and its voice or plain marking", arguments: CopyReference.strings)
  func matchesTheReference(_ reference: CopyReferenceString) {
    guard let string = catalogue.strings[reference.path] else {
      Issue.record("\(reference.path) is missing")
      return
    }
    #expect(string.text == reference.text, "\(reference.path)")
    #expect(string.tone == reference.tone, "\(reference.path)")
  }

  @Test("builds each string that takes arguments", arguments: CopyReference.calls)
  func matchesTheReferenceWithArguments(_ reference: CopyReferenceCall) {
    #expect(reference.actual.text == reference.text, "\(reference.call)")
    #expect(reference.actual.tone == reference.tone, "\(reference.call)")
  }

  @Test func settingsIsNativeOnlyAndPlain() {
    let settings = catalogue.strings.filter { isNativeOnly($0.key) }
    #expect(settings.count > 8)
    #expect(settings.values.allSatisfy { $0.tone == .plain })
  }

  @Test func leavesOutTheAuthAndAccountStrings() {
    #expect(catalogue.strings.keys.allSatisfy { !$0.hasPrefix("auth.") })
    for path in [
      "errors.unauthorized", "pageTitles.signIn", "pageTitles.signUp",
      "pageTitles.forgotPassword", "pageTitles.resetPassword", "pageTitles.account",
    ] {
      #expect(catalogue.strings[path] == nil, "\(path) has no native screen")
    }
  }
}

/// Plurals and optional arguments, spelled out as literals rather than derived.
@Suite("Copy with arguments")
struct CopyArgumentTests {
  @Test func pluralsFollowTheCount() {
    #expect(Copy.library.count(1).text == "1 recipe")
    #expect(Copy.library.count(0).text == "0 recipes")
    #expect(Copy.library.count(12).text == "12 recipes")
    #expect(Copy.gather.summary(1, 1).text == "1 ingredient across 1 recipe.")
    #expect(Copy.gather.summary(5, 3).text == "5 ingredients across 3 recipes.")
    #expect(Copy.gather.inPantryCount(1).text == "1 is already in the pantry.")
    #expect(Copy.gather.inPantryCount(4).text == "4 are already in the pantry.")
    #expect(Copy.week.spread.stir(1).text == "Stir into 1 day")
    #expect(Copy.week.spread.stir(3).text == "Stir into 3 days")
    #expect(Copy.week.spread.stirred(1).text == "Stirred into 1 day.")
    #expect(Copy.week.spread.stirred(3).text == "Stirred into 3 days.")
    #expect(Copy.tracker.diary.loggedMany(1).text == "Logged 1 item.")
    #expect(Copy.tracker.diary.loggedMany(3).text == "Logged 3 items.")
    #expect(Copy.tracker.copyDay.copied(1).text == "Copied 1 item.")
    #expect(Copy.tracker.describe.log(3).text == "Log 3 items")
  }

  @Test func unknownCountsReadAsTheRecipesOwn() {
    #expect(Copy.week.sameServings(nil).text == "As the recipe")
    #expect(Copy.week.sameServings(4).text == "As the recipe (4)")
    #expect(Copy.week.spread.planned(3, nil).text == "3 servings planned")
    #expect(Copy.week.spread.planned(1, nil).text == "1 serving planned")
    #expect(Copy.week.spread.planned(3, 6).text == "3 of 6 servings planned")
  }

  @Test func theHeadlineFollowsTheGoal() {
    #expect(
      Copy.tracker.targets.headline(.maintain, "2200", "0", "kg").text
        == "About 2200 kcal a day to stay where you are.")
    #expect(
      Copy.tracker.targets.headline(.lose, "2000", "0.5", "kg").text
        == "About 2000 kcal a day to lose 0.5 kg a week.")
    #expect(
      Copy.tracker.targets.headline(.gain, "2600", "0.25", "lb").text
        == "About 2600 kcal a day to gain 0.25 lb a week.")
  }

  @Test func slotNamesAreLowercasedInsideASentence() {
    #expect(Copy.week.stirInto("Monday", "Dinner").text == "Stir into Monday, dinner")
    #expect(Copy.tracker.diary.addTo("Snack").text == "Add to snack")
    #expect(Copy.tracker.entry.addTitle("Breakfast").text == "Add to breakfast")
  }

  @Test func deleteConfirmationsKeepTheVerbVoiceAndTheLiteralPlain() {
    let banish = Copy.recipes.banishConfirm("Dal")
    #expect(banish.verb == CopyString.voice("Banish"))
    #expect(banish.confirm == CopyString.plain("Banish Dal? You can undo it straight after."))
  }

  @Test func theWeightRangesReadFromTheirPeriods() {
    #expect(Copy.tracker.weight.ranges.oneMonth.text == "1M")
    #expect(Copy.tracker.weight.ranges.threeMonths.text == "3M")
    #expect(Copy.tracker.weight.ranges.oneYear.text == "1Y")
    #expect(Copy.tracker.weight.ranges.all.text == "All")
  }
}

/// The enum-keyed lookups views use instead of switching on a case themselves.
@Suite("Copy lookups by enum")
struct CopyLookupTests {
  @Test func everyMealSlotAndAisleHasALabel() {
    #expect(
      MealSlot.allCases.map { Copy.week.slots[$0].text } == [
        "Breakfast", "Lunch", "Dinner", "Snack",
      ])
    #expect(
      Aisle.allCases.map { Copy.gather.aisles[$0].text }
        == [
          "Produce", "Meat and fish", "Dairy and eggs", "Bakery", "Pantry", "Spices", "Frozen",
          "Drinks", "Other",
        ])
  }

  @Test func theCalculatorChoicesHaveLabels() {
    let targets = Copy.tracker.targets
    #expect(Sex.allCases.map { targets.sexes[$0].text } == ["Female", "Male", "Prefer not to say"])
    #expect(WeightUnit.allCases.map { targets.weightUnits[$0].text } == ["kg", "lb"])
    #expect(HeightUnit.allCases.map { targets.heightUnits[$0].text } == ["cm", "ft/in"])
    #expect(
      Goal.allCases.map { targets.goals[$0].text } == ["Lose weight", "Maintain", "Gain weight"])
    #expect(
      ActivityLevel.allCases.map { targets.activityLevels[$0].label.text } == [
        "Sedentary", "Lightly active", "Moderately active", "Very active", "Extremely active",
      ])
    #expect(targets.activityLevels[.veryActive].hint.text == "Physical job plus hard training.")
  }

  @Test func everyImportFailureHasAPlainMessage() {
    for code in ImportFailureCode.allCases {
      #expect(Copy.imports.failure(code).tone == .plain, "\(code)")
    }
    #expect(
      Copy.imports.failure(.timeout).text
        == "That took too long. Try again, or paste the recipe text instead.")
  }

  @Test func wholeAndFractionalLimitsPrintLikeTheWebApp() {
    #expect(Copy.validation.numberBetween(0, 2000).text == "Use a number from 0 to 2000.")
    #expect(Copy.validation.numberBetween(0.2, 0.4).text == "Use a number from 0.2 to 0.4.")
  }
}

/// The brand rule: magic verbs with plain nouns. Errors, quantities, step controls and the
/// literal part of delete confirmations are always plain.
@Suite("Copy tone rules")
struct CopyToneTests {
  private func tones(under prefix: String) -> [String: Tone] {
    catalogue.strings.filter { $0.key.hasPrefix(prefix) }.mapValues(\.tone)
  }

  @Test func errorsValidationAndQuantitiesAreAlwaysPlain() {
    for prefix in ["errors.", "validation.", "quantities."] {
      let found = tones(under: prefix)
      #expect(!found.isEmpty, "\(prefix) has strings")
      #expect(found.values.allSatisfy { $0 == .plain }, "\(prefix) must be plain")
    }
  }

  @Test func failureMessagesArePlainEverywhere() {
    for (path, string) in catalogue.strings where path.contains(".couldnt") {
      #expect(string.tone == .plain, "\(path)")
    }
    for (path, string) in catalogue.strings where path.hasPrefix("imports.") {
      let failures = [
        "couldntRead", "noRecipe", "noRecipeInText", "spokenOnly", "tooLarge", "blocked", "timeout",
        "unavailable", "dailyLimit", "couldntStart",
      ]
      if failures.contains(where: { path == "imports.\($0)" }) {
        #expect(string.tone == .plain, "\(path)")
      }
    }
  }

  @Test func brewingControlsArePlainAndOnlyBrewedIsVoice() {
    let voiced = tones(under: "brewing.").filter { $0.value == .voice }.keys
    #expect(Array(voiced) == ["brewing.brewed"])
  }

  @Test func theVoiceStringsAreTheMagicVerbs() {
    let voiced = catalogue.strings.filter { $0.value.tone == .voice }.values.map(\.text)
    #expect(voiced.contains("Conjure a recipe"))
    #expect(voiced.contains("Distill"))
    #expect(voiced.contains("Stir in"))
    #expect(voiced.contains("Gather"))
    #expect(voiced.contains("Divine it"))
    #expect(voiced.count > 20)
  }
}
