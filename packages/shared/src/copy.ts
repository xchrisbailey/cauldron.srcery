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
  couldntReadPage: plain("Couldn't read that page. Paste the recipe text instead."),
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
  count: (n: number) => plain(n === 1 ? "1 recipe" : `${n} recipes`),
  results: plain("Recipes"),
  actions: plain("Jump to"),
  openWeek: plain("Open the week"),
  noResults: plain("Nothing matches. Try another word."),
  summonHelp: plain("Use the arrow keys to choose and Enter to open."),
} as const;

export const brewing = {
  nextStep: plain("Next step"),
  previousStep: plain("Previous step"),
} as const;

export const week = {
  title: plain("The week"),
  empty: voice("The cauldron's cold. Stir in a recipe to start the week."),
} as const;

export const gather = {
  title: voice("Gather list"),
  empty: voice("Nothing to gather yet. Stir recipes into the week and the list fills itself."),
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
