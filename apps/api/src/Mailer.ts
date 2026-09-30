import { Context, Effect, Layer, Ref } from "effect";

export interface Email {
  readonly to: string;
  readonly subject: string;
  readonly text: string;
  readonly html?: string;
}

export class MailerOutbox extends Context.Service<MailerOutbox, Ref.Ref<ReadonlyArray<Email>>>()(
  "cauldron/api/MailerOutbox",
) {}

/** Transactional email. #5 adds the Resend layer; until then `layer` logs instead of sending. */
export class Mailer extends Context.Service<
  Mailer,
  { readonly send: (email: Email) => Effect.Effect<void> }
>()("cauldron/api/Mailer") {
  static readonly layer = Layer.succeed(
    Mailer,
    Mailer.of({
      send: Effect.fn("Mailer.send")(function* (email) {
        yield* Effect.logInfo("Email (not sent: no provider configured)", {
          to: email.to,
          subject: email.subject,
        });
      }),
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
