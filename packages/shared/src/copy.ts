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

// Account emails and screens. Account and auth copy stays plain: it's about
// trust and access, not cooking.
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
  sourceUrl: plain("Source link"),
  tags: plain("Tags"),
  tagsHint: plain("Press Enter or comma to add a tag."),
  removeTag: (name: string) => plain(`Remove tag ${name}`),
  notes: plain("Notes"),
  ingredients: plain("Ingredients"),
  ingredientsHint: plain(
    "One ingredient per line, like “1 1/2 cups flour, sifted”. Paste a whole list to split it. A line like “For the sauce:” starts a section.",
  ),
  ingredientLine: (n: number) => plain(`Ingredient ${n}`),
  heading: (n: number) => plain(`Section heading ${n}`),
  addIngredient: plain("Add ingredient"),
  addHeading: plain("Add section"),
  steps: plain("Method"),
  stepsHint: plain(
    "Enter starts a new step and Shift+Enter a new line. Times like “bake 25 minutes” become timers.",
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
  fixLine: (line: string) => plain(`Fix how “${line}” was read`),
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
} as const;

// Recipe photos (#12). Plain: they're controls and errors.
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

// Start brewing (#20). The controls stay plain: hands are busy. Brewed is voice.
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
  keys: plain("Arrow keys move between steps. Space starts or pauses the timer."),
  noSteps: plain("This recipe has no method steps yet. Add some, then start brewing."),
  editRecipe: plain("Edit recipe"),
  brewed: voice("Brewed"),
  brewedToast: voice("Brewed. Marked as cooked today."),
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

export const nav = {
  recipes: plain("Recipes"),
  week: plain("The week"),
  gather: voice("Gather list"),
  tracker: plain("Tracker"),
  later: plain("later"),
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
