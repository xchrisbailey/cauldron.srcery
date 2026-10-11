#if DEBUG
  import CauldronKit

  // Four weeks of tracker history for development and demos, ported from
  // `packages/db/src/seed-tracker.ts`: weigh-ins drifting down with day-to-day noise, and most
  // days' meals logged. It is deterministic, and it makes the same numbers as the TypeScript.

  struct SeedFood {
    var name: String
    var amount: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    init(
      _ name: String, _ amount: String, _ calories: Double, _ protein: Double, _ carbs: Double,
      _ fat: Double
    ) {
      self.name = name
      self.amount = amount
      self.calories = calories
      self.protein = protein
      self.carbs = carbs
      self.fat = fat
    }
  }

  /// The generator of the TypeScript seed, a linear congruential one. It keeps its state in a
  /// `Double` because the JavaScript did: the product can pass 2^53, and rounding it the same
  /// way is what keeps the two seeds in step.
  struct SeedRandom {
    private var seed: Double

    init(seed: Double) {
      self.seed = seed
    }

    mutating func next() -> Double {
      seed = (seed * 1_103_515_245 + 12_345).truncatingRemainder(dividingBy: 2_147_483_648)
      return seed / 2_147_483_648
    }
  }

  enum SeedTracker {
    static let days = 28
    static let startKg = 74.2

    static let meals: [MealSlot: [[SeedFood]]] = [
      .breakfast: [
        [SeedFood("Overnight oats", "1 jar", 380, 14, 58, 10)],
        [
          SeedFood("Greek yogurt", "200 g", 190, 20, 8, 9),
          SeedFood("Blueberries", "1 handful", 40, 0.5, 10, 0),
        ],
        [
          SeedFood("Eggs", "2 large", 143, 12.5, 1, 9.5),
          SeedFood("Sourdough toast", "1 slice", 100, 4, 19, 1),
        ],
      ],
      .lunch: [
        [SeedFood("Tomato and white bean soup", "1 bowl", 260, 12, 38, 6)],
        [SeedFood("Chicken salad wrap", "1 wrap", 450, 32, 40, 16)],
        [SeedFood("Leftover dal with rice", "1 bowl", 520, 20, 82, 11)],
      ],
      .dinner: [
        [SeedFood("Weeknight chicken thighs", "1 serving", 540, 42, 12, 34)],
        [SeedFood("Shakshuka with feta", "1 serving", 310, 18, 16, 19)],
        [
          SeedFood("Salmon", "1 fillet", 360, 34, 0, 23),
          SeedFood("Roast potatoes", "1 cup", 210, 4, 32, 8),
        ],
      ],
      .snack: [
        [SeedFood("Apple", "1 medium", 95, 0.5, 25, 0.3)],
        [SeedFood("Dark chocolate", "2 squares", 110, 1.5, 9, 8)],
        [SeedFood("Almonds", "1 handful", 160, 6, 6, 14)],
      ],
    ]

    struct Weight {
      var day: LocalDate
      var kg: Double
    }

    struct Meal {
      var day: LocalDate
      var slot: MealSlot
      var food: SeedFood
      var servings: Double
      var position: Int
    }

    /// The history for the `days` before `today`, one pass of the generator, in the order the
    /// TypeScript draws from it.
    static func history(endingOn today: LocalDate) -> (weights: [Weight], meals: [Meal]) {
      var random = SeedRandom(seed: 23)
      let start = today.adding(days: -days)
      var weights: [Weight] = []
      var eaten: [Meal] = []
      for i in 0..<days {
        let day = start.adding(days: i)
        // About 0.45 kg a week down, with a kilo of water noise either way.
        if random.next() < 0.85 {
          let kg = startKg - (0.45 / 7) * Double(i) + (random.next() - 0.5) * 1.2
          weights.append(Weight(day: day, kg: roundToHundredth(kg)))
        }
        // Most days are logged; some are forgotten.
        if random.next() < 0.2 { continue }
        for slot in [MealSlot.breakfast, .lunch, .dinner, .snack] {
          if slot == .snack && random.next() < 0.2 { continue }
          let options = meals[slot] ?? []
          let meal = options[Int((random.next() * Double(options.count)).rounded(.down))]
          for (position, food) in meal.enumerated() {
            // Bigger plates at lunch and dinner, so the days land near maintenance.
            let servings = slot == .lunch || slot == .dinner ? 1.5 : 1
            eaten.append(
              Meal(day: day, slot: slot, food: food, servings: servings, position: position))
          }
        }
      }
      return (weights, eaten)
    }

    /// `Math.round(x * 100) / 100`, where `Math.round` takes halves up.
    private static func roundToHundredth(_ x: Double) -> Double {
      let scaled = x * 100
      let floor = scaled.rounded(.down)
      return (scaled - floor >= 0.5 ? floor + 1 : floor) / 100
    }
  }
#endif
