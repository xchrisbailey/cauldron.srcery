import CauldronKit
import Foundation
import Testing

/// Pins the JSON of export format version 1. A change that fails this test changes the shipped
/// format: add the field in a new version (see docs/native/export-format.md) rather than
/// editing the expectation.
@Suite("Export format")
struct ExportFormatTests {
  private static func id(_ n: Int) -> UUID {
    let last = String(n)
    return UUID(
      uuidString: "00000000-0000-0000-0000-" + String(repeating: "0", count: 12 - last.count) + last
    )!
  }

  private static func day(_ string: String) -> LocalDate { LocalDate(string)! }

  /// 2026-10-11T09:30:00.000Z, plus `ms` milliseconds.
  private static func moment(plus ms: Int = 0) -> Date {
    Date(timeIntervalSince1970: (1_791_711_000_000 + Double(ms)) / 1000)
  }

  /// A document with every kind of record and every optional field filled in.
  static let full = CauldronExport(
    exportedAt: moment(),
    app: ExportedApp(name: "Cauldron", version: "0.0.1"),
    recipes: [
      ExportedRecipe(
        id: id(1), title: "Shakshuka", summary: "Eggs in tomato.", notes: "Use ripe tomatoes.",
        servings: 4, prepMinutes: 10, cookMinutes: 25, totalMinutes: 35,
        source: ExportedSource(
          platform: "web", url: "https://example.com/shakshuka", author: "A. Cook",
          fetchedAt: moment(plus: 500)),
        macros: ExportedMacros(calories: 420, protein: 24.5, carbs: 30, fat: nil),
        macrosSource: "estimated", macrosPending: false,
        ingredients: [
          ExportedIngredient(
            section: "Sauce", quantity: ExportedQuantity(min: 1, max: 2), unit: "can",
            item: "tomatoes", note: "crushed", optional: false,
            alt: ExportedAltMeasure(quantity: ExportedQuantity(min: 28, max: nil), unit: "oz"),
            original: "1-2 cans (28oz) tomatoes, crushed", itemKey: "tomato"),
          ExportedIngredient(
            section: nil, quantity: nil, unit: nil, item: "salt", note: nil, optional: true,
            alt: nil, original: "salt, to taste", itemKey: "salt"),
        ],
        steps: [
          ExportedStep(section: nil, text: "Simmer.", timerSeconds: 480),
          ExportedStep(section: "Finish", text: "Add the eggs.", timerSeconds: nil),
        ],
        tagIds: [id(10)], lastCookedOn: day("2026-10-04"), deletedAt: nil,
        createdAt: moment(plus: 1), updatedAt: moment(plus: 2)),
      ExportedRecipe(
        id: id(2), title: "Banished stew", summary: nil, notes: nil, servings: nil,
        prepMinutes: nil, cookMinutes: nil, totalMinutes: nil,
        source: ExportedSource(platform: "manual", url: nil, author: nil, fetchedAt: nil),
        macros: ExportedMacros(calories: nil, protein: nil, carbs: nil, fat: nil),
        macrosSource: nil, macrosPending: true, ingredients: [], steps: [], tagIds: [],
        lastCookedOn: nil, deletedAt: moment(plus: 3000), createdAt: moment(), updatedAt: moment()),
    ],
    photos: [
      ExportedPhoto(
        id: id(20), recipeId: id(1), file: "photos/00000000-0000-0000-0000-000000000020.jpg",
        width: 1600, height: 1200, createdAt: moment()),
      ExportedPhoto(
        id: id(21), recipeId: nil, file: nil, width: 0, height: 0, createdAt: moment()),
    ],
    tags: [
      ExportedTag(
        id: id(10), name: "Breakfast", kind: "meal", createdAt: moment(), updatedAt: moment())
    ],
    cooks: [
      ExportedCook(id: id(30), recipeId: id(1), cookedOn: day("2026-10-04"), createdAt: moment())
    ],
    planEntries: [
      ExportedPlanEntry(
        id: id(40), day: day("2026-10-12"), slot: "dinner", title: "Shakshuka", servings: 4,
        position: 0, recipeId: id(1), createdAt: moment(), updatedAt: moment()),
      ExportedPlanEntry(
        id: id(41), day: day("2026-10-13"), slot: "lunch", title: "Leftovers", servings: nil,
        position: 1, recipeId: nil, createdAt: moment(), updatedAt: moment()),
    ],
    gatherItems: [
      ExportedGatherItem(
        id: id(50), weekStart: day("2026-10-12"), item: "tomatoes", itemKey: "tomato",
        quantity: ExportedQuantity(min: 1, max: nil), unit: "can", aisle: "pantry", checked: true,
        manual: false, position: 2,
        sources: [
          ExportedGatherSource(
            id: id(51), recipeId: id(1), quantity: ExportedQuantity(min: 1, max: nil), unit: "can")
        ], createdAt: moment(), updatedAt: moment())
    ],
    pantry: [ExportedPantryItem(id: id(60), itemKey: "salt", createdAt: moment())],
    diary: [
      ExportedDiaryEntry(
        id: id(70), day: day("2026-10-11"), slot: "snack", name: "Apple", amount: "1 medium",
        servings: 1.5,
        macros: ExportedMacros(calories: 95, protein: 0.5, carbs: 25, fat: 0.3),
        source: "described", position: 0, macrosPending: false, recipeId: nil,
        createdAt: moment(), updatedAt: moment())
    ],
    favourites: [
      ExportedFavourite(
        id: id(80), key: "apple", name: "Apple", amount: nil, servings: 1,
        macros: ExportedMacros(calories: 95, protein: nil, carbs: nil, fat: nil),
        source: "manual", recipeId: id(1), createdAt: moment(), updatedAt: moment())
    ],
    weighIns: [
      ExportedWeighIn(
        id: id(90), day: day("2026-10-11"), weightKg: 74.2, healthSampleID: "HK-1",
        createdAt: moment(), updatedAt: moment())
    ],
    bodyProfile: ExportedBodyProfile(
      id: id(100), sex: "female", birthDate: day("1990-05-14"), heightCm: 168, activity: "light",
      goal: "lose", weeklyRateKg: 0.5, proteinPerKg: 1.8, fatShare: 0.25, weightUnit: "kg",
      heightUnit: "cm", createdAt: moment(), updatedAt: moment()),
    targets: ExportedTargets(
      id: id(101), calories: 1800, protein: 120, carbs: 180, fat: 50,
      overridden: ExportedTargetOverrides(calories: true, protein: false, carbs: false, fat: false),
      checkedInOn: day("2026-10-03"), createdAt: moment(), updatedAt: moment()),
    preferences: ExportedPreferences(
      id: id(102), weekStartsOn: 1, unitSystem: "metric", createdAt: moment(),
      updatedAt: moment())
  )

  static let empty = CauldronExport(exportedAt: moment(), app: ExportedApp(name: "Cauldron"))

  // swift-format-ignore
  static let fullJSON = """
    {
      "formatVersion": 1,
      "exportedAt": "2026-10-11T09:30:00.000Z",
      "app": { "name": "Cauldron", "version": "0.0.1" },
      "recipes": [
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "title": "Shakshuka",
          "summary": "Eggs in tomato.",
          "notes": "Use ripe tomatoes.",
          "servings": 4,
          "prepMinutes": 10,
          "cookMinutes": 25,
          "totalMinutes": 35,
          "source": {
            "platform": "web",
            "url": "https://example.com/shakshuka",
            "author": "A. Cook",
            "fetchedAt": "2026-10-11T09:30:00.500Z"
          },
          "macros": { "calories": 420, "protein": 24.5, "carbs": 30 },
          "macrosSource": "estimated",
          "macrosPending": false,
          "ingredients": [
            {
              "section": "Sauce",
              "quantity": { "min": 1, "max": 2 },
              "unit": "can",
              "item": "tomatoes",
              "note": "crushed",
              "optional": false,
              "alt": { "quantity": { "min": 28 }, "unit": "oz" },
              "original": "1-2 cans (28oz) tomatoes, crushed",
              "itemKey": "tomato"
            },
            {
              "item": "salt",
              "optional": true,
              "original": "salt, to taste",
              "itemKey": "salt"
            }
          ],
          "steps": [
            { "text": "Simmer.", "timerSeconds": 480 },
            { "section": "Finish", "text": "Add the eggs." }
          ],
          "tagIds": ["00000000-0000-0000-0000-000000000010"],
          "lastCookedOn": "2026-10-04",
          "createdAt": "2026-10-11T09:30:00.001Z",
          "updatedAt": "2026-10-11T09:30:00.002Z"
        },
        {
          "id": "00000000-0000-0000-0000-000000000002",
          "title": "Banished stew",
          "source": { "platform": "manual" },
          "macros": {},
          "macrosPending": true,
          "ingredients": [],
          "steps": [],
          "tagIds": [],
          "deletedAt": "2026-10-11T09:30:03.000Z",
          "createdAt": "2026-10-11T09:30:00.000Z",
          "updatedAt": "2026-10-11T09:30:00.000Z"
        }
      ],
      "photos": [
        {
          "id": "00000000-0000-0000-0000-000000000020",
          "recipeId": "00000000-0000-0000-0000-000000000001",
          "file": "photos/00000000-0000-0000-0000-000000000020.jpg",
          "width": 1600,
          "height": 1200,
          "createdAt": "2026-10-11T09:30:00.000Z"
        },
        {
          "id": "00000000-0000-0000-0000-000000000021",
          "width": 0,
          "height": 0,
          "createdAt": "2026-10-11T09:30:00.000Z"
        }
      ],
      "tags": [
        {
          "id": "00000000-0000-0000-0000-000000000010",
          "name": "Breakfast",
          "kind": "meal",
          "createdAt": "2026-10-11T09:30:00.000Z",
          "updatedAt": "2026-10-11T09:30:00.000Z"
        }
      ],
      "cooks": [
        {
          "id": "00000000-0000-0000-0000-000000000030",
          "recipeId": "00000000-0000-0000-0000-000000000001",
          "cookedOn": "2026-10-04",
          "createdAt": "2026-10-11T09:30:00.000Z"
        }
      ],
      "planEntries": [
        {
          "id": "00000000-0000-0000-0000-000000000040",
          "day": "2026-10-12",
          "slot": "dinner",
          "title": "Shakshuka",
          "servings": 4,
          "position": 0,
          "recipeId": "00000000-0000-0000-0000-000000000001",
          "createdAt": "2026-10-11T09:30:00.000Z",
          "updatedAt": "2026-10-11T09:30:00.000Z"
        },
        {
          "id": "00000000-0000-0000-0000-000000000041",
          "day": "2026-10-13",
          "slot": "lunch",
          "title": "Leftovers",
          "position": 1,
          "createdAt": "2026-10-11T09:30:00.000Z",
          "updatedAt": "2026-10-11T09:30:00.000Z"
        }
      ],
      "gatherItems": [
        {
          "id": "00000000-0000-0000-0000-000000000050",
          "weekStart": "2026-10-12",
          "item": "tomatoes",
          "itemKey": "tomato",
          "quantity": { "min": 1 },
          "unit": "can",
          "aisle": "pantry",
          "checked": true,
          "manual": false,
          "position": 2,
          "sources": [
            {
              "id": "00000000-0000-0000-0000-000000000051",
              "recipeId": "00000000-0000-0000-0000-000000000001",
              "quantity": { "min": 1 },
              "unit": "can"
            }
          ],
          "createdAt": "2026-10-11T09:30:00.000Z",
          "updatedAt": "2026-10-11T09:30:00.000Z"
        }
      ],
      "pantry": [
        {
          "id": "00000000-0000-0000-0000-000000000060",
          "itemKey": "salt",
          "createdAt": "2026-10-11T09:30:00.000Z"
        }
      ],
      "diary": [
        {
          "id": "00000000-0000-0000-0000-000000000070",
          "day": "2026-10-11",
          "slot": "snack",
          "name": "Apple",
          "amount": "1 medium",
          "servings": 1.5,
          "macros": { "calories": 95, "protein": 0.5, "carbs": 25, "fat": 0.3 },
          "source": "described",
          "position": 0,
          "macrosPending": false,
          "createdAt": "2026-10-11T09:30:00.000Z",
          "updatedAt": "2026-10-11T09:30:00.000Z"
        }
      ],
      "favourites": [
        {
          "id": "00000000-0000-0000-0000-000000000080",
          "key": "apple",
          "name": "Apple",
          "servings": 1,
          "macros": { "calories": 95 },
          "source": "manual",
          "recipeId": "00000000-0000-0000-0000-000000000001",
          "createdAt": "2026-10-11T09:30:00.000Z",
          "updatedAt": "2026-10-11T09:30:00.000Z"
        }
      ],
      "weighIns": [
        {
          "id": "00000000-0000-0000-0000-000000000090",
          "day": "2026-10-11",
          "weightKg": 74.2,
          "healthSampleID": "HK-1",
          "createdAt": "2026-10-11T09:30:00.000Z",
          "updatedAt": "2026-10-11T09:30:00.000Z"
        }
      ],
      "bodyProfile": {
        "id": "00000000-0000-0000-0000-000000000100",
        "sex": "female",
        "birthDate": "1990-05-14",
        "heightCm": 168,
        "activity": "light",
        "goal": "lose",
        "weeklyRateKg": 0.5,
        "proteinPerKg": 1.8,
        "fatShare": 0.25,
        "weightUnit": "kg",
        "heightUnit": "cm",
        "createdAt": "2026-10-11T09:30:00.000Z",
        "updatedAt": "2026-10-11T09:30:00.000Z"
      },
      "targets": {
        "id": "00000000-0000-0000-0000-000000000101",
        "calories": 1800,
        "protein": 120,
        "carbs": 180,
        "fat": 50,
        "overridden": { "calories": true, "protein": false, "carbs": false, "fat": false },
        "checkedInOn": "2026-10-03",
        "createdAt": "2026-10-11T09:30:00.000Z",
        "updatedAt": "2026-10-11T09:30:00.000Z"
      },
      "preferences": {
        "id": "00000000-0000-0000-0000-000000000102",
        "weekStartsOn": 1,
        "unitSystem": "metric",
        "createdAt": "2026-10-11T09:30:00.000Z",
        "updatedAt": "2026-10-11T09:30:00.000Z"
      }
    }
    """

  // swift-format-ignore
  static let emptyJSON = """
    {
      "formatVersion": 1,
      "exportedAt": "2026-10-11T09:30:00.000Z",
      "app": { "name": "Cauldron" },
      "recipes": [],
      "photos": [],
      "tags": [],
      "cooks": [],
      "planEntries": [],
      "gatherItems": [],
      "pantry": [],
      "diary": [],
      "favourites": [],
      "weighIns": []
    }
    """

  /// The JSON as a tree, so the comparison ignores key order and whitespace but nothing else.
  private func tree(_ data: Data) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
  }

  @Test func versionOneHasThisExactShape() throws {
    let encoded = try Self.full.encoded()
    #expect(try tree(encoded) == tree(Data(Self.fullJSON.utf8)))
  }

  @Test func anEmptyExportKeepsEveryListAndLeavesTheSingleRowsOut() throws {
    let encoded = try Self.empty.encoded()
    #expect(try tree(encoded) == tree(Data(Self.emptyJSON.utf8)))
  }

  @Test func theFixtureDecodesBackToTheSameValues() throws {
    #expect(try CauldronExport.decode(Data(Self.fullJSON.utf8)) == Self.full)
    #expect(try CauldronExport.decode(Data(Self.emptyJSON.utf8)) == Self.empty)
  }

  @Test func encodedOutputRoundTrips() throws {
    #expect(try CauldronExport.decode(Self.full.encoded()) == Self.full)
  }

  @Test func encodingIsStableFromRunToRun() throws {
    #expect(try Self.full.encoded() == Self.full.encoded())
  }

  @Test func timestampsKeepTheirMilliseconds() throws {
    let date = Date(timeIntervalSince1970: 1_791_711_006.789)
    #expect(ExportCoding.milliseconds(date) == Date(timeIntervalSince1970: 1_791_711_006.789))
    var document = Self.empty
    document.pantry = [ExportedPantryItem(id: Self.id(1), itemKey: "salt", createdAt: date)]
    let text = try String(decoding: document.encoded(), as: UTF8.self)
    #expect(text.contains(#""createdAt" : "2026-10-11T09:30:06.789Z""#))
    // Anything finer is rounded, so a value read back equals the value written.
    let fine = Date(timeIntervalSince1970: 1_791_711_006.789_4)
    #expect(ExportCoding.milliseconds(fine) == date)
  }

  @Test func daysAreWrittenAsPlainDates() throws {
    #expect(Self.fullJSON.contains(#""lastCookedOn": "2026-10-04""#))
  }

  @Test func refusesAFileFromANewerFormat() throws {
    let newer = Data(#"{ "formatVersion": 2, "somethingNew": [] }"#.utf8)
    #expect(throws: ExportFormatError.newerFormat(found: 2, supported: 1)) {
      try CauldronExport.decode(newer)
    }
  }

  @Test func refusesAFileThatIsNotAnExport() throws {
    #expect(throws: ExportFormatError.unreadable) {
      try CauldronExport.decode(Data(#"{ "recipes": [] }"#.utf8))
    }
    #expect(throws: ExportFormatError.unreadable) {
      try CauldronExport.decode(Data("not json".utf8))
    }
  }

  @Test func ignoresFieldsAFutureVersionAdds() throws {
    var object = try #require(
      try JSONSerialization.jsonObject(with: Data(Self.fullJSON.utf8)) as? [String: Any])
    object["somethingNew"] = ["a": 1]
    let data = try JSONSerialization.data(withJSONObject: object)
    #expect(try CauldronExport.decode(data) == Self.full)
  }
}
