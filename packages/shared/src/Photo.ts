import { Schema } from "effect";

// Recipe photos (#12): a client uploads the original, the API stores WebP
// variants, and recipes point at the photo by id.

export const PhotoId = Schema.String.check(Schema.isUUID()).pipe(Schema.brand("PhotoId"));
export type PhotoId = typeof PhotoId.Type;

/** Widths: a list thumbnail, a library card and the recipe page. */
export const PHOTO_VARIANTS = { thumb: 320, card: 800, full: 1920 } as const;
export const PhotoVariant = Schema.Literals(["thumb", "card", "full"]);
export type PhotoVariant = typeof PhotoVariant.Type;

export const PHOTO_MAX_BYTES = 15 * 1024 * 1024;
export const PHOTO_TYPES = ["image/jpeg", "image/png", "image/webp", "image/avif"] as const;
// Not HEIC: the prebuilt sharp can't decode HEVC. Leaving it out of the file
// picker's accept list makes iOS hand over a JPEG instead.

export const PhotoUploadInput = Schema.Struct({
  contentType: Schema.Literals(PHOTO_TYPES),
  size: Schema.Int.check(Schema.isBetween({ minimum: 1, maximum: PHOTO_MAX_BYTES })),
});
export type PhotoUploadInput = typeof PhotoUploadInput.Type;

/** Where to PUT the file: straight to storage when it can sign a URL, else the API. */
export class PhotoUpload extends Schema.Class<PhotoUpload>("PhotoUpload")({
  id: Schema.String,
  url: Schema.String,
  /** Send these headers with the PUT. */
  headers: Schema.Record(Schema.String, Schema.String),
}) {}

export const PhotoFinishInput = Schema.Struct({ uploadId: Schema.String.check(Schema.isUUID()) });

export const PhotoFromUrlInput = Schema.Struct({
  url: Schema.Trim.check(Schema.isMaxLength(2048), Schema.isPattern(/^https?:\/\//i)),
});

export class Photo extends Schema.Class<Photo>("Photo")({
  id: PhotoId,
  width: Schema.Int,
  height: Schema.Int,
}) {}

/** The URL a page shows a photo variant from (served by the API). */
export const photoUrl = (id: string, variant: PhotoVariant) => `/v1/photos/${id}/${variant}`;
