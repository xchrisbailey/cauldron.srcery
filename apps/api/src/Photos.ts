import { schema } from "@cauldron/db";
import {
  copy,
  InvalidRequest,
  NotFound,
  Photo,
  PHOTO_MAX_BYTES,
  PHOTO_VARIANTS,
  PhotoId,
  PhotoUpload,
  type PhotoUploadInput,
  type PhotoVariant,
  type UserId,
} from "@cauldron/shared";
import { and, eq, inArray, lt, sql } from "drizzle-orm";
import { Context, Duration, Effect, Layer, Option, Schedule } from "effect";
import sharp from "sharp";
import { AppConfig } from "./AppConfig.ts";
import { Db } from "./Db.ts";
import { RemoteFetch } from "./RemoteFetch.ts";
import { Storage } from "./Storage.ts";

const { photo, photoUpload, recipe } = schema;

/** Formats sharp may decode. Anything else is refused before resizing. */
const FORMATS = new Set(["jpeg", "png", "webp", "avif", "heif"]);
/** Refuse decompression bombs: about 50 megapixels. */
const MAX_PIXELS = 50_000_000;
/** Uploads and unused photos older than this are cleaned up. */
export const PHOTO_GRACE = Duration.hours(24);

export const uploadKey = (ownerId: string, id: string) => `uploads/${ownerId}/${id}`;
export const variantKey = (ownerId: string, id: string, variant: PhotoVariant) =>
  `photos/${ownerId}/${id}/${variant}.webp`;
const variantKeys = (ownerId: string, id: string) =>
  (Object.keys(PHOTO_VARIANTS) as Array<PhotoVariant>).map((v) => variantKey(ownerId, id, v));

const invalid = (message: string) => new InvalidRequest({ message });
const notFound = () => new NotFound({ message: copy.errors.notFound.text });

/** Decodes, checks and resizes an image into the WebP variants. */
const renderVariants = (bytes: Uint8Array) =>
  Effect.tryPromise({
    try: async () => {
      const image = sharp(bytes, { limitInputPixels: MAX_PIXELS, failOn: "error" });
      const meta = await image.metadata();
      if (!meta.format || !FORMATS.has(meta.format)) return { error: "unsupported" as const };
      // rotate() applies the EXIF orientation, then metadata is dropped.
      const oriented = image.rotate();
      const variants = await Promise.all(
        (Object.entries(PHOTO_VARIANTS) as Array<[PhotoVariant, number]>).map(
          async ([variant, width]) => {
            const out = await oriented
              .clone()
              .resize({ width, withoutEnlargement: true })
              .webp({ quality: 80 })
              .toBuffer({ resolveWithObject: true });
            return { variant, bytes: new Uint8Array(out.data), info: out.info };
          },
        ),
      );
      const full = variants.find((v) => v.variant === "full")!;
      return { variants, width: full.info.width, height: full.info.height };
    },
    catch: (cause) =>
      String(cause).includes("pixel limit")
        ? "tooBig"
        : ("couldntRead" as "tooBig" | "couldntRead"),
  }).pipe(
    Effect.flatMap((result) =>
      "error" in result ? Effect.fail("unsupported" as const) : Effect.succeed(result),
    ),
    Effect.mapError((reason) => invalid(copy.photos[reason].text)),
  );

const make = Effect.gen(function* () {
  const db = yield* Db;
  const storage = yield* Storage;
  const remote = yield* RemoteFetch;
  const { publicUrl } = yield* AppConfig;

  /** Stores the variants of an image and records the photo. */
  const store = Effect.fn("Photos.store")(function* (ownerId: UserId, bytes: Uint8Array) {
    const rendered = yield* renderVariants(bytes);
    const id = crypto.randomUUID();
    for (const v of rendered.variants) {
      yield* storage.put(variantKey(ownerId, id, v.variant), v.bytes, "image/webp");
    }
    yield* db.use((d) =>
      d.insert(photo).values({ id, ownerId, width: rendered.width, height: rendered.height }),
    );
    return new Photo({ id: PhotoId.make(id), width: rendered.width, height: rendered.height });
  });

  const findUpload = Effect.fn("Photos.findUpload")(function* (ownerId: UserId, id: string) {
    const [row] = yield* db.use((d) =>
      d
        .select()
        .from(photoUpload)
        .where(and(eq(photoUpload.id, id), eq(photoUpload.ownerId, ownerId))),
    );
    if (!row) return yield* invalid(copy.photos.uploadExpired.text);
    return row;
  });

  return {
    /** Starts an upload: a URL to PUT the original to, straight to storage when possible. */
    startUpload: Effect.fn("Photos.startUpload")(function* (
      ownerId: UserId,
      input: PhotoUploadInput,
    ) {
      const [row] = yield* db.use((d) =>
        d
          .insert(photoUpload)
          .values({ ownerId, contentType: input.contentType })
          .returning({ id: photoUpload.id }),
      );
      const id = row!.id;
      const signed = yield* storage.signUpload(uploadKey(ownerId, id), input.contentType);
      // A signed URL is bound to the photo's type; the API takes raw bytes.
      return Option.match(signed, {
        onSome: (url) =>
          new PhotoUpload({ id, url, headers: { "content-type": input.contentType } }),
        onNone: () =>
          new PhotoUpload({
            id,
            url: `${publicUrl}/v1/photos/uploads/${id}`,
            headers: { "content-type": "application/octet-stream" },
          }),
      });
    }),

    /** Receives the original when storage can't take it directly. */
    receiveUpload: Effect.fn("Photos.receiveUpload")(function* (
      ownerId: UserId,
      id: string,
      bytes: Uint8Array,
    ) {
      const upload = yield* findUpload(ownerId, id);
      if (bytes.byteLength === 0) return yield* invalid(copy.photos.couldntRead.text);
      if (bytes.byteLength > PHOTO_MAX_BYTES) return yield* invalid(copy.photos.tooLarge.text);
      yield* storage.put(uploadKey(ownerId, id), bytes, upload.contentType);
    }),

    /** Turns a finished upload into a photo and drops the original. */
    finishUpload: Effect.fn("Photos.finishUpload")(function* (ownerId: UserId, id: string) {
      yield* findUpload(ownerId, id);
      const bytes = yield* storage.get(uploadKey(ownerId, id));
      if (!bytes) return yield* invalid(copy.photos.uploadExpired.text);
      if (bytes.byteLength > PHOTO_MAX_BYTES) return yield* invalid(copy.photos.tooLarge.text);
      const stored = yield* store(ownerId, bytes);
      yield* storage.delete([uploadKey(ownerId, id)]);
      yield* db.use((d) => d.delete(photoUpload).where(eq(photoUpload.id, id)));
      return stored;
    }),

    /** For importers: downloads a photo from a source URL on the server. */
    fromUrl: Effect.fn("Photos.fromUrl")(function* (ownerId: UserId, url: string) {
      const fetched = yield* remote
        .get(url, { maxBytes: PHOTO_MAX_BYTES, accept: "image/*" })
        .pipe(
          Effect.mapError((error) =>
            invalid(
              error.reason === "tooLarge"
                ? copy.photos.tooLarge.text
                : copy.photos.couldntFetch.text,
            ),
          ),
        );
      return yield* store(ownerId, fetched.bytes);
    }),

    /** One variant's bytes, for the owner only. */
    read: Effect.fn("Photos.read")(function* (ownerId: UserId, id: PhotoId, variant: PhotoVariant) {
      const [row] = yield* db.use((d) =>
        d
          .select({ id: photo.id })
          .from(photo)
          .where(and(eq(photo.id, id), eq(photo.ownerId, ownerId))),
      );
      if (!row) return yield* notFound();
      const bytes = yield* storage.get(variantKey(ownerId, id, variant));
      if (!bytes) return yield* notFound();
      return bytes;
    }),

    /** Whether the owner has this photo, for recipes that point at one. */
    owns: Effect.fn("Photos.owns")(function* (ownerId: UserId, id: string) {
      const rows = yield* db.use((d) =>
        d
          .select({ id: photo.id })
          .from(photo)
          .where(and(eq(photo.id, id), eq(photo.ownerId, ownerId))),
      );
      return rows.length > 0;
    }),

    /**
     * Removes uploads that were never finished and photos no recipe points at
     * (banished recipes still count, so Undo keeps their photo), once they're
     * older than the grace period.
     */
    cleanup: Effect.fn("Photos.cleanup")(function* (now: Date = new Date()) {
      const before = new Date(now.getTime() - Duration.toMillis(PHOTO_GRACE));
      const stale = yield* db.use((d) =>
        d
          .select({ id: photoUpload.id, ownerId: photoUpload.ownerId })
          .from(photoUpload)
          .where(lt(photoUpload.createdAt, before)),
      );
      if (stale.length > 0) {
        yield* storage.delete(stale.map((u) => uploadKey(u.ownerId, u.id)));
        yield* db.use((d) =>
          d.delete(photoUpload).where(
            inArray(
              photoUpload.id,
              stale.map((u) => u.id),
            ),
          ),
        );
      }
      const orphans = yield* db.use((d) =>
        d
          .select({ id: photo.id, ownerId: photo.ownerId })
          .from(photo)
          .where(
            and(
              lt(photo.createdAt, before),
              sql`not exists (select 1 from ${recipe} where ${recipe.ownerId} = ${photo.ownerId} and ${recipe.photoKey} = ${photo.id}::text)`,
            ),
          ),
      );
      if (orphans.length > 0) {
        yield* storage.delete(orphans.flatMap((p) => variantKeys(p.ownerId, p.id)));
        yield* db.use((d) =>
          d.delete(photo).where(
            inArray(
              photo.id,
              orphans.map((p) => p.id),
            ),
          ),
        );
      }
      return { uploads: stale.length, photos: orphans.length };
    }),
  };
});

export class Photos extends Context.Service<Photos, Effect.Success<typeof make>>()(
  "cauldron/api/Photos",
) {
  static readonly layer = Layer.effect(Photos, make);
}

/** Runs the cleanup hourly in the background for as long as the API is up. */
export const PhotoCleanup = Layer.effectDiscard(
  Effect.gen(function* () {
    const photos = yield* Photos;
    yield* photos.cleanup().pipe(
      Effect.tap((removed) =>
        removed.uploads + removed.photos > 0
          ? Effect.logInfo("Cleaned up photos", removed)
          : Effect.void,
      ),
      Effect.catchCause((cause) => Effect.logWarning("Photo cleanup failed", cause)),
      Effect.repeat(Schedule.spaced("1 hour")),
      Effect.forkScoped,
    );
  }),
);
