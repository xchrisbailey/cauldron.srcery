import { copy, type Photo, PHOTO_MAX_BYTES, PHOTO_TYPES } from "@cauldron/shared";
import { callApi } from "./api";
import { messageOr } from "./api-failure";

// Uploading a recipe photo: ask the API where to put it, PUT the file there
// (storage directly, or the API), then have the API make the variants.

type PhotoType = (typeof PHOTO_TYPES)[number];
const isPhotoType = (type: string): type is PhotoType =>
  (PHOTO_TYPES as ReadonlyArray<string>).includes(type);

export const PHOTO_ACCEPT = PHOTO_TYPES.join(",");

/** Our own checks, whose message is already plain copy. */
class PhotoRejected extends Error {}

/** The plain message to show for a failed upload; transport errors get the generic one. */
export const photoError = (error: unknown) =>
  error instanceof PhotoRejected ? error.message : messageOr(error, copy.photos.couldntRead.text);

export const uploadPhoto = async (file: File): Promise<Photo> => {
  if (!isPhotoType(file.type)) throw new PhotoRejected(copy.photos.unsupported.text);
  if (file.size > PHOTO_MAX_BYTES) throw new PhotoRejected(copy.photos.tooLarge.text);
  const upload = await callApi((c) =>
    c.photos.startUpload({ payload: { contentType: file.type as PhotoType, size: file.size } }),
  );
  const put = await fetch(upload.url, {
    method: "PUT",
    body: file,
    headers: upload.headers,
    credentials: "same-origin",
  });
  if (!put.ok) throw new PhotoRejected(copy.photos.couldntRead.text);
  return callApi((c) => c.photos.finishUpload({ payload: { uploadId: upload.id } }));
};
