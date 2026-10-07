import { assert, describe, it } from "@effect/vitest";
import { Effect, Ref } from "effect";
import { TestClock } from "effect/testing";
import { ExtractError, makeModelBudget } from "../src/imports/RecipeExtractor.ts";

const DAY = "24 hours";

describe("makeModelBudget", () => {
  it.effect("lets the limit through, then fails without running the call", () =>
    Effect.gen(function* () {
      const budget = yield* makeModelBudget(3);
      const calls = yield* Ref.make(0);
      const call = budget.guard(Ref.updateAndGet(calls, (n) => n + 1));
      for (let i = 1; i <= 3; i++) assert.strictEqual(yield* call, i);
      const error = yield* call.pipe(Effect.flip);
      assert.instanceOf(error, ExtractError);
      assert.strictEqual(error.reason, "budget");
      assert.strictEqual(yield* Ref.get(calls), 3);
    }),
  );

  it.effect("opens a new window 24 hours after the first call", () =>
    Effect.gen(function* () {
      const budget = yield* makeModelBudget(1);
      const calls = yield* Ref.make(0);
      const call = budget.guard(Ref.updateAndGet(calls, (n) => n + 1));
      yield* call;
      yield* TestClock.adjust("23 hours");
      assert.strictEqual((yield* call.pipe(Effect.flip)).reason, "budget");
      yield* TestClock.adjust("1 hour");
      assert.strictEqual(yield* call, 2);
      assert.strictEqual((yield* call.pipe(Effect.flip)).reason, "budget");
      assert.strictEqual(yield* Ref.get(calls), 2);
    }),
  );

  it.effect("counts failed calls, since they cost quota too", () =>
    Effect.gen(function* () {
      const budget = yield* makeModelBudget(1);
      const boom = budget.guard(Effect.fail(new ExtractError({ reason: "failed" })));
      assert.strictEqual((yield* boom.pipe(Effect.flip)).reason, "failed");
      assert.strictEqual((yield* boom.pipe(Effect.flip)).reason, "budget");
      yield* TestClock.adjust(DAY);
      assert.strictEqual((yield* boom.pipe(Effect.flip)).reason, "failed");
    }),
  );

  it.effect("is shared by everything wrapped with the same budget", () =>
    Effect.gen(function* () {
      const budget = yield* makeModelBudget(2);
      yield* budget.guard(Effect.void);
      yield* budget.guard(Effect.void);
      assert.strictEqual((yield* budget.guard(Effect.void).pipe(Effect.flip)).reason, "budget");
    }),
  );
});
