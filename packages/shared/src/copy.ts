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
  signIn: plain("Sign in"),
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
