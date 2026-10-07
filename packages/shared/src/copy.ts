// Every user-facing string lives here, marked `voice` (magic verbs) or `plain`.
// Errors are always plain. #1 fills in the rest of the voice table.

export type Tone = "voice" | "plain";

export interface CopyString {
  readonly tone: Tone;
  readonly text: string;
}

const plain = (text: string): CopyString => ({ tone: "plain", text });

export const errors = {
  unauthorized: plain("Sign in to continue."),
  forbidden: plain("You don't have access to that."),
  notFound: plain("We couldn't find that."),
  invalidRequest: plain("Something in that request wasn't right. Check it and try again."),
  tooManyRequests: plain("That's a lot of requests at once. Wait a moment and try again."),
  internal: plain("Something went wrong on our side. Try again in a moment."),
  unavailable: plain("Cauldron can't reach its database right now. Try again in a moment."),
  crossSite: plain("That request came from another site, so we didn't run it."),
} as const;

// Account emails and screens. Account and auth copy stays plain, because it's
// about trust and access, not cooking.
export const auth = {
  verifyEmailSubject: plain("Confirm your email for Cauldron"),
  verifyEmailBody: (url: string) =>
    plain(
      `Confirm your email address to finish setting up Cauldron:\n\n${url}\n\nIf you didn't sign up, you can ignore this email.`,
    ),
  resetPasswordSubject: plain("Reset your Cauldron password"),
  resetPasswordBody: (url: string) =>
    plain(
      `Use this link to choose a new password. It expires in an hour.\n\n${url}\n\nIf you didn't ask for this, you can ignore this email.`,
    ),
  alreadyHaveAccountSubject: plain("You already have a Cauldron account"),
  alreadyHaveAccountBody: (url: string) =>
    plain(
      `Someone tried to create a Cauldron account with this email address, but you already have one.\n\nSign in here, or use "Forgot password?" on that page if you need a new password:\n\n${url}\n\nIf that wasn't you, you can ignore this email.`,
    ),
  signIn: plain("Sign in"),
  signInWithDevOidc: plain("Continue with dev OIDC"),
  signInAgain: plain("Sign in again"),
  signInAgainToDelete: plain("For your security, sign in again, then delete your account."),
  resendVerificationFor: plain("Enter your email and we'll send a new confirmation link."),
  signUp: plain("Create account"),
  signOut: plain("Sign out"),
  signInWithGoogle: plain("Continue with Google"),
  signInWithApple: plain("Continue with Apple"),
  forgotPassword: plain("Forgot password?"),
  sendResetLink: plain("Send reset link"),
  resetLinkSent: plain("If that email has an account, a reset link is on its way."),
  chooseNewPassword: plain("Choose a new password"),
  passwordUpdated: plain("Password updated. Sign in with your new password."),
  checkEmail: plain("Check your email for a link to confirm your address."),
  emailVerified: plain("Email confirmed. You're signed in."),
  resendVerification: plain("Send the link again"),
  deleteAccount: plain("Delete account"),
  deleteAccountConfirm: plain("Delete your account and everything in it? This can't be undone."),
  name: plain("Name"),
  email: plain("Email"),
  password: plain("Password"),
  newPassword: plain("New password"),
  passwordTooShort: plain("Use at least 8 characters."),
  invalidEmail: plain("Enter a valid email address."),
  nameRequired: plain("Enter your name."),
  wrongCredentials: plain("That email and password don't match."),
  emailNotVerified: plain("Confirm your email first. We sent you a link when you signed up."),
  emailTaken: plain("There's already an account with that email. Sign in instead."),
  linkExpired: plain("That link has expired or was already used. Ask for a new one."),
  passwordRequired: plain("Enter your password."),
  noPasswordOnAccount: plain("This account doesn't have a password. Sign in again to continue."),
  wrongPassword: plain("That password isn't right."),
  somethingWentWrong: plain("Something went wrong. Try again in a moment."),
  signUpClosed: plain("Cauldron isn't taking new accounts right now."),
  signInTitle: plain("Sign in to Cauldron"),
  signUpTitle: plain("Create your Cauldron account"),
  forgotPasswordTitle: plain("Reset your password"),
  noAccount: plain("New here? Create an account"),
  haveAccount: plain("Already have an account? Sign in"),
  backToSignIn: plain("Back to sign in"),
  or: plain("or"),
  account: plain("Account"),
  signedInAs: plain("Signed in as"),
} as const;

const voice = (text: string): CopyString => ({ tone: "voice", text });

// The brand voice (#1): magic verbs with plain nouns. Recipes, ingredients,
// meals and days keep their real names. Quantities, method steps, errors,
// brewing-mode controls and the literal part of delete confirmations stay plain.
export const recipes = {
  conjure: voice("Conjure a recipe"),
  distillFromLink: voice("Distill from a link"),
  distill: voice("Distill"),
  summon: voice("Summon a recipe"),
  stirInto: (day: string) => voice(`Stir into ${day}`),
  startBrewing: voice("Start brewing"),
  brewed: voice("Brewed"),
  saving: voice("Simmering…"),
  saved: voice("Set"),
  empty: voice("No recipes yet. Conjure one, or distill it from a link."),
  /** "Banish" is the voice; the rest is the literal, plain confirmation. */
  banishConfirm: (title: string) => ({
    verb: voice("Banish"),
    confirm: plain(`Banish ${title}? You can undo it straight after.`),
  }),
  /** Title of a duplicated recipe. */
  copyOf: (title: string) => plain(`${title} (copy)`),
  tagNameTaken: plain("You already have a tag with that name."),
  /** Under the search field until #11 lists results. */
  summonHint: plain("Search by recipe name, ingredient or tag."),
} as const;

// Messages for recipe fields that fail the shared schemas. The editor shows
// these through Standard Schema, so they're plain and say how to fix it.
export const validation = {
  required: plain("Fill this in."),
  tooLong: (max: number) => plain(`Keep it to ${max} characters or fewer.`),
  tooMany: (max: number) => plain(`Use ${max} or fewer.`),
  wholeNumber: (min: number, max: number) => plain(`Use a whole number from ${min} to ${max}.`),
  numberBetween: (min: number, max: number) => plain(`Use a number from ${min} to ${max}.`),
  link: plain("Enter a link starting with https://"),
  date: plain("Use a real date, like 2026-10-01."),
  quantity: plain("Use an amount from 0 up to 99,999,999."),
  range: plain("The second amount in a range can't be smaller than the first."),
} as const;

// The recipe editor (#9). Field labels and errors are plain; the save states
// ("Simmering…", "Set") live in `recipes`.
export const editor = {
  newTitle: voice("Conjure a recipe"),
  editTitle: plain("Edit recipe"),
  save: plain("Save recipe"),
  done: plain("Done"),
  startOver: plain("Start over"),
  startOverConfirm: plain("Clear this draft and start over?"),
  draftKept: plain("Draft kept on this device"),
  couldntSave: plain("Couldn't save. Check your connection and try again."),
  leaveTitle: plain("Leave without saving?"),
  leaveBody: plain("Your latest changes haven't been saved yet."),
  leave: plain("Leave"),
  stay: plain("Keep editing"),
  title: plain("Title"),
  description: plain("Description"),
  servings: plain("Serves"),
  prepMinutes: plain("Prep (min)"),
  cookMinutes: plain("Cook (min)"),
  totalMinutes: plain("Total (min)"),
  macros: plain("Per serving"),
  macrosHint: plain("Optional. The week adds these up for each day."),
  /** Asks the model to estimate the macros from the ingredients. */
  divineMacros: voice("Divine from ingredients"),
  divining: voice("Divining…"),
  divined: plain("Estimated from the ingredients. Check them before you save."),
  divineNeedsIngredients: plain("Add some ingredients first."),
  divineUnavailable: plain("Estimating needs an AI model, and none is set up."),
  divineFailed: plain("Couldn't estimate the macros. Try again, or fill them in yourself."),
  macroFields: {
    calories: plain("Calories"),
    protein: plain("Protein (g)"),
    carbs: plain("Carbs (g)"),
    fat: plain("Fat (g)"),
  },
  sourceUrl: plain("Source link"),
  tags: plain("Tags"),
  tagsHint: plain("Press Enter or comma to add a tag."),
  removeTag: (name: string) => plain(`Remove tag ${name}`),
  notes: plain("Notes"),
  ingredients: plain("Ingredients"),
  ingredientsHint: plain(
    'One ingredient per line, like "1 1/2 cups flour, sifted". Paste a whole list to split it. A line like "For the sauce:" starts a section.',
  ),
  ingredientLine: (n: number) => plain(`Ingredient ${n}`),
  heading: (n: number) => plain(`Section heading ${n}`),
  addIngredient: plain("Add ingredient"),
  addHeading: plain("Add section"),
  steps: plain("Method"),
  stepsHint: plain(
    'Enter starts a new step and Shift+Enter a new line. Times like "bake 25 minutes" become timers.',
  ),
  step: (n: number) => plain(`Step ${n}`),
  addStep: plain("Add step"),
  remove: plain("Remove"),
  move: plain("Move"),
  moveHint: plain(
    "Drag, or press the arrow keys, to reorder. Alt plus an arrow key moves a row from its field.",
  ),
  moved: (n: number, of: number) => plain(`Moved to position ${n} of ${of}.`),
  fix: plain("Fix"),
  fixLine: (line: string) => plain(`Fix how "${line}" was read`),
  resetLine: plain("Read it from the line again"),
  quantity: plain("Quantity"),
  unit: plain("Unit"),
  noUnit: plain("No unit"),
  item: plain("Ingredient"),
  note: plain("Note"),
  optional: plain("Optional"),
  addTimer: plain("Add timer"),
  changeTimer: plain("Change timer"),
  timerMinutes: plain("Timer (min)"),
  clearTimer: plain("Remove timer"),
  needsALook: plain("Check this"),
  fixErrors: plain("Some fields need a fix before this can be saved."),
  /** For a quantity typed into the correction fields. */
  badQuantity: plain("Use a number, a fraction like 1 1/2, or a range like 2-3."),
} as const;

// The recipe page (#10). Quantities, steps and controls are plain.
export const recipeView = {
  ingredients: plain("Ingredients"),
  method: plain("Method"),
  checked: (n: number, of: number) => plain(`${n} of ${of}`),
  serves: (n: number) => plain(`serves ${n}`),
  scale: (factor: string) => plain(`×${factor}`),
  fewer: plain("Fewer servings"),
  more: plain("More servings"),
  servingsFor: plain("Servings"),
  units: plain("Units"),
  asWritten: plain("As written"),
  metric: plain("Metric"),
  us: plain("US"),
  total: plain("total"),
  prep: plain("prep"),
  cook: plain("cook"),
  from: (source: string) => plain(`From ${source}`),
  by: (author: string) => plain(`by ${author}`),
  edit: plain("Edit"),
  duplicate: plain("Duplicate"),
  duplicated: plain("Copy made. You're editing it now."),
  print: plain("Print"),
  markBrewed: voice("Brewed it today"),
  brewedToday: voice("Brewed. Marked as cooked today."),
  lastCooked: (date: string) => plain(`Last cooked ${date}`),
  banished: (title: string) => plain(`Banished ${title}.`),
  optional: plain("optional"),
  undo: plain("Undo"),
  restored: plain("Restored."),
  cancel: plain("Cancel"),
  notFound: plain("We couldn't find that recipe. It may have been banished."),
  backToRecipes: plain("Back to recipes"),
} as const;

// The recipe library (#11) and the ⌘K palette. Controls and counts are plain.
export const library = {
  search: plain("Search recipes"),
  searchPlaceholder: plain("Name, ingredient or tag"),
  sort: plain("Sort"),
  sortRecent: plain("Newest"),
  sortTitle: plain("A to Z"),
  sortLastCooked: plain("Last cooked"),
  tag: plain("Tag"),
  allTags: plain("All tags"),
  view: plain("View"),
  grid: plain("Grid"),
  list: plain("List"),
  noMatches: plain("No recipes match that. Try another word, or clear the filters."),
  clearFilters: plain("Clear filters"),
  loadingMore: plain("Loading more recipes"),
  couldntLoadMore: plain("Couldn't load more recipes."),
  retry: plain("Try again"),
  tagOption: (name: string, n: number) => plain(`${name} (${n})`),
  count: (n: number) => plain(n === 1 ? "1 recipe" : `${n} recipes`),
  results: plain("Recipes"),
  actions: plain("Jump to"),
  openWeek: plain("Open the week"),
  noResults: plain("Nothing matches. Try another word."),
  summonHelp: plain("Use the arrow keys to choose and Enter to open."),
  /** The compact per-serving line on a card, and what it reads aloud. Plain: quantities. */
  macroLine: {
    calories: (n: string) => plain(`${n} kcal`),
    protein: (g: string) => plain(`${g}P`),
    fat: (g: string) => plain(`${g}F`),
    carbs: (g: string) => plain(`${g}C`),
    spoken: {
      calories: (n: string) => plain(`${n} kcal`),
      protein: (g: string) => plain(`${g} g protein`),
      fat: (g: string) => plain(`${g} g fat`),
      carbs: (g: string) => plain(`${g} g carbs`),
      label: (parts: string) => plain(`Per serving: ${parts}`),
    },
  },
} as const;

// Recipe photos (#12). Plain, since they're controls and errors.
export const photos = {
  add: plain("Add a photo"),
  replace: plain("Replace photo"),
  remove: plain("Remove photo"),
  uploading: plain("Uploading photo…"),
  alt: (title: string) => plain(`Photo of ${title}`),
  unsupported: plain("Use a JPEG, PNG, WebP or AVIF photo."),
  tooLarge: plain("That photo is over 15 MB. Try a smaller one."),
  tooBig: plain("That photo is too large to process. Try a smaller one."),
  couldntRead: plain("We couldn't read that photo. Try another one."),
  couldntFetch: plain("We couldn't fetch a photo from that link."),
  uploadExpired: plain("That upload has expired. Choose the photo again."),
  storageFull: plain(
    "Your photo storage is full. Take photos off recipes you no longer need; the space comes back within a day.",
  ),
} as const;

// Distill (#13 to #16): importing a recipe from a link or pasted text. The
// action is voice; labels, statuses and every failure are plain.
export const imports = {
  title: voice("Distill a recipe"),
  distill: voice("Distill"),
  distilling: voice("Distilling…"),
  link: plain("Link"),
  linkPlaceholder: plain("https://"),
  linkHint: plain("A recipe page, or an Instagram or TikTok post."),
  orPaste: plain("Or paste the recipe"),
  pasteHint: plain("Paste it from anywhere: a notes app, an email, a caption."),
  pastePlaceholder: plain("Title, ingredients and method"),
  stop: plain("Stop"),
  stopped: plain("Stopped."),
  another: voice("Distill another"),
  review: plain("Check the highlighted fields, then save."),
  unsureLine: plain("we may have misread it"),
  source: plain("Source"),
  pasted: plain("Pasted text"),
  duplicate: (title: string) => plain(`You already have a recipe from this link: ${title}.`),
  openDuplicate: plain("Open it"),
  saveAnyway: plain("Saving makes a second copy."),
  pasteInstead: plain("Paste the text instead"),
  tryAgain: plain("Try again"),
  couldntStart: plain("Couldn't start distilling. Check your connection and try again."),
  alreadySaved: plain("That draft is already saved."),
  notReady: plain("That draft isn't ready to save."),
  // Failures. Each one suggests what to do next.
  couldntRead: plain("Couldn't read that page. Paste the recipe text instead."),
  noRecipe: plain("We couldn't find a recipe there. Paste the recipe text instead."),
  noRecipeInText: plain(
    "We couldn't find a recipe in that text. Check it has the ingredients and the method.",
  ),
  spokenOnly: plain(
    "That post's caption doesn't have the recipe. It may only be spoken in the video, so paste the recipe text instead.",
  ),
  tooLarge: plain("That page is too large to read. Paste the recipe text instead."),
  blocked: plain("We can't open that link. Paste the recipe text instead."),
  timeout: plain("That took too long. Try again, or paste the recipe text instead."),
  unavailable: plain(
    "Distilling isn't available right now. Try again in a moment, or conjure the recipe by hand.",
  ),
  dailyLimit: plain(
    "That's a lot of distilling for one day. Try again tomorrow, or conjure the recipe by hand.",
  ),
} as const;

// Start brewing (#20). The controls stay plain because hands are busy. Brewed is voice.
export const brewing = {
  nextStep: plain("Next step"),
  previousStep: plain("Previous step"),
  stepOf: (n: number, of: number) => plain(`${n} of ${of}`),
  leave: plain("Back to the recipe"),
  forThisStep: plain("For this step"),
  startTimer: plain("Start timer"),
  pause: plain("Pause"),
  resume: plain("Resume"),
  reset: plain("Reset"),
  timeUp: plain("Time's up"),
  timerFor: (n: number) => plain(`Step ${n}`),
  timerDone: (title: string, n: number) => plain(`${title}: the step ${n} timer is done.`),
  timers: plain("Timers"),
  wakeOn: plain("Screen stays on while you brew"),
  wakeOff: plain("This browser can't keep the screen on, so it may sleep."),
  wakeRefused: plain("The browser wouldn't keep the screen on just now, so it may sleep."),
  keys: plain("Arrow keys move between steps. Space starts or pauses the timer."),
  noSteps: plain("This recipe has no method steps yet. Add some, then start brewing."),
  editRecipe: plain("Edit recipe"),
  brewed: voice("Brewed"),
  couldntSave: plain("Couldn't mark it cooked. Check your connection and try again."),
} as const;

// The week (#18). Stirring in is voice; days, meals, controls and the literal
// part of the clear confirmation are plain.
export const week = {
  title: plain("The week"),
  empty: voice("The cauldron's cold. Stir in a recipe to start the week."),
  slots: {
    breakfast: plain("Breakfast"),
    lunch: plain("Lunch"),
    dinner: plain("Dinner"),
    snack: plain("Snack"),
  },
  previousWeek: plain("Previous week"),
  nextWeek: plain("Next week"),
  thisWeek: plain("This week"),
  today: plain("today"),
  days: plain("Days"),
  copyLastWeek: plain("Copy last week"),
  copiedLastWeek: plain("Copied last week's meals."),
  nothingToCopy: plain("Last week has nothing planned."),
  /** "Clear" is a plain verb here: it removes things. */
  clearWeek: plain("Clear week"),
  clearConfirm: (range: string) =>
    plain(`Clear every meal planned for ${range}? This can't be undone.`),
  cleared: plain("Cleared the week."),
  cancel: plain("Cancel"),
  stirIn: voice("Stir in"),
  stirInto: (day: string, slot: string) => voice(`Stir into ${day}, ${slot.toLowerCase()}`),
  stirIntoWeek: voice("Stir into the week"),
  stirred: (day: string) => voice(`Stirred into ${day}.`),
  /** The meal-picker: search the recipe box, or write a meal that isn't a recipe. */
  searchRecipes: plain("Search your recipes"),
  noMatches: plain("No recipes match that."),
  orWrite: plain("Or write a meal"),
  writePlaceholder: plain("Leftovers, eating out…"),
  add: plain("Add"),
  day: plain("Day"),
  slot: plain("Meal"),
  servings: plain("Servings"),
  sameServings: (n: number | null) => plain(n === null ? "As the recipe" : `As the recipe (${n})`),
  edit: (title: string) => plain(`Change ${title}`),
  open: plain("Open recipe"),
  remove: plain("Remove"),
  removed: (title: string) => plain(`Removed ${title}.`),
  undo: plain("Undo"),
  save: plain("Save"),
  brewed: voice("✓ brewed"),
  leftovers: plain("not a recipe"),
  recipesPanel: plain("Recipes"),
  dragHint: plain("Drag a recipe onto a meal, or press + on a meal to stir one in."),
  moveHint: plain("Drag a meal to move it to another day."),
  weekStarts: plain("Week starts on"),
  monday: plain("Monday"),
  sunday: plain("Sunday"),
  couldntSave: plain("Couldn't save that change. Check your connection and try again."),
  couldntLoad: plain("Couldn't load the week."),
  retry: plain("Try again"),
  slotFull: plain("That meal is full. Remove something first."),
  moveUp: plain("Move up"),
  moveDown: plain("Move down"),
  meal: plain("Meal"),
  /** The running tally of calories and macros: all plain, they're numbers. */
  tally: {
    label: plain("Calories and macros"),
    week: plain("Week"),
    perDay: plain("a day"),
    macros: {
      calories: plain("kcal"),
      protein: plain("protein"),
      carbs: plain("carbs"),
      fat: plain("fat"),
    },
    none: plain("Add calories and macros to your recipes to see totals here."),
    gaps: (n: number) =>
      plain(
        n === 1
          ? "1 meal has no calories or macros, so it isn't fully counted."
          : `${n} meals have no calories or macros, so they aren't fully counted.`,
      ),
    showDay: (day: string) => plain(`Show ${day}`),
    clearDay: plain("Back to the week"),
  },
  /** Spreading one recipe's servings over the days that will eat them. */
  spread: {
    days: plain("Days"),
    hint: plain("Pick the days this batch feeds. Each day gets one serving unless you change it."),
    planned: (n: number, of: number | null) =>
      plain(
        of === null
          ? `${n} ${n === 1 ? "serving" : "servings"} planned`
          : `${n} of ${of} servings planned`,
      ),
    oneADay: plain("One a day"),
    allOn: (day: string) => plain(`All on ${day}`),
    fewer: (day: string) => plain(`Fewer servings on ${day}`),
    more: (day: string) => plain(`More servings on ${day}`),
    servingsOn: (n: number) => plain(`${n} ${n === 1 ? "serving" : "servings"}`),
    stir: (n: number) => voice(n === 1 ? "Stir into 1 day" : `Stir into ${n} days`),
    stirred: (n: number) => voice(n === 1 ? "Stirred into 1 day." : `Stirred into ${n} days.`),
    pickADay: plain("Pick at least one day."),
  },
} as const;

// The Gather list (#19). Gather is voice; aisles, items, amounts and controls are plain.
export const gather = {
  title: voice("Gather list"),
  empty: voice("Nothing to gather yet. Stir recipes into the week and the list fills itself."),
  gather: voice("Gather"),
  aisles: {
    produce: plain("Produce"),
    meat: plain("Meat and fish"),
    dairy: plain("Dairy and eggs"),
    bakery: plain("Bakery"),
    pantry: plain("Pantry"),
    spices: plain("Spices"),
    frozen: plain("Frozen"),
    drinks: plain("Drinks"),
    other: plain("Other"),
  },
  addItem: plain("Add an item"),
  addPlaceholder: plain("2 lemons, oat milk…"),
  add: plain("Add"),
  hideChecked: plain("Hide checked"),
  checked: (n: number, of: number) => plain(`${n} of ${of} gathered`),
  forRecipes: (titles: string) => plain(`For ${titles}`),
  addedByHand: plain("Added by you"),
  inPantry: plain("In the pantry"),
  markInPantry: (item: string) => plain(`${item} is in the pantry`),
  remove: (item: string) => plain(`Remove ${item}`),
  allChecked: voice("Everything's gathered. Time to brew."),
  summary: (items: number, recipes: number) =>
    plain(
      `${items === 1 ? "1 ingredient" : `${items} ingredients`} across ${recipes === 1 ? "1 recipe" : `${recipes} recipes`}.`,
    ),
  inPantryCount: (n: number) =>
    plain(n === 1 ? "1 is already in the pantry." : `${n} are already in the pantry.`),
  couldntSave: plain("Couldn't save that change. Check your connection and try again."),
  couldntLoad: plain("Couldn't load the Gather list."),
  retry: plain("Try again"),
} as const;

// The tracker (#23). Logging and divining are voice; numbers, units, meals,
// controls and errors are plain.
export const tracker = {
  title: plain("Tracker"),
  dayFull: plain("That day is full. Remove something first."),
  targets: {
    title: voice("Set your targets"),
    pageTitle: plain("Targets"),
    step: (n: number, of: number) => plain(`Step ${n} of ${of}`),
    steps: {
      about: plain("About you"),
      activity: plain("Activity and goal"),
      targets: plain("Your targets"),
    },
    sex: plain("Sex"),
    sexes: {
      female: plain("Female"),
      male: plain("Male"),
      unspecified: plain("Prefer not to say"),
    },
    sexHint: plain("Used only for the resting energy formula."),
    birthDate: plain("Birth date"),
    height: plain("Height"),
    heightUnits: { cm: plain("cm"), ftin: plain("ft/in") },
    feet: plain("ft"),
    inches: plain("in"),
    weight: plain("Current weight"),
    weightUnits: { kg: plain("kg"), lb: plain("lb") },
    unitSwitch: (what: string) => plain(`${what} unit`),
    activity: plain("How active are you?"),
    activityLevels: {
      sedentary: { label: plain("Sedentary"), hint: plain("Desk job, little exercise.") },
      light: { label: plain("Lightly active"), hint: plain("Exercise 1 to 3 days a week.") },
      moderate: { label: plain("Moderately active"), hint: plain("Exercise 3 to 5 days a week.") },
      active: { label: plain("Very active"), hint: plain("Hard exercise 6 to 7 days a week.") },
      veryActive: {
        label: plain("Extremely active"),
        hint: plain("Physical job plus hard training."),
      },
    },
    goal: plain("What's your goal?"),
    goals: { lose: plain("Lose weight"), maintain: plain("Maintain"), gain: plain("Gain weight") },
    rate: plain("How fast?"),
    perWeek: (amount: string, unit: string) => plain(`${amount} ${unit} a week`),
    continue: plain("Continue"),
    back: plain("Back"),
    edit: plain("Edit"),
    summaryAge: (years: number) => plain(`${years} years`),
    // The reasoning, in plain words.
    headline: (goal: "lose" | "maintain" | "gain", kcal: string, amount: string, unit: string) =>
      plain(
        goal === "maintain"
          ? `About ${kcal} kcal a day to stay where you are.`
          : `About ${kcal} kcal a day to ${goal} ${amount} ${unit} a week.`,
      ),
    breakdown: (resting: string, multiplier: string, burned: string) =>
      plain(
        `Resting energy ${resting} kcal x ${multiplier} for activity = ${burned} kcal burned a day.`,
      ),
    adjustLose: (kcal: string) => plain(`Minus ${kcal} kcal a day for your goal.`),
    adjustGain: (kcal: string) => plain(`Plus ${kcal} kcal a day for your goal.`),
    floor: (kcal: string) =>
      plain(`That went below the safety floor, so it was raised to ${kcal} kcal.`),
    macroLabels: {
      calories: plain("Calories"),
      protein: plain("Protein"),
      carbs: plain("Carbs"),
      fat: plain("Fat"),
    },
    unitKcal: plain("kcal"),
    unitGrams: plain("g"),
    calculated: plain("calculated"),
    setByYou: plain("set by you"),
    reset: plain("Reset"),
    resetLabel: (what: string) => plain(`Reset ${what} to the calculated value`),
    adjust: plain("Adjust"),
    proteinPerKg: plain("Protein per kg of bodyweight (g)"),
    fatShare: plain("Fat share of calories (%)"),
    save: voice("Set my targets"),
    saving: voice("Setting\u2026"),
    saved: voice("Targets set"),
    settled: plain(
      "These are your daily targets. Change any of them, or run the calculator again.",
    ),
    couldntSave: plain("Couldn't save your targets. Check your connection and try again."),
    couldntLoad: plain("Couldn't load your details. Try again."),
    fixThese: plain("Check the highlighted fields."),
  },
  /** The weekly check-in (#118). Magic verbs on the actions; numbers, units, controls and errors plain. */
  checkIn: {
    pageTitle: plain("Check-in"),
    title: voice("This week's check-in"),
    banner: plain("A week of food and weigh-ins is in. Time to see how your targets are doing."),
    bannerAction: voice("Divine this week's check-in"),
    expenditure: plain("Estimated daily burn"),
    perDay: plain("kcal a day"),
    basedOn: (days: number, weighIns: number, weeks: number) =>
      plain(
        `Based on ${days} logged ${days === 1 ? "day" : "days"} and ${weighIns} ${weighIns === 1 ? "weigh-in" : "weigh-ins"} over the last ${weeks} ${weeks === 1 ? "week" : "weeks"}.`,
      ),
    thin: plain("There isn't enough yet to measure, so this leans on the calculator."),
    leans: plain("There's still little to go on, so this leans on the calculator."),
    progress: plain("Progress"),
    expected: plain("Goal"),
    actual: plain("Trend"),
    perWeek: (amount: string, unit: string) => plain(`${amount} ${unit} a week`),
    noTrend: plain("Not enough weigh-ins yet"),
    targets: plain("Targets"),
    now: plain("Now"),
    proposed: plain("Proposed"),
    keepHandSet: plain("Keep my hand-set targets"),
    keepHandSetHint: plain("Targets you typed in yourself stay as they are."),
    floored: plain("Held at the calorie floor so the target isn't too low."),
    unchanged: plain("The proposed targets match your current ones."),
    accept: voice("Accept these targets"),
    accepting: voice("Setting\u2026"),
    notNow: plain("Not now"),
    accepted: voice("Targets set"),
    deferred: plain("Okay, we'll ask again next week."),
    couldntSave: plain("Couldn't save that. Check your connection and try again."),
    couldntLoad: plain("Couldn't load your check-in. Try again."),
    retry: plain("Try again"),
    needTargets: plain("Set your daily targets first, then check in once a week."),
  },
  /** The diary (#113): one day at a time. */
  diary: {
    previousDay: plain("Previous day"),
    nextDay: plain("Next day"),
    today: plain("Today"),
    yesterday: plain("Yesterday"),
    tomorrow: plain("Tomorrow"),
    pickDay: plain("Pick a day"),
    couldntLoad: plain("Couldn't load the day."),
    couldntSave: plain("Couldn't save that change. Check your connection and try again."),
    retry: plain("Try again"),
    empty: voice("Nothing logged yet. Add what you've eaten as the day goes."),
    add: plain("Add"),
    addTo: (slot: string) => plain(`Add to ${slot.toLowerCase()}`),
    logged: (name: string) => plain(`Logged ${name}.`),
    loggedMany: (n: number) => plain(n === 1 ? "Logged 1 item." : `Logged ${n} items.`),
    removed: (name: string) => plain(`Removed ${name}.`),
    undo: plain("Undo"),
    edit: (name: string) => plain(`Change ${name}`),
    estimate: plain("estimate"),
    gaps: plain("Some numbers missing"),
  },
  /** Eaten against target. Numbers, so plain. */
  header: {
    label: plain("Eaten against target"),
    eaten: plain("eaten"),
    of: plain("of"),
    left: (n: string) => plain(`${n} left`),
    over: (n: string) => plain(`${n} over`),
    noTargets: plain("Set daily targets to see how the day measures up."),
    setTargets: voice("Divine your targets"),
    targets: plain("Targets"),
  },
  macros: {
    calories: plain("kcal"),
    protein: plain("protein"),
    carbs: plain("carbs"),
    fat: plain("fat"),
    grams: plain("g"),
  },
  macroNames: {
    calories: plain("Calories"),
    protein: plain("Protein"),
    carbs: plain("Carbs"),
    fat: plain("Fat"),
  },
  /** Describe it (#114): type what you ate, the model splits it into foods. */
  describe: {
    heading: plain("Describe it"),
    hint: plain("Say what you ate, with amounts if you know them."),
    label: plain("What you ate"),
    placeholder: plain("2 eggs, a slice of sourdough with butter, black coffee"),
    divine: voice("Divine it"),
    divining: voice("Divining…"),
    review: plain("Check these before logging. The numbers are estimates."),
    notFood: plain("Not something we could estimate"),
    remove: (name: string) => plain(`Remove ${name}`),
    total: plain("Total"),
    log: (n: number) => plain(n === 1 ? "Log 1 item" : `Log ${n} items`),
    startOver: plain("Start over"),
    unavailable: plain("Describing needs an AI model, and none is set up. Use quick add instead."),
    failed: plain("Couldn't estimate that just now. Try again, or use quick add."),
    unreadable: plain("Couldn't find any food in that. Try naming what you ate."),
    nothingLeft: plain("Nothing left to log."),
  },
  /** Log a recipe (#115). Logging is voice; servings and numbers are plain. */
  logRecipe: {
    title: plain("Log it"),
    search: plain("Search your recipes"),
    noNumbers: plain("No calories yet"),
    aServing: plain("a serving"),
    change: plain("Change recipe"),
    gaps: plain(
      "This recipe is missing some numbers. Divine them from the ingredients, or log what's known.",
    ),
  },
  /** Recents and favourites (#116). Re-logging is voice; the rest is plain. */
  quick: {
    favourites: plain("Favourites"),
    recents: plain("Recent"),
    empty: voice("Nothing logged lately. Describe a meal and it'll be here next time."),
    logAgain: (name: string) => plain(`Log ${name} again`),
    star: (name: string) => plain(`Add ${name} to favourites`),
    unstar: (name: string) => plain(`Remove ${name} from favourites`),
    favourite: plain("Favourite"),
    unfavourite: plain("Unfavourite"),
    starred: (name: string) => plain(`${name} is a favourite.`),
    times: (n: number) => plain(`${n}×`),
    couldntLoad: plain("Couldn't load your recent foods."),
  },
  /** Copying a meal or a day (#116). */
  copyDay: {
    open: plain("Copy a day"),
    copyYesterday: plain("Copy yesterday"),
    title: (day: string) => plain(`Copy into ${day}`),
    from: plain("From"),
    meal: plain("Meal"),
    wholeDay: plain("The whole day"),
    copy: plain("Copy"),
    copied: (n: number) => plain(n === 1 ? "Copied 1 item." : `Copied ${n} items.`),
    nothing: plain("Nothing logged there to copy."),
    sameDay: plain("Pick a different day to copy from."),
  },
  /** The add sheet's ways in. */
  addTabs: {
    label: plain("How to add"),
    recents: plain("Recent"),
    describe: plain("Describe"),
    recipe: plain("Recipe"),
    quick: plain("Quick add"),
  },
  /** Weigh-ins (#117). Logging is voice; numbers, units, controls and errors are plain. */
  weight: {
    pageTitle: plain("Weight"),
    link: plain("Weight"),
    logWeight: plain("Log weight"),
    logTitle: plain("Weigh-in"),
    logFor: (day: string) => plain(`Weigh-in for ${day}`),
    change: (weight: string) => plain(`Change weight, now ${weight}`),
    seeTrend: plain("See the trend"),
    label: (unit: string) => plain(`Weight (${unit})`),
    day: plain("Day"),
    save: plain("Save"),
    saving: plain("Saving…"),
    remove: plain("Remove"),
    cancel: plain("Cancel"),
    outOfRange: (min: string, max: string, unit: string) =>
      plain(`Enter a weight between ${min} and ${max} ${unit}.`),
    needDay: plain("Pick a day that isn't in the future."),
    couldntSave: plain("Couldn't save that weight. Check your connection and try again."),
    couldntRemove: plain("Couldn't remove that weigh-in. Check your connection and try again."),
    couldntLoad: plain("Couldn't load your weight."),
    retry: plain("Try again"),
    ranges: { "1m": plain("1M"), "3m": plain("3M"), "1y": plain("1Y"), all: plain("All") },
    rangeLabel: plain("Time range"),
    chartLabel: plain("Weight over time"),
    chartSummary: (n: number, from: string, to: string) =>
      plain(`${n} weigh-ins from ${from} to ${to}, with the trend line.`),
    legendScale: plain("Weigh-in"),
    legendTrend: plain("Trend"),
    trendNow: plain("Trend weight"),
    lastWeek: plain("Last 7 days"),
    lastMonth: plain("Last 30 days"),
    notEnough: plain("Not enough yet"),
    intakeTitle: plain("Average intake"),
    intakeAcross: (n: number) => plain(n === 1 ? "across 1 logged day" : `across ${n} logged days`),
    intakeNone: plain("No food logged in this range."),
    listTitle: plain("Weigh-ins"),
    add: plain("Log a past day"),
    edit: (day: string) => plain(`Change the weigh-in for ${day}`),
    removeFor: (day: string) => plain(`Remove the weigh-in for ${day}`),
    removed: (day: string) => plain(`Removed the weigh-in for ${day}.`),
    empty: voice("No weigh-ins yet. Log one and the trend starts to show."),
  },
  /** The add sheet and the entry editor. Fields and controls are plain. */
  entry: {
    addTitle: (slot: string) => plain(`Add to ${slot.toLowerCase()}`),
    quickAdd: plain("Quick add"),
    quickAddHint: plain("Type in a name and its numbers."),
    name: plain("Name"),
    namePlaceholder: plain("Flat white, apple…"),
    amount: plain("Amount"),
    amountPlaceholder: plain("1 cup, 2 slices…"),
    servings: plain("Servings"),
    fewer: plain("Fewer servings"),
    more: plain("More servings"),
    perServing: plain("Per serving"),
    meal: plain("Meal"),
    day: plain("Day"),
    log: plain("Log it"),
    save: plain("Save"),
    remove: plain("Remove"),
    cancel: plain("Cancel"),
    fromRecipe: plain("From a recipe"),
    described: plain("Described"),
    byHand: plain("Typed in"),
    total: plain("Total"),
  },
} as const;

export const nav = {
  recipes: plain("Recipes"),
  week: plain("The week"),
  gather: voice("Gather list"),
  tracker: plain("Tracker"),
} as const;

// Browser tab titles for pages that have no nav label or heading of their own.
// Plain nouns; the web app adds the app name (`pageTitle`).
export const pageTitles = {
  signIn: plain("Sign in"),
  signUp: plain("Create account"),
  forgotPassword: plain("Reset your password"),
  resetPassword: plain("Choose a new password"),
  account: plain("Account"),
  recipe: plain("Recipe"),
  brew: plain("Brew"),
} as const;

export const ui = {
  appName: plain("Cauldron"),
  byline: plain("by srcery"),
  footer: voice("Cauldron, stirred at srcery.computer"),
  /** The lockup's wordmark, set in lowercase. */
  wordmark: plain("cauldron"),
  tagline: voice(
    "A recipe box and weekly meal planner. Conjure recipes, distill them from a link, and stir them into the week.",
  ),
  menu: plain("Menu"),
  close: plain("Close"),
  loading: plain("Loading"),
  tryAgain: plain("Try again"),
  skipToContent: plain("Skip to content"),
  mainNav: plain("Main"),
  goHome: plain("Back to Cauldron"),
  switchToLight: plain("Switch to light theme"),
  switchToDark: plain("Switch to dark theme"),
} as const;

/** Quantity words. Always plain. */
export const quantities = {
  /** Shown for amounts below 1/16 tsp. */
  pinch: plain("pinch"),
} as const;
