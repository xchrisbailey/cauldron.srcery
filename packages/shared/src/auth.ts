import { Schema } from "effect";
import { auth, errors } from "./copy.ts";

// Input shapes for the account screens. Better Auth validates again on the
// server; these give the web forms (and later iOS) the same rules and plain messages.

const Email = Schema.String.check(
  Schema.isPattern(/^[^\s@]+@[^\s@]+\.[^\s@]+$/, { message: auth.invalidEmail.text }),
);
const Password = Schema.String.check(
  Schema.isMinLength(8, { message: auth.passwordTooShort.text }),
);
const Name = Schema.String.check(Schema.isMinLength(1, { message: auth.nameRequired.text }));

export const SignInInput = Schema.Struct({ email: Email, password: Schema.String });
export const SignUpInput = Schema.Struct({ name: Name, email: Email, password: Password });
export const EmailInput = Schema.Struct({ email: Email });
export const NewPasswordInput = Schema.Struct({ password: Password });
/** Used when the password field is shown; accounts without a password skip this form check. */
export const DeleteAccountInput = Schema.Struct({
  password: Schema.String.check(Schema.isMinLength(1, { message: auth.passwordRequired.text })),
});

/** Plain messages for the Better Auth error codes the screens can hit. */
export const authErrorMessage = (code: string | undefined): string => {
  switch (code) {
    case "INVALID_EMAIL_OR_PASSWORD":
      return auth.wrongCredentials.text;
    case "EMAIL_NOT_VERIFIED":
      return auth.emailNotVerified.text;
    case "USER_ALREADY_EXISTS":
    case "USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL":
      return auth.emailTaken.text;
    case "INVALID_TOKEN":
      return auth.linkExpired.text;
    case "INVALID_PASSWORD":
      return auth.wrongPassword.text;
    case "CREDENTIAL_ACCOUNT_NOT_FOUND":
      return auth.noPasswordOnAccount.text;
    case "SESSION_EXPIRED":
      return auth.signInAgainToDelete.text;
    case "TOO_MANY_REQUESTS":
      return errors.tooManyRequests.text;
    default:
      return auth.somethingWentWrong.text;
  }
};
