extension Copy {
  /// The tracker. Logging and divining are voice; numbers, units, meals, controls and errors
  /// are plain.
  public struct Tracker: Sendable {
    public let title = plain("Tracker")
    public let dayFull = plain("That day is full. Remove something first.")
    public let targets = Targets()
    /// The weekly check-in.
    public let checkIn = CheckIn()
    /// The diary: one day at a time.
    public let diary = Diary()
    /// Eaten against target. Numbers, so plain.
    public let header = Header()
    public let macros = Macros()
    public let macroNames = MacroNames()
    /// Describe it: type what you ate, the model splits it into foods.
    public let describe = Describe()
    /// Log a recipe. Logging is voice; servings and numbers are plain.
    public let logRecipe = LogRecipe()
    /// Recents and favourites. Re-logging is voice; the rest is plain.
    public let quick = Quick()
    /// Copying a meal or a day.
    public let copyDay = CopyDay()
    /// The add sheet's ways in.
    public let addTabs = AddTabs()
    /// Weigh-ins. Logging is voice; numbers, units, controls and errors are plain.
    public let weight = Weight()
    /// The add sheet and the entry editor. Fields and controls are plain.
    public let entry = Entry()

    public init() {}

    public struct Targets: Sendable {
      public let title = voice("Set your targets")
      public let pageTitle = plain("Targets")
      public let steps = Steps()
      public let sex = plain("Sex")
      public let sexes = Sexes()
      public let sexHint = plain("Used only for the resting energy formula.")
      public let birthDate = plain("Birth date")
      public let height = plain("Height")
      public let heightUnits = HeightUnits()
      public let feet = plain("ft")
      public let inches = plain("in")
      public let weight = plain("Current weight")
      public let weightUnits = WeightUnits()
      public let activity = plain("How active are you?")
      public let activityLevels = ActivityLevels()
      public let goal = plain("What's your goal?")
      public let goals = Goals()
      public let rate = plain("How fast?")
      public let `continue` = plain("Continue")
      public let back = plain("Back")
      public let edit = plain("Edit")
      public let macroLabels = MacroLabels()
      public let unitKcal = plain("kcal")
      public let unitGrams = plain("g")
      public let calculated = plain("calculated")
      public let setByYou = plain("set by you")
      public let reset = plain("Reset")
      public let adjust = plain("Adjust")
      public let proteinPerKg = plain("Protein per kg of bodyweight (g)")
      public let fatShare = plain("Fat share of calories (%)")
      public let save = voice("Set my targets")
      public let saving = voice("Setting…")
      public let saved = voice("Targets set")
      public let settled = plain(
        "These are your daily targets. Change any of them, or run the calculator again.")
      public let couldntSave = plain(
        "Couldn't save your targets. Check your connection and try again.")
      public let couldntLoad = plain("Couldn't load your details. Try again.")
      public let fixThese = plain("Check the highlighted fields.")

      public init() {}

      public func step(_ n: Int, _ of: Int) -> CopyString { plain("Step \(n) of \(of)") }
      public func unitSwitch(_ what: String) -> CopyString { plain("\(what) unit") }
      public func perWeek(_ amount: String, _ unit: String) -> CopyString {
        plain("\(amount) \(unit) a week")
      }
      public func summaryAge(_ years: Int) -> CopyString { plain("\(years) years") }
      // The reasoning, in plain words.
      public func headline(_ goal: Goal, _ kcal: String, _ amount: String, _ unit: String)
        -> CopyString
      {
        plain(
          goal == .maintain
            ? "About \(kcal) kcal a day to stay where you are."
            : "About \(kcal) kcal a day to \(goal.rawValue) \(amount) \(unit) a week.")
      }
      public func breakdown(_ resting: String, _ multiplier: String, _ burned: String)
        -> CopyString
      {
        plain(
          "Resting energy \(resting) kcal x \(multiplier) for activity = \(burned) kcal burned a day."
        )
      }
      public func adjustLose(_ kcal: String) -> CopyString {
        plain("Minus \(kcal) kcal a day for your goal.")
      }
      public func adjustGain(_ kcal: String) -> CopyString {
        plain("Plus \(kcal) kcal a day for your goal.")
      }
      public func floor(_ kcal: String) -> CopyString {
        plain("That went below the safety floor, so it was raised to \(kcal) kcal.")
      }
      public func resetLabel(_ what: String) -> CopyString {
        plain("Reset \(what) to the calculated value")
      }

      public struct Steps: Sendable {
        public let about = plain("About you")
        public let activity = plain("Activity and goal")
        public let targets = plain("Your targets")

        public init() {}
      }

      public struct Sexes: Sendable {
        public let female = plain("Female")
        public let male = plain("Male")
        public let unspecified = plain("Prefer not to say")

        public init() {}

        public subscript(sex: Sex) -> CopyString {
          switch sex {
          case .female: female
          case .male: male
          case .unspecified: unspecified
          }
        }
      }

      public struct HeightUnits: Sendable {
        public let cm = plain("cm")
        public let ftin = plain("ft/in")

        public init() {}

        public subscript(unit: HeightUnit) -> CopyString {
          switch unit {
          case .cm: cm
          case .ftin: ftin
          }
        }
      }

      public struct WeightUnits: Sendable {
        public let kg = plain("kg")
        public let lb = plain("lb")

        public init() {}

        public subscript(unit: WeightUnit) -> CopyString {
          switch unit {
          case .kg: kg
          case .lb: lb
          }
        }
      }

      /// A label and the hint under it.
      public struct Described: Sendable {
        public let label: CopyString
        public let hint: CopyString
      }

      public struct ActivityLevels: Sendable {
        public let sedentary = Described(
          label: plain("Sedentary"), hint: plain("Desk job, little exercise."))
        public let light = Described(
          label: plain("Lightly active"), hint: plain("Exercise 1 to 3 days a week."))
        public let moderate = Described(
          label: plain("Moderately active"), hint: plain("Exercise 3 to 5 days a week."))
        public let active = Described(
          label: plain("Very active"), hint: plain("Hard exercise 6 to 7 days a week."))
        public let veryActive = Described(
          label: plain("Extremely active"), hint: plain("Physical job plus hard training."))

        public init() {}

        public subscript(level: ActivityLevel) -> Described {
          switch level {
          case .sedentary: sedentary
          case .light: light
          case .moderate: moderate
          case .active: active
          case .veryActive: veryActive
          }
        }
      }

      public struct Goals: Sendable {
        public let lose = plain("Lose weight")
        public let maintain = plain("Maintain")
        public let gain = plain("Gain weight")

        public init() {}

        public subscript(goal: Goal) -> CopyString {
          switch goal {
          case .lose: lose
          case .maintain: maintain
          case .gain: gain
          }
        }
      }

      public struct MacroLabels: Sendable {
        public let calories = plain("Calories")
        public let protein = plain("Protein")
        public let carbs = plain("Carbs")
        public let fat = plain("Fat")

        public init() {}
      }
    }

    public struct CheckIn: Sendable {
      public let pageTitle = plain("Check-in")
      public let title = voice("This week's check-in")
      public let banner = plain(
        "A week of food and weigh-ins is in. Time to see how your targets are doing.")
      public let bannerAction = voice("Divine this week's check-in")
      public let expenditure = plain("Estimated daily burn")
      public let perDay = plain("kcal a day")
      public let thin = plain("There isn't enough yet to measure, so this leans on the calculator.")
      public let leans = plain("There's still little to go on, so this leans on the calculator.")
      public let progress = plain("Progress")
      public let expected = plain("Goal")
      public let actual = plain("Trend")
      public let noTrend = plain("Not enough weigh-ins yet")
      public let targets = plain("Targets")
      public let now = plain("Now")
      public let proposed = plain("Proposed")
      public let keepHandSet = plain("Keep my hand-set targets")
      public let keepHandSetHint = plain("Targets you typed in yourself stay as they are.")
      public let floored = plain("Held at the calorie floor so the target isn't too low.")
      public let unchanged = plain("The proposed targets match your current ones.")
      public let accept = voice("Accept these targets")
      public let accepting = voice("Setting…")
      public let notNow = plain("Not now")
      public let accepted = voice("Targets set")
      public let deferred = plain("Okay, we'll ask again next week.")
      public let couldntSave = plain("Couldn't save that. Check your connection and try again.")
      public let couldntLoad = plain("Couldn't load your check-in. Try again.")
      public let retry = plain("Try again")
      public let needTargets = plain("Set your daily targets first, then check in once a week.")

      public init() {}

      public func basedOn(_ days: Int, _ weighIns: Int, _ weeks: Int) -> CopyString {
        let loggedDays = "\(days) logged \(days == 1 ? "day" : "days")"
        let weighInCount = "\(weighIns) \(weighIns == 1 ? "weigh-in" : "weigh-ins")"
        let weekCount = "\(weeks) \(weeks == 1 ? "week" : "weeks")"
        return plain("Based on \(loggedDays) and \(weighInCount) over the last \(weekCount).")
      }
      public func perWeek(_ amount: String, _ unit: String) -> CopyString {
        plain("\(amount) \(unit) a week")
      }
    }

    public struct Diary: Sendable {
      public let previousDay = plain("Previous day")
      public let nextDay = plain("Next day")
      public let today = plain("Today")
      public let yesterday = plain("Yesterday")
      public let tomorrow = plain("Tomorrow")
      public let pickDay = plain("Pick a day")
      public let couldntLoad = plain("Couldn't load the day.")
      public let couldntSave = plain(
        "Couldn't save that change. Check your connection and try again.")
      public let retry = plain("Try again")
      public let empty = voice("Nothing logged yet. Add what you've eaten as the day goes.")
      public let add = plain("Add")
      public let undo = plain("Undo")
      public let estimate = plain("estimate")
      public let gaps = plain("Some numbers missing")

      public init() {}

      public func addTo(_ slot: String) -> CopyString { plain("Add to \(slot.lowercased())") }
      public func logged(_ name: String) -> CopyString { plain("Logged \(name).") }
      public func loggedMany(_ n: Int) -> CopyString {
        plain(n == 1 ? "Logged 1 item." : "Logged \(n) items.")
      }
      public func removed(_ name: String) -> CopyString { plain("Removed \(name).") }
      public func edit(_ name: String) -> CopyString { plain("Change \(name)") }
    }

    public struct Header: Sendable {
      public let label = plain("Eaten against target")
      public let eaten = plain("eaten")
      public let of = plain("of")
      public let noTargets = plain("Set daily targets to see how the day measures up.")
      public let setTargets = voice("Divine your targets")
      public let targets = plain("Targets")

      public init() {}

      public func left(_ n: String) -> CopyString { plain("\(n) left") }
      public func over(_ n: String) -> CopyString { plain("\(n) over") }
    }

    public struct Macros: Sendable {
      public let calories = plain("kcal")
      public let protein = plain("protein")
      public let carbs = plain("carbs")
      public let fat = plain("fat")
      public let grams = plain("g")

      public init() {}
    }

    public struct MacroNames: Sendable {
      public let calories = plain("Calories")
      public let protein = plain("Protein")
      public let carbs = plain("Carbs")
      public let fat = plain("Fat")

      public init() {}
    }

    public struct Describe: Sendable {
      public let heading = plain("Describe it")
      public let hint = plain("Say what you ate, with amounts if you know them.")
      public let label = plain("What you ate")
      public let placeholder = plain("2 eggs, a slice of sourdough with butter, black coffee")
      public let divine = voice("Divine it")
      public let divining = voice("Divining…")
      public let review = plain("Check these before logging. The numbers are estimates.")
      public let notFood = plain("Not something we could estimate")
      public let total = plain("Total")
      public let startOver = plain("Start over")
      public let unavailable = plain(
        "Describing needs an AI model, and none is set up. Use quick add instead.")
      public let failed = plain("Couldn't estimate that just now. Try again, or use quick add.")
      public let unreadable = plain("Couldn't find any food in that. Try naming what you ate.")
      public let nothingLeft = plain("Nothing left to log.")

      public init() {}

      public func remove(_ name: String) -> CopyString { plain("Remove \(name)") }
      public func log(_ n: Int) -> CopyString { plain(n == 1 ? "Log 1 item" : "Log \(n) items") }
    }

    public struct LogRecipe: Sendable {
      public let title = plain("Log it")
      public let search = plain("Search your recipes")
      public let noNumbers = plain("No calories yet")
      public let aServing = plain("a serving")
      public let change = plain("Change recipe")
      public let gaps = plain(
        "This recipe is missing some numbers. Divine them from the ingredients, or log what's known."
      )

      public init() {}
    }

    public struct Quick: Sendable {
      public let favourites = plain("Favourites")
      public let recents = plain("Recent")
      public let empty = voice(
        "Nothing logged lately. Describe a meal and it'll be here next time.")
      public let favourite = plain("Favourite")
      public let unfavourite = plain("Unfavourite")
      public let couldntLoad = plain("Couldn't load your recent foods.")

      public init() {}

      public func logAgain(_ name: String) -> CopyString { plain("Log \(name) again") }
      public func star(_ name: String) -> CopyString { plain("Add \(name) to favourites") }
      public func unstar(_ name: String) -> CopyString { plain("Remove \(name) from favourites") }
      public func starred(_ name: String) -> CopyString { plain("\(name) is a favourite.") }
      public func times(_ n: Int) -> CopyString { plain("\(n)×") }
    }

    public struct CopyDay: Sendable {
      public let open = plain("Copy a day")
      public let copyYesterday = plain("Copy yesterday")
      public let from = plain("From")
      public let meal = plain("Meal")
      public let wholeDay = plain("The whole day")
      public let copy = plain("Copy")
      public let nothing = plain("Nothing logged there to copy.")
      public let sameDay = plain("Pick a different day to copy from.")

      public init() {}

      public func title(_ day: String) -> CopyString { plain("Copy into \(day)") }
      public func copied(_ n: Int) -> CopyString {
        plain(n == 1 ? "Copied 1 item." : "Copied \(n) items.")
      }
    }

    public struct AddTabs: Sendable {
      public let label = plain("How to add")
      public let recents = plain("Recent")
      public let describe = plain("Describe")
      public let recipe = plain("Recipe")
      public let quick = plain("Quick add")

      public init() {}
    }

    public struct Weight: Sendable {
      public let pageTitle = plain("Weight")
      public let link = plain("Weight")
      public let logWeight = plain("Log weight")
      public let logTitle = plain("Weigh-in")
      public let seeTrend = plain("See the trend")
      public let day = plain("Day")
      public let save = plain("Save")
      public let saving = plain("Saving…")
      public let remove = plain("Remove")
      public let cancel = plain("Cancel")
      public let needDay = plain("Pick a day that isn't in the future.")
      public let couldntSave = plain(
        "Couldn't save that weight. Check your connection and try again.")
      public let couldntRemove = plain(
        "Couldn't remove that weigh-in. Check your connection and try again.")
      public let couldntLoad = plain("Couldn't load your weight.")
      public let retry = plain("Try again")
      public let ranges = Ranges()
      public let rangeLabel = plain("Time range")
      public let chartLabel = plain("Weight over time")
      public let legendScale = plain("Weigh-in")
      public let legendTrend = plain("Trend")
      public let trendNow = plain("Trend weight")
      public let lastWeek = plain("Last 7 days")
      public let lastMonth = plain("Last 30 days")
      public let notEnough = plain("Not enough yet")
      public let intakeTitle = plain("Average intake")
      public let intakeNone = plain("No food logged in this range.")
      public let listTitle = plain("Weigh-ins")
      public let add = plain("Log a past day")
      public let empty = voice("No weigh-ins yet. Log one and the trend starts to show.")

      public init() {}

      public func logFor(_ day: String) -> CopyString { plain("Weigh-in for \(day)") }
      public func change(_ weight: String) -> CopyString {
        plain("Change weight, now \(weight)")
      }
      public func label(_ unit: String) -> CopyString { plain("Weight (\(unit))") }
      public func outOfRange(_ min: String, _ max: String, _ unit: String) -> CopyString {
        plain("Enter a weight between \(min) and \(max) \(unit).")
      }
      public func chartSummary(_ n: Int, _ from: String, _ to: String) -> CopyString {
        plain("\(n) weigh-ins from \(from) to \(to), with the trend line.")
      }
      public func intakeAcross(_ n: Int) -> CopyString {
        plain(n == 1 ? "across 1 logged day" : "across \(n) logged days")
      }
      public func edit(_ day: String) -> CopyString { plain("Change the weigh-in for \(day)") }
      public func removeFor(_ day: String) -> CopyString {
        plain("Remove the weigh-in for \(day)")
      }
      public func removed(_ day: String) -> CopyString {
        plain("Removed the weigh-in for \(day).")
      }

      public struct Ranges: Sendable {
        public let oneMonth = plain("1M")
        public let threeMonths = plain("3M")
        public let oneYear = plain("1Y")
        public let all = plain("All")

        public init() {}
      }
    }

    public struct Entry: Sendable {
      public let quickAdd = plain("Quick add")
      public let quickAddHint = plain("Type in a name and its numbers.")
      public let name = plain("Name")
      public let namePlaceholder = plain("Flat white, apple…")
      public let amount = plain("Amount")
      public let amountPlaceholder = plain("1 cup, 2 slices…")
      public let servings = plain("Servings")
      public let fewer = plain("Fewer servings")
      public let more = plain("More servings")
      public let perServing = plain("Per serving")
      public let meal = plain("Meal")
      public let day = plain("Day")
      public let log = plain("Log it")
      public let save = plain("Save")
      public let remove = plain("Remove")
      public let cancel = plain("Cancel")
      public let fromRecipe = plain("From a recipe")
      public let described = plain("Described")
      public let byHand = plain("Typed in")
      public let total = plain("Total")

      public init() {}

      public func addTitle(_ slot: String) -> CopyString { plain("Add to \(slot.lowercased())") }
    }
  }
}
