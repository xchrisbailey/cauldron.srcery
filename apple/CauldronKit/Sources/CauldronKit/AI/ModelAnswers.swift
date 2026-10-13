import Foundation

// What the model is asked for, and how its answer becomes the app's own types (`ModelRecipe`,
// `ModelMacros`, `ModelMeal` and their `fromModel…` functions in the reference). Every key is
// required and may be null, so the shapes fit a strict structured-output mode.

/// `found`, or why not: no recipe at all, or one that's only in the video.
public enum ExtractOutcome: String, Sendable, Hashable, Codable, CaseIterable {
  case found
  case missing
  case inVideo
}

public struct ModelRecipe: Sendable, Hashable, Decodable {
  public var recipe: ExtractOutcome
  public var title: String?
  public var description: String?
  public var servings: Double?
  public var prepMinutes: Double?
  public var cookMinutes: Double?
  public var totalMinutes: Double?
  public var ingredients: [ExtractedLine]
  public var steps: [ExtractedStep]
  public var tags: [String]
  public var notes: String?
  public var unsure: [DraftField]

  private enum CodingKeys: String, CodingKey {
    case recipe, title, description, servings, prepMinutes, cookMinutes, totalMinutes
    case ingredients, steps, tags, notes, unsure
  }

  // Every key has to be there, though it may be null, as the reference's schema demands. An
  // answer that leaves keys out is some other shape, not a recipe with gaps.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    recipe = try container.decode(ExtractOutcome.self, forKey: .recipe)
    title = try container.decode(String?.self, forKey: .title)
    description = try container.decode(String?.self, forKey: .description)
    servings = try container.decode(Double?.self, forKey: .servings)
    prepMinutes = try container.decode(Double?.self, forKey: .prepMinutes)
    cookMinutes = try container.decode(Double?.self, forKey: .cookMinutes)
    totalMinutes = try container.decode(Double?.self, forKey: .totalMinutes)
    ingredients = try container.decode([ExtractedLine].self, forKey: .ingredients)
    steps = try container.decode([ExtractedStep].self, forKey: .steps)
    tags = try container.decode([String].self, forKey: .tags)
    notes = try container.decode(String?.self, forKey: .notes)
    unsure = try container.decode([DraftField].self, forKey: .unsure)
  }

  /// A whole number of minutes or servings: nothing negative, and halves round up.
  private static func whole(_ value: Double?) -> Int? {
    // Past 2^53 a double isn't a whole number any more, and no recipe gets near it.
    guard let value, value.isFinite, value >= 0, value <= 9_007_199_254_740_992 else { return nil }
    return Int(jsRound(value))
  }

  /// The model's answer in the shape every extractor shares.
  public var extracted: ExtractedRecipe {
    ExtractedRecipe(
      title: title, description: description, servings: Self.whole(servings),
      prepMinutes: Self.whole(prepMinutes), cookMinutes: Self.whole(cookMinutes),
      totalMinutes: Self.whole(totalMinutes), tags: tags, notes: notes, ingredients: ingredients,
      steps: steps, unsure: unsure)
  }
}

public struct ModelMacros: Sendable, Hashable, Decodable {
  /// The servings the model divided by: the given yield, or its own guess.
  public var servings: Double?
  public var calories: Double?
  public var protein: Double?
  public var carbs: Double?
  public var fat: Double?

  public init(
    servings: Double? = nil, calories: Double?, protein: Double?, carbs: Double?, fat: Double?
  ) {
    self.servings = servings
    self.calories = calories
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
  }

  private enum CodingKeys: String, CodingKey {
    case servings, calories, protein, carbs, fat
  }

  // Every key has to be there, though it may be null.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    servings = try container.decode(Double?.self, forKey: .servings)
    calories = try container.decode(Double?.self, forKey: .calories)
    protein = try container.decode(Double?.self, forKey: .protein)
    carbs = try container.decode(Double?.self, forKey: .carbs)
    fat = try container.decode(Double?.self, forKey: .fat)
  }

  private static func within(_ value: Double?, max: Double, step: Double) -> Double? {
    guard let value, value.isFinite, value >= 0, value <= max else { return nil }
    return jsRound(value / step) * step
  }

  /// The estimate, rounded and bounded like a recipe's own macros: whole calories, and grams to
  /// the half.
  public var macros: Macros {
    Macros(
      calories: Self.within(calories, max: Double(RecipeLimits.calories), step: 1),
      protein: Self.within(protein, max: Double(RecipeLimits.grams), step: 0.5),
      carbs: Self.within(carbs, max: Double(RecipeLimits.grams), step: 0.5),
      fat: Self.within(fat, max: Double(RecipeLimits.grams), step: 0.5))
  }
}

public struct ModelMeal: Sendable, Hashable, Decodable {
  public struct Item: Sendable, Hashable, Decodable {
    public var name: String
    public var amount: String?
    /// False when this isn't something eaten or drunk. Its numbers are then ignored.
    public var food: Bool
    public var calories: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?

    private enum CodingKeys: String, CodingKey {
      case name, amount, food, calories, protein, carbs, fat
    }

    // Every key has to be there, though the amount and the numbers may be null.
    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      name = try container.decode(String.self, forKey: .name)
      amount = try container.decode(String?.self, forKey: .amount)
      food = try container.decode(Bool.self, forKey: .food)
      calories = try container.decode(Double?.self, forKey: .calories)
      protein = try container.decode(Double?.self, forKey: .protein)
      carbs = try container.decode(Double?.self, forKey: .carbs)
      fat = try container.decode(Double?.self, forKey: .fat)
    }
  }

  public var items: [Item]

  /// The most foods one description becomes.
  public static let itemsMax = 30
  static let amountMax = 100

  /// The model's foods, rounded and bounded like recipe macros. Something that isn't food
  /// comes back with no numbers.
  public var described: [DescribedItem] {
    items
      .filter { !$0.name.jsTrimmed().isEmpty }
      .prefix(Self.itemsMax)
      .map { item in
        let amount = item.amount?.jsTrimmed().jsPrefix(Self.amountMax)
        return DescribedItem(
          name: item.name.jsTrimmed().jsPrefix(RecipeLimits.title),
          amount: amount.flatMap { $0.isEmpty ? nil : $0 },
          macros: item.food
            ? ModelMacros(
              calories: item.calories, protein: item.protein, carbs: item.carbs, fat: item.fat
            ).macros
            : .none)
      }
  }
}

/// Model usage, for the job's record.
public struct AIUsage: Sendable, Hashable, Codable {
  public var model: String
  public var inputTokens: Int
  public var outputTokens: Int

  public init(model: String, inputTokens: Int, outputTokens: Int) {
    self.model = model
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
  }
}

public struct Extraction: Sendable, Hashable {
  public var outcome: ExtractOutcome
  public var recipe: ExtractedRecipe
  public var usage: AIUsage?
  /// True when the on-device model read it because Gemini couldn't be reached. The cook is
  /// told to check it more carefully.
  public var rough: Bool

  public init(
    outcome: ExtractOutcome, recipe: ExtractedRecipe, usage: AIUsage?, rough: Bool = false
  ) {
    self.outcome = outcome
    self.recipe = recipe
    self.usage = usage
    self.rough = rough
  }
}
