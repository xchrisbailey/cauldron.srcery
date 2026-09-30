import { Config, Context, Effect, Layer, Option, Redacted, Ref, Schema } from "effect";
import { FetchHttpClient, HttpClient, HttpClientRequest } from "effect/http";

export interface Email {
  readonly to: string;
  readonly subject: string;
  readonly text: string;
}

export class MailerError extends Schema.TaggedError<MailerError>()("MailerError", {
  cause: Schema.Defect(),
}) {}

export class MailerOutbox extends Context.Service<MailerOutbox, Ref.Ref<ReadonlyArray<Email>>>()(
  "cauldron/api/MailerOutbox",
) {}

/** Transactional email: Resend when RESEND_API_KEY is set, otherwise logged to the console. */
export class Mailer extends Context.Service<
  Mailer,
  { readonly send: (email: Email) => Effect.Effect<void, MailerError> }
>()("cauldron/api/Mailer") {
  static readonly layerResend = (apiKey: Redacted.Redacted<string>, from: string) =>
    Layer.effect(
      Mailer,
      Effect.gen(function* () {
        const client = (yield* HttpClient.HttpClient).pipe(HttpClient.filterStatusOk);
        return Mailer.of({
          send: Effect.fn("Mailer.send")(function* (email) {
            yield* HttpClientRequest.post("https://api.resend.com/emails").pipe(
              HttpClientRequest.bearerToken(Redacted.value(apiKey)),
              HttpClientRequest.bodyJsonUnsafe({
                from,
                to: [email.to],
                subject: email.subject,
                text: email.text,
              }),
              client.execute,
              Effect.scoped,
              Effect.mapError((cause) => new MailerError({ cause })),
            );
          }),
        });
      }),
    ).pipe(Layer.provide(FetchHttpClient.layer));

  /** Logs the email instead of sending it, links included, so local sign-up works without a provider. */
  static readonly layerConsole = Layer.succeed(
    Mailer,
    Mailer.of({
      send: Effect.fn("Mailer.send")(function* (email) {
        yield* Effect.logInfo(`Email to ${email.to}: ${email.subject}\n\n${email.text}`);
      }),
    }),
  );

  static readonly layer = Layer.unwrap(
    Effect.gen(function* () {
      const apiKey = yield* Config.option(Config.Redacted("RESEND_API_KEY"));
      if (Option.isNone(apiKey)) return Mailer.layerConsole;
      const from = yield* Config.String("EMAIL_FROM");
      return Mailer.layerResend(apiKey.value, from);
    }),
  );

  /** Keeps sent mail in memory; read it back through `MailerOutbox`. */
  static readonly layerTest = Layer.effect(
    Mailer,
    Effect.gen(function* () {
      const outbox = yield* MailerOutbox;
      return Mailer.of({ send: (email) => Ref.update(outbox, (sent) => [...sent, email]) });
    }),
  ).pipe(Layer.provideMerge(Layer.effect(MailerOutbox, Ref.make<ReadonlyArray<Email>>([]))));
}
