import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { createAutosave, type SaveStatus } from "../src/lib/autosave.ts";

const WAIT = 800;

/** A persist whose saves finish at once with `status`. */
const settling = (status: SaveStatus) =>
  vi.fn<(values: string) => Promise<SaveStatus>>(async () => status);

/** A persist whose saves finish when the test says so, recording what it was sent. */
const deferredPersist = () => {
  const sent: string[] = [];
  const pending: Array<(status: SaveStatus) => void> = [];
  const persist = (values: string) => {
    sent.push(values);
    return new Promise<SaveStatus>((resolve) => pending.push(resolve));
  };
  const finish = async (status: SaveStatus = "saved") => {
    pending.shift()?.(status);
    await vi.advanceTimersByTimeAsync(0);
  };
  return { sent, persist, finish };
};

const setup = (persist: (values: string) => Promise<SaveStatus>) =>
  createAutosave({ persist, key: (values: string) => values, initial: "a", wait: WAIT });

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("createAutosave", () => {
  it("waits for a quiet spell, then saves the latest change", async () => {
    const persist = settling("saved");
    const autosave = setup(persist);

    autosave.change("ab");
    autosave.change("abc");
    expect(autosave.status()).toBe("pending");
    expect(autosave.dirty()).toBe(true);
    await vi.advanceTimersByTimeAsync(WAIT - 1);
    expect(persist).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(1);
    expect(persist.mock.calls).toEqual([["abc"]]);
    expect(autosave.status()).toBe("saved");
    expect(autosave.dirty()).toBe(false);
  });

  it("lands saves in order, one at a time, and sends a change made mid-save next", async () => {
    const { sent, persist, finish } = deferredPersist();
    const autosave = setup(persist);
    const statuses: SaveStatus[] = [];
    autosave.subscribe(() => statuses.push(autosave.status()));

    autosave.change("ab");
    await vi.advanceTimersByTimeAsync(WAIT);
    expect(sent).toEqual(["ab"]);
    expect(autosave.status()).toBe("saving");

    // Typed while the first save is out: flushed, it waits its turn.
    autosave.change("abc");
    autosave.flush();
    await vi.advanceTimersByTimeAsync(0);
    expect(sent).toEqual(["ab"]);

    await finish();
    expect(sent).toEqual(["ab", "abc"]);
    await finish();
    expect(autosave.status()).toBe("saved");
    expect(autosave.dirty()).toBe(false);
    expect(statuses).toEqual(["pending", "saving", "pending", "saving", "saved"]);
  });

  it("re-saves when the form changed while a save was running", async () => {
    const { sent, persist, finish } = deferredPersist();
    const autosave = setup(persist);

    autosave.change("ab");
    await vi.advanceTimersByTimeAsync(WAIT);
    autosave.change("abc");
    // The first save finishes before the new change's wait is up.
    await finish();
    await vi.advanceTimersByTimeAsync(WAIT);
    expect(sent).toEqual(["ab", "abc"]);
    await finish();
    expect(autosave.dirty()).toBe(false);
  });

  it("sends nothing when a change is undone back to what's saved", async () => {
    const persist = settling("saved");
    const autosave = setup(persist);

    autosave.change("ab");
    autosave.change("a");
    expect(autosave.status()).toBe("idle");
    expect(autosave.dirty()).toBe(false);
    await vi.advanceTimersByTimeAsync(WAIT * 2);
    expect(persist).not.toHaveBeenCalled();
  });

  it("shows the last save's status again once an edit is undone", async () => {
    const persist = settling("kept");
    const autosave = setup(persist);

    autosave.change("ab");
    await vi.advanceTimersByTimeAsync(WAIT);
    autosave.change("abc");
    expect(autosave.status()).toBe("pending");
    autosave.change("ab");
    expect(autosave.status()).toBe("kept");
    await vi.advanceTimersByTimeAsync(WAIT);
    expect(persist).toHaveBeenCalledTimes(1);
  });

  it("keeps trying a change whose save didn't land", async () => {
    const persist = settling("error");
    const autosave = setup(persist);

    autosave.change("ab");
    await vi.advanceTimersByTimeAsync(WAIT);
    expect(autosave.status()).toBe("error");
    expect(autosave.dirty()).toBe(true);
  });

  it("saves a waiting change at once on flush, as on the way out", async () => {
    const persist = settling("saved");
    const autosave = setup(persist);

    autosave.change("ab");
    autosave.flush();
    await autosave.idle();
    expect(persist.mock.calls).toEqual([["ab"]]);
    expect(autosave.dirty()).toBe(false);

    // Nothing waiting: a flush sends nothing.
    autosave.flush();
    await autosave.idle();
    expect(persist).toHaveBeenCalledTimes(1);
  });

  it("writes nothing after cancel, even when flushed on the way out", async () => {
    const persist = settling("kept");
    const autosave = setup(persist);

    autosave.change("ab");
    autosave.cancel();
    autosave.flush();
    await vi.advanceTimersByTimeAsync(WAIT * 2);
    expect(persist).not.toHaveBeenCalled();
  });

  it("drops a save queued behind a running one on cancel", async () => {
    const { sent, persist, finish } = deferredPersist();
    const autosave = setup(persist);

    autosave.change("ab");
    await vi.advanceTimersByTimeAsync(WAIT);
    autosave.change("abc");
    autosave.flush();
    autosave.cancel();
    await finish();
    await vi.advanceTimersByTimeAsync(WAIT * 2);
    expect(sent).toEqual(["ab"]);
  });

  it("stops telling a listener once it unsubscribes", () => {
    const autosave = setup(async () => "saved");
    const listener = vi.fn();
    const unsubscribe = autosave.subscribe(listener);
    autosave.change("ab");
    unsubscribe();
    autosave.change("a");
    expect(listener).toHaveBeenCalledTimes(1);
  });
});
