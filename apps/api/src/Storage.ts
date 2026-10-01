import { mkdir, rm } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { Config, Context, Effect, Layer, Option, Redacted, Ref, Schema } from "effect";
import { NodeEnv } from "./AppConfig.ts";

// Object storage for photos: S3-compatible in production (the provider is
// picked with hosting, #21), MinIO from docker-compose locally, or a folder on
// disk when neither is set up. Tests keep objects in memory.

export class StorageError extends Schema.TaggedError<StorageError>()("StorageError", {
  cause: Schema.Defect(),
}) {}

/** The objects behind `Storage.layerTest`. */
export class StorageObjects extends Context.Service<
  StorageObjects,
  Ref.Ref<ReadonlyMap<string, Uint8Array>>
>()("cauldron/api/StorageObjects") {}

export class Storage extends Context.Service<
  Storage,
  {
    readonly put: (
      key: string,
      bytes: Uint8Array,
      contentType: string,
    ) => Effect.Effect<void, StorageError>;
    /** The object's bytes, or null when there's no such object. */
    readonly get: (key: string) => Effect.Effect<Uint8Array | null, StorageError>;
    readonly delete: (keys: ReadonlyArray<string>) => Effect.Effect<void, StorageError>;
    /**
     * A URL the browser can PUT the object to directly, valid for a few
     * minutes. None when the backend can't sign one (disk, memory); the API
     * then takes the upload itself.
     */
    readonly signUpload: (
      key: string,
      contentType: string,
    ) => Effect.Effect<Option.Option<string>, StorageError>;
  }
>()("cauldron/api/Storage") {
  static readonly layerS3 = (options: {
    readonly bucket: string;
    readonly endpoint: string | undefined;
    readonly region: string | undefined;
    readonly accessKeyId: string;
    readonly secretAccessKey: Redacted.Redacted<string>;
  }) =>
    Layer.sync(Storage, () => {
      const client = new Bun.S3Client({
        bucket: options.bucket,
        accessKeyId: options.accessKeyId,
        secretAccessKey: Redacted.value(options.secretAccessKey),
        ...(options.endpoint ? { endpoint: options.endpoint } : {}),
        ...(options.region ? { region: options.region } : {}),
      });
      const attempt = <A>(f: () => Promise<A>) =>
        Effect.tryPromise({ try: f, catch: (cause) => new StorageError({ cause }) });
      return Storage.of({
        put: (key, bytes, contentType) =>
          attempt(() => client.write(key, bytes, { type: contentType })).pipe(Effect.asVoid),
        get: (key) =>
          attempt(async () => {
            const file = client.file(key);
            if (!(await file.exists())) return null;
            return new Uint8Array(await file.arrayBuffer());
          }),
        delete: (keys) =>
          attempt(() => Promise.all(keys.map((key) => client.delete(key)))).pipe(Effect.asVoid),
        signUpload: (key, contentType) =>
          Effect.try({
            try: () =>
              Option.some(
                client.presign(key, { method: "PUT", expiresIn: 600, type: contentType }),
              ),
            catch: (cause) => new StorageError({ cause }),
          }),
      });
    });

  /** Objects as files under `dir`. For local development without MinIO. */
  static readonly layerDisk = (dir: string) =>
    Layer.sync(Storage, () => {
      const root = resolve(dir);
      // Keys come from the API, but never let one step outside the folder.
      const pathOf = (key: string) => {
        const path = resolve(join(root, key));
        if (!path.startsWith(`${root}/`)) throw new Error("storage key escapes the folder");
        return path;
      };
      const attempt = <A>(f: () => Promise<A>) =>
        Effect.tryPromise({ try: f, catch: (cause) => new StorageError({ cause }) });
      return Storage.of({
        put: (key, bytes) =>
          attempt(async () => {
            const path = pathOf(key);
            await mkdir(dirname(path), { recursive: true });
            await Bun.write(path, bytes);
          }),
        get: (key) =>
          attempt(async () => {
            const file = Bun.file(pathOf(key));
            return (await file.exists()) ? new Uint8Array(await file.arrayBuffer()) : null;
          }),
        delete: (keys) =>
          attempt(() => Promise.all(keys.map((key) => rm(pathOf(key), { force: true })))).pipe(
            Effect.asVoid,
          ),
        signUpload: () => Effect.succeed(Option.none()),
      });
    });

  /** Objects in memory, for tests. Read them back through `StorageObjects`. */
  static readonly layerTest = Layer.effect(
    Storage,
    Effect.gen(function* () {
      const objects = yield* StorageObjects;
      return Storage.of({
        put: (key, bytes) => Ref.update(objects, (all) => new Map(all).set(key, bytes)),
        get: (key) => Ref.get(objects).pipe(Effect.map((all) => all.get(key) ?? null)),
        delete: (keys) =>
          Ref.update(objects, (all) => {
            const next = new Map(all);
            for (const key of keys) next.delete(key);
            return next;
          }),
        signUpload: () => Effect.succeed(Option.none()),
      });
    }),
  ).pipe(
    Layer.provideMerge(
      Layer.effect(StorageObjects, Ref.make<ReadonlyMap<string, Uint8Array>>(new Map())),
    ),
  );

  /**
   * S3 when S3_BUCKET is set (with S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY and
   * optional S3_ENDPOINT / S3_REGION), otherwise a folder (STORAGE_DIR,
   * default .data/storage). Production requires S3.
   */
  static readonly layer = Layer.unwrap(
    Effect.gen(function* () {
      const bucket = yield* Config.option(Config.String("S3_BUCKET"));
      if (Option.isSome(bucket)) {
        return Storage.layerS3({
          bucket: bucket.value,
          accessKeyId: yield* Config.String("S3_ACCESS_KEY_ID"),
          secretAccessKey: yield* Config.Redacted("S3_SECRET_ACCESS_KEY"),
          endpoint: Option.getOrUndefined(yield* Config.option(Config.String("S3_ENDPOINT"))),
          region: Option.getOrUndefined(yield* Config.option(Config.String("S3_REGION"))),
        });
      }
      if ((yield* NodeEnv) === "production") {
        return yield* Effect.die("S3_BUCKET must be set in production.");
      }
      const dir = yield* Config.String("STORAGE_DIR").pipe(Config.withDefault(".data/storage"));
      return Storage.layerDisk(dir);
    }),
  );
}
